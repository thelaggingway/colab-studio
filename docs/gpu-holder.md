# The GPU holder: one Colab GPU held by this server, not by an agent thread

A held Colab GPU used to live inside an Amp orb: the orb ran `scripts/studio-up.sh` as a supervised
service, which held the port forward and the idle watchdog. An orb is not a stable host. When its
thread paused or crashed, the service died with it, the forward and the watchdog stopped, and Colab
reclaimed the runtime about 20 minutes later.

This is the fix: the same flow runs as a **systemd `--user` service on an always-on server**
(`lucky-fox`, the `agent-hostuplarge` runner), so it survives the agent thread, the logout, and a
reboot. Agent threads only ask for a hold and send jobs to it; they never hold a GPU themselves.

## The three GPUs lost on 2026-11-24

| # | What happened | What stopped | Result |
| --- | --- | --- | --- |
| 1 | The holding thread's orb **paused after an idle turn** | port forward, idle watchdog | Colab reclaimed the A100 about 20 minutes later; units spent for nothing |
| 2 | The holding thread's orb **crashed on `request body length limit exceeded`**, because too many full-size contact-sheet images were in its context | the same two | GPU lost mid-job |
| 3 | Same crash, second time, same cause | the same two | GPU lost again |

All three have one root cause: the process that holds the GPU lived inside the agent's runtime. Two
consequences shaped this design. The holder must not depend on a thread, and worker threads must not
put images in their context (see the rule in `AGENTS.md` and `docs/runbook.md`).

## What runs where

| Where | What | Lifetime |
| --- | --- | --- |
| This server | `colab` CLI and the login, the holder service, the monitor timer, `127.0.0.1:8188` | survives logout and reboot (linger is on) |
| Colab VM | ComfyUI, models, `/content` | until the session is stopped or Colab reclaims it |
| Agent thread (orb or runner) | asks for a hold, submits jobs, reads `scripts/gpu-status.sh` | minutes to hours |

## Setup, once per machine

```bash
bash scripts/bootstrap.sh              # installs the Colab CLI; restores the login from COLAB_OAUTH_TOKEN_B64
bash scripts/login.sh                  # only if there is no stored login: the human opens the link, pastes the code
bash scripts/gpu-holder-install.sh     # installs and enables the services; needs no sudo
```

`login.sh` must be run in a terminal the human can reach (tmux over ssh works). The Google code goes
into that terminal prompt, never into a chat, and the token is never printed or committed.

`gpu-holder-install.sh` writes three units to `~/.config/systemd/user/`, enables the monitor timer, and
enables (does not start) the holder. It also creates `~/.config/colab-studio/alerts.env` to fill in.

## Holding a GPU

```bash
bash scripts/gpu-request.sh h3 minimax-h3 60 60 A100 L4   # session, recipe, grab minutes, idle minutes, GPUs
bash scripts/gpu-status.sh
journalctl --user -u colab-gpu-holder -f                  # GOT=A100, then "comfyui reachable"
```

`gpu-request.sh` writes `~/.config/colab-studio/holder.env`, marks the hold as wanted, and restarts the
holder. It returns at once: the grab (10 to 30 minutes of 503 is normal) happens in the service.

Ending a hold, two different things:

| Command | Effect |
| --- | --- |
| `scripts/gpu-release.sh [session]` | ends the hold: saves outputs to Drive, stops the GPU, clears the marker |
| `systemctl --user stop colab-gpu-holder` | pauses the holder only; the hold stays requested, so the next start or boot adopts the same session |

The idle watchdog (`scripts/idle-stop.sh`, default 60 minutes) ends the hold by itself: it saves the
outputs, stops the session, and the holder clears the marker so nothing re-grabs.

## What the holder does

`scripts/gpu-holder.sh`, in order:

1. **Gate.** Exits at once unless `~/.local/state/colab-studio/desired` exists. That is why the unit can
   be enabled at boot: a machine with no hold starts nothing.
2. **One holder.** A `flock` on `holder.lock`; a second holder exits instead of grabbing a second GPU.
3. **Adopt or grab.** `scripts/grab-gpu.sh` checks `colab sessions` **before every attempt**. If a
   session exists it is adopted and used, never doubled. If a session exists that this machine cannot
   address (started on another machine, so it shows as `[?]`), it stops with exit 3 rather than grabbing
   a second GPU. An adopted session keeps billing anyway, so the holder sets up its own recipe on it.
4. **Set up** with the existing `scripts/studio-up.sh`: balance check, `models.txt`, `HF_TOKEN`, the
   recipe's `remote.sh`, then ComfyUI on `127.0.0.1:8188`.
5. **Keep the forward up.** `scripts/port-forward.sh` re-opens the SSH forward whenever the local port
   stops answering, and exits when the session is gone. Before this, a network blip left the port dead
   while the GPU kept billing.
