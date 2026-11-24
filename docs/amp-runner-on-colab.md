# Amp runner on a Colab GPU

Tested in **Amp** (ampcode.com) on 2026-11-24, on a Colab T4 on Google AI Pro. Amp-specific: other
agents (Claude Code, Codex) have their own remote modes and are not covered here. The rest of the repo
still works without Amp; see [other-systems.md](other-systems.md).

## Why

The default setup drives the GPU from an Amp orb over `colab ssh`. Two things went wrong with that:

- **An orb that pauses loses the GPU.** An orb pauses when its thread goes idle. That stops the idle
  watchdog and the SSH/port-forward connection, and Colab's own idle timeout then reclaimed the runtime
  about 20 minutes later. A held A100 was lost this way before its job started, after about 4 units
  were spent on nothing. The thread holding a GPU must stay inside its turn (polling, `sleep`), or the
  GPU must be held from somewhere that does not pause.
- **The SSH plumbing is fragile:** one SSH connection per runtime (a second gets HTTP 429), a supervised
  port-forward service, and `colab download` round trips for every output.

An Amp runner (`amp --no-tui`) started **on the Colab VM itself** lets Amp threads run directly on the
GPU machine, with ComfyUI on `localhost` and files on local disk.

## Setup (about 2 minutes after the GPU is assigned)

From the orb that owns the Colab session (named `t4test` here):

```bash
# 1. Install Amp on the VM (Colab runs as root; installs to /root/.local/bin)
bash scripts/colab-ssh.sh t4test 'curl -fsSL https://ampcode.com/install.sh | bash'

# 2. Sign in with the device flow, in tmux so it survives the SSH call
bash scripts/colab-ssh.sh t4test 'export PATH="$HOME/.local/bin:$PATH";
  tmux new-session -d -s login "amp login 2>&1 | tee /tmp/amp-login.log; sleep 1800";
  sleep 8; cat /tmp/amp-login.log'
#    -> prints https://ampcode.com/auth/cli/device?user_code=XXX-XXX-XXX
#    The human opens it in their own browser and approves. The code expires after a few minutes;
#    re-run step 2 for a new one.

# 3. Start the runner in a served directory
bash scripts/colab-ssh.sh t4test 'export PATH="$HOME/.local/bin:$PATH";
  mkdir -p /content/studio && cd /content/studio && git init -q;
  tmux new-session -d -s runner "cd /content/studio && amp --no-tui --runner-id colab-<gpu>-<name> --remote-control-terminal 2>&1 | tee /tmp/runner.log"'
```

`/content/studio` starts empty. The first runner thread clones this repo into it
(`git clone https://github.com/<owner>/colab-studio /content/studio/colab-studio`; a private repo needs a
GitHub token on the VM) and runs VM-side scripts such as `recipes/minimax-h3/remote.sh` from there.

Within about 15 s the log says `Registered as <account>` and the runner appears in Amp's runner list.
Create threads on it from ampcode.com (pick the runner as the location) or with `create_thread`
(`executor: runner`, `runner_id`, `working_directory: /content/studio`).

Flags worth adding:

- `--remote-control-portals`: gives runner threads a Portal tab, so a human can open ComfyUI's UI.
  (Not used in the test; without it there is no way for a person to open port 8188.)
- `--remote-control-terminal`: the thread's Terminal tab (needs tmux, which Colab has).
- Do **not** use `--share-network`: it routes orb traffic through the VM, which Colab's policy forbids
  (no proxies). Do not use `--share` either.

## Measured on the T4 (2026-11-24)

The whole session ran from **08:25 to 10:21 UTC**, about **2.2 units at 1.15 units/hour**. It was
stopped deliberately by a scheduled cleanup, not by Colab: the runtime never dropped on its own while
the runner was up.

A runner thread did the full setup on the VM itself, with no SSH, in 2 min 48 s:

