# Runbook: one Colab GPU session, end to end

Follow the steps in order. Each one gives the exact command, what success looks like, and what to do
when it does not. Rules that apply throughout are in [AGENTS.md](../AGENTS.md).

The path: restore the login, check the balance, get a GPU in the background, set up a recipe, open
ComfyUI, generate, copy the outputs back, release the GPU, report the units.

Budget in one line: Google AI Pro, 200 units a month. A100 is 6.73 units/hour, L4 about 1.9, T4 about
1.5, G4 about 10 (see [per-GPU notes](#9-per-gpu-notes)). A held GPU bills every minute, so steps 3
and 8 matter as much as the generation.

## Quick path (the usual case: the machine that holds GPUs)

```bash
bash scripts/bootstrap.sh                                  # once per machine; restores the login
source config/account.env && colab usage                   # read-only; stop if below MIN_BALANCE
bash scripts/gpu-request.sh h3 minimax-h3 60 60 A100 G4    # returns at once; systemd does the grab
bash scripts/gpu-status.sh                                 # repeat until it says phase=holding
curl -s http://127.0.0.1:8188/system_stats                 # ComfyUI, on that machine
# generate (step 6), copy outputs back (step 7)
bash scripts/gpu-release.sh h3                             # or let the watchdog do it (step 8)
colab sessions && colab usage                              # confirm, then report units
```

`gpu-request.sh` is the durable route: the GPU is held by a systemd service on that machine, so it
survives the agent thread, a logout, and a reboot. See [gpu-holder.md](gpu-holder.md), including how a
thread on another machine (an orb) submits work to it. The orb-service route in step 3 still works on a
machine without the holder.

Everything below explains each of those, plus the manual route when there is no orb.

## 0. Before you start

- You are in the repo root. `scripts/bootstrap.sh` has run (Amp orbs run `.agents/setup`, which runs it).
- Reading, planning, and these three commands are free and do not start a GPU:
  `colab sessions`, `colab whoami`, `colab usage`. Everything that creates a runtime bills from the
  moment it exists.
- Never wait for a busy GPU in the conversation that is doing other work. Hand the wait to a service
  or a child thread (step 3).
- Check the recipe's licence before generating for a client: MiniMax H3's community licence excludes
  use in the US, EU, UK, and South Korea. The recipe README has the details.

## 1. Restore the login

```bash
bash scripts/bootstrap.sh
colab whoami
```

Expected: `[bootstrap] restored Colab login from COLAB_OAUTH_TOKEN_B64`, then `[bootstrap] installed:
Version: 0.8.0`, then `[bootstrap] login ok: ...`. `colab whoami` prints `Auth provider: oauth2`,
`Email: ...`, and a `Scopes:` list that contains `/auth/colaboratory`, `/auth/cloud-platform`, and
`/auth/drive.file`. It never prints the token.

`colab sessions` is the other free check: it prints `[colab] No active sessions found on server.` or
one line per running session.

**If the login is missing** (`Warning: Could not read the OAuth token from the OS keyring`, or a
sign-in link appears):

1. Run `scripts/login.sh`. The CLI prints:
   ```
   To authorize colab-cli, visit this URL in any browser:
     https://accounts.google.com/o/oauth2/auth?...
   After approving, Google will display an authorization code.
   Enter the authorization code:
   ```
2. Open that URL in the **user's own browser**, signed in to the Google account that holds the Colab
   plan. Do not use the orb browser: Google's number-match 2FA expires before a remote browser
   renders the prompt, so that route fails.
3. Paste the code from Google's page at the prompt in the terminal (the Amp Terminal tab in an orb).
   Never paste it into a chat.
4. Store the login for other machines: `scripts/login.sh --export` prints one base64 line. Put it in
   the secret `COLAB_OAUTH_TOKEN_B64` (Amp: project secret; elsewhere: that machine's secret store).
   Never print, log, or commit it. On macOS the Keychain alone is enough.

The token can read Drive files it creates (`drive.file`) and use `cloud-platform`; it is the account's
own login. Revoke it at myaccount.google.com > Security > Third-party connections > Google Cloud SDK.

## 2. Check the balance

```bash
source config/account.env
colab usage
```

Expected (values vary):

```
Current balance: 196.59 compute units
Usage rate: 8.67/hr
Active assignments: 2
```

- Stop if the balance is below `MIN_BALANCE` (20). `scripts/studio-up.sh` enforces this itself.
- `Usage rate` is live. While one GPU runs it is that GPU's rate: this is how the A100's 6.73/hr was
  measured. Two sessions add up (A100 + L4 showed 8.67/hr).
- The balance lags a few minutes behind real spend. Do not conclude "it is free" from an unchanged
  balance; check the rate and the clock, and re-read the balance at the end. Example: with two sessions
  at 8.67/hr the balance went 197.31 to 195.16 in about 15 minutes, which is the 2.2 units the rate
  predicts.
- Rough unit costs on an A100: 6 minutes of setup ≈ 0.67, a 864×480 5.2 s H3 clip ≈ 0.22, a 1280×736
  10.1 s clip ≈ 0.64, one idle hour = 6.73. 200 units is about 29 A100 hours or 100 L4 hours.

## 3. Get a GPU (requisition)

GPUs are often busy and answer HTTP 503 for 10 to 30 minutes at a time (worst in the India evening,
around 15:30-16:00 UTC). That is capacity, not a refusal, and it costs nothing.

**On the machine that holds GPUs** (the always-on server: a thread on it, or ssh to it), ask its
holder service and return at once:

```bash
bash scripts/gpu-request.sh h3 minimax-h3 60 60 A100 G4
bash scripts/gpu-status.sh        # repeat: phase=grabbing, then phase=holding
```

The grab, the recipe setup, the port forward and the idle watchdog all run under systemd, so they
survive this thread, a logout, and a reboot; the monitor alerts if the GPU is lost. Full design,
status fields and failure modes: [gpu-holder.md](gpu-holder.md). Never run a second grab from an orb
for the same account: it would double the sessions, and an orb that pauses loses its GPU.

**In an Amp orb** (a machine without the holder), start the whole grab-and-set-up as a supervised
service, then keep working:

```bash
amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
amp orb service logs -n 20 studio-h3 2>&1 | grep -v 'systemd\[' | sed 's/.*studio-h3\[[0-9]*\]: //'
```

Expected start output:

```
studio-h3: started, port 30276
Manage with: amp orb service stop studio-h3 | amp orb service restart studio-h3
```

Expected log while waiting (one line per attempt, then setup):

```
15:46:49 A100 busy (503)
15:48:00 G4 busy (503)
15:49:12 A100 busy (503)
...
15:55:53 GOT=A100
15:55:53 gpu assigned; usage now:
Current balance: 195.20 compute units
Usage rate: 6.73/hr
```

`colab sessions` on this machine then shows `[h3] gpu-a100-s-... | Hardware: A100 | Shape: Standard |
Variant: GPU`.

**If you are delegating**, give a child thread or subagent this job: run `studio-up.sh` as above, send
the parent one message when the GPU is assigned (GPU type, time, balance) and one when the job is done
or failed (outputs, units, session state). The orchestrating conversation never blocks on the wait.

**Worker threads: keep images out of the context.** Look at an image only through `view_media` with an
objective that says what to check ("does the can label show letters?"), and never attach, paste, or
re-read full-size images, contact sheets, or frame sheets into the conversation. Two GPUs were lost on
2026-11-24 because the holding thread crashed on `request body length limit exceeded` with contact
sheets in its context. A worker reports at each milestone instead: GPU assigned, job done or failed,
GPU released.

**Manual, one GPU, no recipe** (bills from here):

```bash
colab new -s <name> --gpu A100
```

Expected: `[colab] Creating session '<name>'...` then `[colab] Session READY.`

**What the failure looks like, and what it means:**

| Output | Meaning | Do |
| --- | --- | --- |
| `...accelerator=A100: Service Unavailable` (HTTP 503) | The GPU type is busy | Keep waiting, or try the next GPU. `grab-gpu.sh` does this for you. |
| `[colab] Allocation refused (precondition failed)...` (HTTP 412) | Too many active sessions, or a temporary limit | `colab sessions`, stop a session you started, retry. |
| `[colab] Backend rejected accelerator 'H100'...` (HTTP 400) | Not entitled | Do not retry; use A100, G4, L4 or T4. |
| `no GPU after 60m (tried A100 G4)` | The window closed with every GPU busy | Try later, or a cheaper GPU (L4, T4). |

Do not raise `COLAB_CLI_ASSIGN_RETRIES`: the CLI waits `backoff * 2^n` between retries, so 10 retries
from 20 s is about 5.7 hours on one GPU. `grab-gpu.sh` uses one retry per attempt and loops itself.

GPU order: for MiniMax H3 and anything near 24 GB of weights `A100 G4 L4`; for models that fit in about
22 GB `L4 T4` (a quarter of the price). `config/account.env` names these `GPU` and `GPU_SMALL`. G4 has
been busy on every attempt so far.

## 4. Set up the recipe

`scripts/studio-up.sh` does all of this after the GPU is assigned:

1. reads the balance and prints the live rate,
2. copies `recipes/<recipe>/models.txt` to `/content/models.txt`,
3. forwards `HF_TOKEN` (if set) to `/content/.hf_token`,
4. runs `recipes/<recipe>/remote.sh` on the VM through `scripts/colab-ssh.sh`,
5. forwards port 8188 and waits for ComfyUI,
6. runs `scripts/idle-stop.sh` to hold and later release the GPU.

Expected for `recipes/minimax-h3` on an A100. The 2026-11-23 run with the older script took 324 s
end to end, 128 s of it the download. The current script prints one line per phase:

```
clone_seconds=5
apt_seconds=NN      # unmeasured on Colab
download_seconds=128
pip_seconds=NN      # uv; unmeasured on Colab
comfyui started
16:01:17 setup done in 324s
16:01:53 comfyui reachable on 127.0.0.1:8188 after 360s
16:01:54 busy=0 idle=0m
```

The 324 s and 360 s totals are from the older script; the phase lines replace the guesswork about
where that time went. What is measured and what is not:

- `clone_seconds`: `git clone --depth 1` of ComfyUI is 64 MB; measured at 4.9 s.
- `pip_seconds`: the dependency install now uses `uv pip install --system` (falling back to pip).
  Measured here in clean environments with the same requirements and torch already present: 63 s
  with uv against 177 s with pip, for the same 106 packages.
- `download_seconds`: 128 s for the 42 GB H3 set on the 2026-11-23 run.
- `apt_seconds` and the Colab-side `pip_seconds` are new and unmeasured. The next real run fills
  them in from the log; record them in [recipes/minimax-h3/README.md](../recipes/minimax-h3/README.md).
- The phases that can overlap do: the clone runs first because the model folders live inside it,
  then the dependency install and the download run at the same time. `pip_seconds` is the install
  alone; `setup done in Ns` is the total.

`debconf: ...` and `dpkg-preconfigure: unable to re-open stdin:` are harmless. If setup fails,
`studio-up.sh` stops the GPU so it stops billing (`STUDIO_KEEP=1` leaves it up for debugging).

**The same steps by hand**, when you want to run them one at a time:

```bash
bash scripts/colab-ssh.sh <name> 'cat > /content/models.txt' < recipes/<recipe>/models.txt
bash scripts/colab-ssh.sh <name> 'bash -s' < recipes/<recipe>/remote.sh
bash scripts/colab-ssh.sh <name> -f -N -L 8188:localhost:8188
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8188/     # expect 200
```

Rules for the VM side:

- **One SSH connection per runtime.** A second `colab ssh` gets `Already-active SSH session (HTTP 429)`.
  Always go through `scripts/colab-ssh.sh`; it shares one ControlMaster connection with the port
  forward. If something else (an IDE, a bare `colab ssh`) is attached, close it first.
- **Download on the VM, not through this machine.** `aria2c` from Hugging Face into `/content` is fast
  (42 GB in 128 s on the A100). Do not route weights through Drive or a laptop.
- **`out=<filename>` per URL** in `models.txt`. Without it, Hugging Face redirects save files under
  hash names and ComfyUI then reports "Missing Models".
- **Gated models need `HF_TOKEN`.** `studio-up.sh` forwards it to `/content/.hf_token`; a recipe's
  `remote.sh` reads that file and adds `--header="Authorization: Bearer $(cat /content/.hf_token)"`
  (see `recipes/minimax-h3/remote.sh`). On other systems export `HF_TOKEN` before running, and never
  log it. Public models work without it.
- **Check that the files are where the workflow expects them** before generating. `remote.sh` fails
  loudly if a file named in `models.txt` is missing.

## 5. Open ComfyUI

```bash
amp orb portal 8188 --title 'ComfyUI'
```

Expected: a note that port 8188 is not an orb service (normal), then the portal URL. Give that URL to
the user. It is for the account owner only, not for publishing.

Sanity check from this machine:

```bash
curl -s http://127.0.0.1:8188/system_stats
```

Expected JSON with `"comfyui_version": "0.46.0"`, `"pytorch_version": "2.14.1+cu130"` and the device,
for example `cuda:0 NVIDIA A100-SXM4-40GB`. The VM already has Python 3.13, PyTorch 2.14.1+cu130, about
83 GB of RAM and 236 GB of disk on the A100. ComfyUI installs on that preinstalled torch in about a
minute; do not install another torch.

**Phones:** the ComfyUI editor is a heavy desktop web app and often renders blank on a phone. Tell the
user to use a laptop, and give direct output links (step 7) instead of the editor.

Outside Amp there is no portal: the forwarded port is `http://127.0.0.1:8188` on that machine.

## 6. Generate

Two routes. For an agent, the API route is the reliable one.

**UI route:** open the portal, load the recipe's template (for MiniMax H3: "MiniMax H3: Text to
Video"), set the widgets, press Run. Templates that use subgraphs are easiest to queue this way once;
after that, use the API route below.

**API route:** POST an API-format prompt to `/prompt`. Take the API format from `/history` of a real UI
run rather than hand-editing subgraph widgets: each history entry's `prompt` field is
`[number, prompt_id, prompt, extra_data, outputs]`, so the API prompt is `v["prompt"][2]`.
`recipes/minimax-h3/t2v-api.json` is one, already exported. Then:

```bash
python3 - <<'PY'
import json, urllib.request
p = json.load(open("recipes/minimax-h3/t2v-api.json"))
p["140:131"]["inputs"]["prompt"] = "a paper boat on a rainy street, quiet piano"
p["140:129"]["inputs"]["noise_seed"] = 1
req = urllib.request.Request("http://127.0.0.1:8188/prompt",
                             json.dumps({"prompt": p}).encode(),
                             {"Content-Type": "application/json"})
print(urllib.request.urlopen(req).read().decode())
PY
```

Expected: `{"prompt_id": "...", "number": 1, ...}`. Then watch it:

```bash
curl -s http://127.0.0.1:8188/queue                  # queue_running / queue_pending
curl -s 'http://127.0.0.1:8188/history?max_items=1'  # done when the new prompt is here
```

Knobs for the H3 prompt are in [recipes/minimax-h3/README.md](../recipes/minimax-h3/README.md):
`115` megapixels (0.4 = 864×480, 0.9 = 1280×736), `140:133` seconds, `140:139` true = 8-step turbo,
`140:131` prompt, `140:129` seed (`noise_seed`).

**Gotcha:** the template's `ResolutionSelector` (`115`) overrides width and height. A request for
"5 s at 1344×768" actually rendered 864×480 at the default 0.4 MP.

**ComfyUI says "5 issues found" / "Missing Models":** the filenames on the VM do not match the
workflow. Almost always the aria2 hash-name bug (no `out=`), or a file in the wrong `models/`
subfolder. Check with `colab ls -s <name> /content/ComfyUI/models/diffusion_models`.

## 7. Collect the outputs

`/content` is erased when the runtime stops, so copy results back before step 8.

```bash
colab ls -s <name> /content/ComfyUI/output/video
mkdir -p outputs          # the CLI writes the file directly, so its folder must exist
colab download -s <name> /content/ComfyUI/output/video/MiniMax_H3_00001_.mp4 outputs/MiniMax_H3_00001_.mp4
```

Expected: `[colab] Downloaded '/content/...mp4' to 'outputs/...mp4'`. `outputs/` is git-ignored.

- `colab download` copies **one file** and takes a full local path. A directory as the local path fails
  with `[colab] Download failed: [Errno 21] Is a directory`. For a whole folder, tar it on the VM first:
  ```bash
  bash scripts/colab-ssh.sh <name> 'tar -C /content/ComfyUI/output -czf /content/output.tgz .'
  mkdir -p outputs
  colab download -s <name> /content/output.tgz outputs/output.tgz
  ```
- **Give the user direct links**, which play in any browser and work on a phone:
  `<portal-url>/view?filename=<file>&subfolder=video&type=output`
- Copy what matters into `.amp/in/artifacts/` so it survives the GPU stopping, and embed it in the
  reply. A stopped runtime takes its `/view` links with it.

### Save outputs to Google Drive

```bash
scripts/drive-save.sh <session>          # <DRIVE_FOLDER>/outputs/<date>/<session>/
```

It lists `/content/ComfyUI/output` over ssh, downloads each file with `colab download`, and uploads
it with the restored login, so no browser and no per-session consent. It prints the folder link and
one line per file. The token never leaves the keyring.

It needs `DRIVE_QUOTA_PROJECT` in `config/account.env`: the Drive API refuses this login without a
quota project (Google's message: "the drive.googleapis.com API requires a quota project"). Once:

1. Create a project at https://console.cloud.google.com/projectcreate (no billing needed).
2. Enable the Drive API at https://console.cloud.google.com/apis/library/drive.googleapis.com.
3. Put its id in `DRIVE_QUOTA_PROJECT`.

This account's project is already set in `config/account.env`, so Drive saving works as is.
With `DRIVE_SAVE=auto` (the default) and no project, the script prints that it skipped and exits 0.
`DRIVE_SAVE=1` forces an attempt, `DRIVE_SAVE=0` turns it off. The idle watchdog calls it before
stopping the GPU (step 8), capped at 15 minutes so a slow upload cannot hold the GPU forever.

## 8. Release the GPU and report

The watchdog that `studio-up.sh` starts stops the GPU after `<idle_minutes>` without a ComfyUI job,
saving the outputs to Drive first when it is configured:

```
17:12:31 busy=0 idle=60m
idle for 60m, stopping h3
drive-save: copied 3 file(s) from h3:/content/ComfyUI/output
folder: https://drive.google.com/drive/folders/...
[colab] Stopping session 'h3'...
[colab] Session terminated.
[colab] No active sessions found on server.
Current balance: 188.04 compute units
Usage rate: 0.00/hr
```

Or stop it yourself when the work is done, including after errors:

```bash
colab stop -s <name>
colab sessions
colab usage
```

Expected: `[colab] Stopping session '<name>'...`, `[colab] Session terminated.`, then
`[colab] No active sessions found on server.` and the new balance. If `studio-up.sh` was running as a
service, also run `amp orb service stop studio-<name>`: after the watchdog releases the GPU the service
parks instead of exiting, and a restart would grab a fresh GPU.

- **Do not rely on the watchdog alone.** It runs on this machine; if the orb is paused or killed it
  cannot stop the GPU, and Colab's own idle timeout is the only backstop. A 60-minute idle window can
  burn about 6.7 A100 units. If you stop the GPU by hand, run `scripts/drive-save.sh <name>` first,
  or the outputs go with `/content`.
- **On the holder machine, end a hold with `scripts/gpu-release.sh <name>`.** It saves the outputs,
  stops the GPU and clears the hold. `systemctl --user stop colab-gpu-holder` only pauses the holder:
  the hold stays requested, so the next start or boot adopts the same session again. When the watchdog
  releases the GPU, the holder clears the hold by itself.
- **Pro has no guaranteed background execution** (Ultra does). A long job needs this machine, and its
  port forward, connected until the job finishes; otherwise reattach and check `/history`.
- **Sessions belong to the thread that started them.** In a fresh orb, `colab sessions` can show
  `[?] gpu-... | Hardware: A100 ...` entries with no name: those are other threads' sessions and
  cannot be stopped by name from here. Leave them alone.
- **Report** the balance before and after, the usage rate, how long the GPU was held, the units spent,
  and which sessions are still running and why. The balance delta is the honest number; the rate times
  the wall clock is the estimate while the balance still lags.

## 9. Per-GPU notes

| GPU | Memory | Unit rate | Status here | Use it for |
| --- | --- | --- | --- | --- |
| A100 | 40 GB SXM4 (not 80), 83 GB RAM, 236 GB disk | 6.73/hr measured | Granted repeatedly; the H3 workhorse | Video and anything near or above 24 GB of weights |
| G4 | 96 GB | ~10/hr, from the X post (not measured here) | Entitled, but 503 on every attempt so far | H3 at higher resolution or longer clips, when you can get one |
| L4 | 24 GB (23,034 MiB) | ~1.9/hr (implied by 8.67/hr with the A100) | Granted | Models up to about 22 GB: images, speech, music, 3D |
| T4 | 16 GB (15,360 MiB) | ~1.1-1.8/hr (community) | Granted | Cheapest; small models and smoke tests. Old Turing card: no bf16/fp8 compute |
| TPU v6e1 / v5e1 | - | - | Eligible, never used here (`colab new -s <name> --tpu v6e1`) | Training and batch jobs. ComfyUI needs CUDA, so not the studio |
| H100 | - | - | Not entitled (`Backend rejected accelerator`) | - |

Measured on the A100 (2026-11-23, rate 6.73/hr): setup 324 s; 864×480 5.2 s clip 118 s; 1280×736
10.1 s clip with the 8-step turbo LoRA 344 s at 39 s/step. VRAM peaked at 40.1 GB of 40 GB, so longer
or larger H3 clips spill to system RAM and slow down on the A100; G4's 96 GB is the reason to want one.
L4 and T4 H3 numbers are in [recipes/minimax-h3/README.md](../recipes/minimax-h3/README.md).

Which model and workflow fits each GPU, area by area (images, video, upscaling, music, speech, 3D,
training), is in [workflows.md](workflows.md).

Two sessions can run at once on this account (A100 + L4 on 2026-11-23), but each bills, and the rates
add up. Prefer one.

## 10. Failure signatures

| Signature | Meaning | Fix |
| --- | --- | --- |
| `Service Unavailable` on `POST /tun/m/assign` (503) | GPU type busy | Wait; `grab-gpu.sh` retries; try the next GPU. 10-30 min spells are normal. |
| `[colab] Allocation refused (precondition failed)` (412) | Too many sessions, or a temporary limit | `colab sessions`; stop a session you started; retry or pick another GPU. |
| `[colab] Backend rejected accelerator 'H100'` (400) | Not entitled | Use A100/G4/L4/T4. |
| `Already-active SSH session (HTTP 429)` | A second SSH connection to the runtime | Use `scripts/colab-ssh.sh`; close other `colab ssh`/IDE connections. |
| `SSH session limit reached (HTTP 429): N of N` | The plan's SSH limit for that runtime | Close the other connections; one is enough through the shared master. |
| `Endpoint not found (HTTP 404) ... does not expose the /colab/ssh endpoint` | Runtime without SSH | `colab stop` then `colab new`. |
| `-- No entries --` from `amp orb service logs` | Ran without `-n`, or from another folder | Run from the repo root: `amp orb service logs -n 20 studio-h3`. |
| `Unit amp-svc-...service could not be found. Service <name> runs for <path>; run this command from that folder.` | Wrong working directory | `cd` to the repo first. |
| ComfyUI "5 issues found" / "Missing Models" | Files not where the workflow expects | Check `out=` in `models.txt` (hash names), then `colab ls -s <name> /content/ComfyUI/models/<type>`. |
| ComfyUI editor blank on a phone | Heavy desktop app | Use a laptop, or direct `/view?...` links. |
| Balance unchanged after spending | Display lags a few minutes | Use `Usage rate` and wall clock; re-read the balance later. |
| `[colab] Download failed: [Errno 21] Is a directory` | Gave a directory as the local path | Pass a full file path; tar a folder on the VM first. |
| `[colab] Download failed: [Errno 2] No such file or directory: 'outputs/...'` | The local folder does not exist (`outputs/` is git-ignored) | `mkdir -p outputs` first. |
| `[colab] Download failed: File or directory not found` | Wrong path, or `/content` was erased by a stop | Download before stopping; `colab ls` to find the file. |
| `Session READY.` then 404s | The backend pruned the VM | `colab sessions`, then `colab new`. |
| `Warning: Could not read the OAuth token from the OS keyring` | Keyring not set up, or no token | `scripts/bootstrap.sh` (restores from the secret), else `scripts/login.sh`. |
| Sign-in code expires, or `invalid_grant` | Number-match 2FA took too long | Use the user's own browser and paste promptly; not the orb browser. |
| Watchdog log stops while the GPU is still up | The orb was paused or killed | `colab stop -s <name>` by hand. |
| `2 sessions already exist (...); not grabbing another` | The guard in `grab-gpu.sh` refused to double up | `colab sessions`; stop the extra one, or let the holder adopt the named one. |
| `a GPU session is already running but was started on another machine` | A `[?]` session started elsewhere; it has no local name | Stop it where it was started; the holder will not grab a second GPU. |
| `no hold requested (...); exiting` | The holder service started with no hold | Expected after a boot with no hold. Request one: `scripts/gpu-request.sh`. |
| `port 8188 is down; re-opening the forward` | The SSH forward died, the GPU did not | The keeper re-opens it; a dead VM ends the loop. |
| Alert `gpu-lost` | Colab reclaimed the runtime | The monitor restarts the holder, which grabs again. |
| Alert `holder-down` | The GPU is up but nothing will release it | The monitor restarts the holder, which adopts the session. |
| `drive_save: Drive refused the request: no quota project` | The Drive API needs a quota project for this login | Set `DRIVE_QUOTA_PROJECT` (step 7). |
| `drive_save: quota project '<id>' is not usable` | The project does not exist, or the Drive API is not enabled for it | Create and enable it, or fix the id. |
| `drive-save: skipped, no DRIVE_QUOTA_PROJECT set` | Drive saving is not configured | Expected; outputs still go to `outputs/` with `colab download`. |
| A100 slow or out of memory at high resolution | It is 40 GB, not 80 | Lower megapixels or duration, or use G4. |

## 11. Free checks

These never start a GPU: `colab whoami`, `colab sessions`, `colab usage`. On a running session they
also cost nothing extra: `colab status -s <name>`, `colab ls -s <name> <path>`, `colab log -s <name> -n
20`, and `curl http://127.0.0.1:8188/system_stats` through the forward.

`scripts/probe-gpus.sh` is the one probe that may start a GPU: a granted runtime is stopped at once but
still costs a few minutes of units. Run it after a plan change, not as a routine check.