6. **Hold** with `scripts/idle-stop.sh`, which writes the idle count for `gpu-status.sh` and stops the
   GPU after the idle window.
7. **Report.** Writes `phase` (`starting`, `grabbing`, `holding`, `idle`, `failed`) so the monitor can
   tell "still grabbing" from "GPU lost".

Exit codes: 0 = released by the watchdog or stopped on request (systemd leaves it stopped), non-zero =
failed (systemd retries while the hold is still requested, up to 5 times an hour).

## Status

```bash
$ scripts/gpu-status.sh
session=h3 gpu=A100 count=1 idle=3m rate=6.73/hr balance=174.42 holder=active phase=holding desired=yes
```

| Field | Meaning |
| --- | --- |
| `session` | the session name(s) Colab reports; `-` for none, comma-separated when there are several |
| `gpu` | the accelerator Colab reports |
| `count` | how many sessions exist at all; more than 1 bills more than once |
| `idle` | minutes since ComfyUI last had a job, from the watchdog; `(stale)` if it is not running |
| `rate` | live usage rate in units/hour; the honest number while the balance lags |
| `balance` | current compute units; `?` when not signed in |
| `holder` | systemd state: `active`, `activating`, `inactive`, `failed` |
| `phase` | `starting`, `grabbing`, `holding`, `idle`, `failed` |
| `desired` | `yes` while a hold is requested |

It uses only the free calls (`colab sessions`, `colab usage`), so it costs nothing to run.

## Alerting

`scripts/gpu-monitor.sh` runs from `colab-gpu-monitor.timer` every 5 minutes. It is a shell script in
systemd, not an agent, so a paused or crashed thread cannot silence it. It alerts on:

| Alert | Condition | Action |
| --- | --- | --- |
| `gpu-lost` | a hold is requested, phase is `holding`, and no session exists | alerts, restarts the holder to grab again |
| `holder-down` | the GPU is still up but the holder is not running, so nothing will release it | alerts, restarts the holder |
| `holder-failed` | the holder failed with a hold requested | alerts, restarts it |
| `holder-not-running` | a hold is requested and the holder is stopped | alerts; does not restart (that is deliberate) |
| `many-sessions` | more than one session exists | alerts |
| `unheld-session` | a session runs with no hold requested | alerts |
| `rate-cap` | live rate over `RATE_CAP` (default 12 units/hr) | alerts |
| `spend-cap` | this hold has spent over `SPEND_CAP_UNITS` (default 25) | alerts |

Restarts are capped: at most one per `RESTART_COOLDOWN_MIN` (15) minutes, and never when the balance is
below `MIN_BALANCE`. The same alert repeats at most every `ALERT_REPEAT_MIN` (60) minutes. Everything
also goes to `~/.local/state/colab-studio/monitor.log`, so alerts are visible without a channel.

### Channels this server already has (checked 2026-11-24)

- No `ntfy` binary, no Slack config, no `ALERT_WEBHOOK`-style variable, and no mail transport
  (`msmtp`, `sendmail`, `mail` are all absent). Nothing is preconfigured.
- Amp push notifications (`notify_user`) exist only inside an agent thread, so a systemd timer cannot
  use them.
- What it does have: outbound HTTPS, `curl` and `jq`, Tailscale, and a Cloudflare tunnel already used
  for `webhook.wyrdwerk.com` (shared with other work; not repurposed for this).

**Recommended: an ntfy topic.** No account, no credential, one URL. Pick a long random topic name,
subscribe to it in the ntfy app or at `https://ntfy.sh/<topic>`, and set it in
`~/.config/colab-studio/alerts.env`:

```bash
ALERT_WEBHOOK=https://ntfy.sh/colab-studio-<long-random-topic>
```