| Step | Time | Notes |
| --- | --- | --- |
| Install Amp | under 30 s | |
| Sign in | as long as the human takes | device-flow link; the first link timed out unused |
| Runner registered | about 15 s | |
| Environment check | 30 s | T4 15 GB, torch with CUDA, Python 3.13; GitHub, Hugging Face and PyPI reachable |
| `recipes/minimax-h3/remote.sh` (own `models.txt`) | about 90 s | clone 1 s, apt 23 s (installs `aria2c`, which Colab lacks), download 35 s, pip 18 s (uv); ComfyUI answered on 127.0.0.1:8188 |
| SDXL-Turbo, 6.5 GB, then one 512x512 image | 35 s + 32 s | about 190 MB/s download, 7 GB VRAM, 9.5 of 12.7 GB RAM |

The repo's VM-side scripts ran unchanged on the VM. The orb-side tools (`colab`, `colab-ssh.sh`,
`studio-up.sh`, `idle-stop.sh`) are not used there.

## Trade-offs

Better with the runner on the VM:

- No SSH limit, no ControlMaster, no port forward: the agent calls `localhost:8188` directly.
- Weights, logs and outputs are local files; no `colab download`/`ls` round trips.
- Setup timings and logs are greppable in place.
- The agent's work does not depend on an orb staying awake.

Worse, or still needed:

- **Billing and release are unchanged.** The GPU bills every minute it exists. Something still has to
  release it. `colab stop` works only from the orb that started the session (or one given its
  `~/.config/colab-cli/sessions.json`). An on-VM release path is untested.
- **Secrets do not follow.** The runner sees only its own environment. `HF_TOKEN` is missing, so gated
  models (for example LTX-2.5) cannot download. `amp --no-tui --amp-env` would pull every personal Amp
  secret onto a shared Google VM, so prefer passing only `HF_TOKEN` into the runner's environment
  (open item). Amp proxy secrets (placeholder headers swapped by Amp's secret proxy) exist only in
  orbs, so API calls that rely on them, such as ElevenLabs voiceovers, stay on an orb.
- **The machine is fixed.** The standard T4 VM has 12.7 GB of RAM, so H3, LTX-2.5 and other large
  models cannot load there; use an A100 (83 GB RAM) or a high-RAM shape.
- **Everything in `/content` dies with the runtime**, including the Amp login. Copy outputs off first.
- **Process hygiene:** the runner and its threads share the VM. Do not kill the `runner` tmux session or
  run `tmux kill-server` from a runner thread.
- **Login approval** is a human step on every new runtime.

## Cleanup (every time)

When the work ends, the thread is archived, or the owner says so:

1. From the owning orb: `bash scripts/colab-ssh.sh <session> 'tmux kill-server'` (stops the runner and
   ComfyUI), then `colab stop -s <session>`, then confirm with `colab sessions`.
2. Check Amp's runner list. A stopped runner shows as offline; Amp has no tool for agents to delete a
   runner, so remove a lingering entry in Amp's settings by hand.
3. The Amp login on the VM is erased with the runtime. To be sure, revoke the CLI session from Amp's
   security settings.

## Open question: does an idle runner keep the GPU alive?

Colab says sessions stay alive while the kernel is active. The runner is a separate process, so Colab
may still treat the runtime as idle and reclaim it. Observed so far:

- A GPU stayed up while a thread was working on it, and was reclaimed about 20 minutes after the orb
  driving it paused.
- On 2026-11-24 the T4 stayed up for the whole 08:25 to 10:21 UTC session, including **about 55
  minutes with no job running (08:46 to 09:41)**. That is not proof that an idle runner holds the GPU:
  the orb kept running `colab` commands against the session throughout (status, sessions, usage), so
  the runtime was never left alone for the 20 minutes that a reclaim takes.

So the question is still open. To answer it, leave a runner-only session completely untouched for 30
minutes and watch `colab sessions` from another machine. Until then, treat the GPU as something that
must be held by a machine that stays up, not by a runner alone; `docs/gpu-holder.md` is that machine.