A Slack incoming webhook works the same way (the monitor detects `ntfy` in the URL and otherwise posts
Slack's `{"text": ...}` JSON):

```bash
ALERT_WEBHOOK=https://hooks.slack.com/services/T000/B000/xxxx
```

Check the channel once after setting it:

```bash
scripts/gpu-monitor.sh --test     # sends one test alert and prints the status line
```

## Submitting work from an agent thread

The GPU is reachable as `http://127.0.0.1:8188` **on this server**, and as nothing else. Three ways in,
best first:

1. **Run the thread on this server's runner.** It has the GPU on localhost and the repo checked out:

   ```
   create_thread(executor: "runner", runner_id: "agent-hostuplarge",
                 working_directory: "/home/yash/Agent/project/colab-studio")
   ```

   Then use ComfyUI exactly as in `docs/runbook.md` step 6 (`POST /prompt`, poll `/queue` and
   `/history`), and `scripts/colab-ssh.sh <session> ...` for shell work on the VM. No tunnel, no
   credentials, no port forwarding.

2. **From an orb, hand the job to a thread on this runner** with `send_thread_message`: the orb sends
   the prompt and settings, the runner thread queues the work and reports back the output paths. This
   is also the fix for the crash that lost two GPUs: the images and logs stay in the runner thread's
   context, and the orb's context stays small.

3. **Direct HTTP from an orb** needs infrastructure that does not exist yet: Tailscale access from the
   orb (the `tailscale_access` tool) plus a listener bound to the tailnet address, or a Cloudflare
   hostname behind Access. Both are documented options, neither is built or verified. `amp orb portal`
   is not a route here: on a runner thread it answers `Portals are not available for this thread`.

Colab's policy still applies: the port is for the account owner, not for publishing.

## Failure modes

| Symptom | Meaning | What happens |
| --- | --- | --- |
| `no hold requested ...; exiting` | the unit started with no hold | expected after a boot with no hold |
| `2 sessions already exist (...); not grabbing another` | another session is running | holder exits 3; the monitor alerts; stop the extra one |
| `a GPU session is already running but was started on another machine` | a `[?]` session | holder exits 3 rather than doubling; stop it where it was started |
| `balance below MIN_BALANCE` | broke | no grab; top up or wait for the monthly reset |
| `holder failed (rc=1)` | grab window closed, or setup failed | systemd retries up to 5 times an hour, then the monitor alerts |
| `port 8188 is down; re-opening the forward` | a network blip or a dead VM | the keeper re-opens it; a dead VM ends it |
| `gpu-lost` alert | Colab reclaimed the runtime | monitor restarts the holder, which grabs again |
| `holder-down` alert | the GPU is up with no watchdog | monitor restarts the holder, which adopts the session |
| `idle=... (stale)` in status | the watchdog is not writing | the holder is not holding; check `holder=` and `phase=` |
| After a reboot, no GPU | Colab dropped the session while the server was down | the holder grabs again; the monitor alerts in the meantime |

## Files and state

| Path | What |
| --- | --- |
| `scripts/gpu-holder.sh` | the service: gate, adopt-or-grab, hold, release |
| `scripts/gpu-request.sh` | request a hold (writes `holder.env`, marks it wanted, restarts the unit) |
| `scripts/gpu-release.sh` | end a hold: save outputs, stop the GPU, clear the marker |
| `scripts/gpu-status.sh` | the one-line status |
| `scripts/gpu-monitor.sh` | the checks and alerts (`--test` to check the channel) |
| `scripts/gpu-holder-install.sh` | install the units, enable the timer |
| `scripts/port-forward.sh` | keeps `127.0.0.1:8188` alive |
| `config/systemd/*` | the unit templates (`@REPO@` is filled in by the installer) |
| `~/.config/colab-studio/holder.env` | what to hold: session, recipe, minutes, GPUs |
| `~/.config/colab-studio/alerts.env` | webhook and caps |
| `~/.local/state/colab-studio/desired` | the hold is wanted |
| `~/.local/state/colab-studio/{session,phase,idle,balance_start,released}` | what the holder is doing |
| `~/.local/state/colab-studio/{monitor.log,grab.log}` | alerts and the last grab |
| `~/.local/state/colab-studio/alert-*`, `last_restart` | dedup and restart cooldown |

## Tested without a GPU

Everything except the GPU itself, with a fake `colab` CLI, a fake ComfyUI on port 8199, and a local
HTTP receiver standing in for the webhook:

- the guard: no session → grab; existing named session → adopt, `colab new` never called; `[?]` and
  two-session cases → exit 3, no grab;
- the holder: no hold → exits 0; unknown recipe → exit 2; no GPU available → non-zero and `phase=failed`;
  adopt → records the session and balance, stops the session when setup fails;
- the watchdog: writes `idle`, stops after the window, writes `released`;
- the port-forward keeper: re-opens a dead forward, exits when the session is gone;
- release: clears the marker, saves, stops, cleans the state;
- the monitor: every alert above, dedup, restart cooldown, ntfy-style and Slack-style sends;
- systemd: the holder starts and exits 0 with no hold; the timer fires.

Still to prove on a real GPU (one short T4 hold): grab, recipe setup, ComfyUI on 8188 through the
keeper, a job, the watchdog release, and `gpu-status.sh` during all of it.

## Open questions

- **Does an idle runner alone keep the GPU alive?** Still not proven; see
  [amp-runner-on-colab.md](amp-runner-on-colab.md).
- **A reboot while holding** should adopt the same session if Colab still has it; untested, because it
  needs a reboot.
- **Direct HTTP from an orb** needs Tailscale or Cloudflare work, and approval for the shared tunnel.
- **Two holders on two machines** would race; the guard narrows it (each sees the other's session and
  refuses to double), but there is still a window between `colab sessions` and `colab new`.
