# Colab Studio

This repo turns a Google account's Colab compute units into on-demand GPUs for creative and ML work:
video, images, music, speech, 3D, and model training. Any agent (Amp, Claude Code, Codex) or a person
at a terminal drives it through the official Colab CLI (`colab`).

**Start with [docs/runbook.md](docs/runbook.md)** for the full procedure: login, balance, requisition,
recipe setup, ComfyUI, generate, collect, release, and the failure signatures with their fixes.

## Setup

- Setting up for a new person or device: follow the README's "Set up" steps. `config/account.env` holds the
  repo owner's GPU results and Drive project; another account must re-probe and set its own values.
  Sign-in needs the human: run `scripts/login.sh` and ask them to open the link in their own browser.
- Amp orbs run `.agents/setup`, which runs `scripts/bootstrap.sh`. Anywhere else, run
  `scripts/bootstrap.sh` yourself; `docs/other-systems.md` covers Claude Code, Codex, a laptop, and
  other machines.
- The Google login comes from the secret `COLAB_OAUTH_TOKEN_B64`; the bootstrap restores it and ends
  with a read-only `colab sessions` check. If it is missing, follow `scripts/login.sh` in the user's own
  browser (see runbook step 1).
- Check the login with `colab whoami` (email and scopes, never the token) or `colab sessions`. Check the
  balance with `colab usage`.

## Rules for every session

1. **Check the balance first** with `colab usage`. Do not start a GPU if the balance is below
   `MIN_BALANCE` in `config/account.env`; `scripts/studio-up.sh` refuses by itself. The balance lags a
   few minutes behind spend, so `Usage rate` is the live number while a GPU runs.
2. **Use the GPU from `config/account.env`** unless the task needs another one: `GPU` (A100) for video
   and anything near 24 GB of weights, `GPU_SMALL` (L4) for models that fit in about 22 GB. Only the
   GPUs in `GRANTED_GPUS` are known to work; re-run `scripts/probe-gpus.sh` after any plan change.
3. **Always name sessions** (`-s <name>`). Units are spent every minute a runtime exists. A held GPU
   must have the idle watchdog running (see below); otherwise stop it with `colab stop -s <name>` when
   the work ends, including after errors. Before ending a turn, run `colab sessions` and say which
   sessions are still running and why. Sessions started by another thread show up as `[?] gpu-...`
   with no name and cannot be stopped from here: leave them alone.
4. **Download model files on the Colab VM** (`aria2c` from Hugging Face into `/content`), with
   `out=<filename>` per URL so files do not land under hash names. Do not move model weights through
   this machine or Google Drive. For gated models, use `HF_TOKEN`; `scripts/studio-up.sh` forwards it to
   `/content/.hf_token`, and a recipe reads that file (never log the token).
5. **Copy results back** before stopping: `colab download -s <name> <remote file> outputs/<file>` takes
   one file and a full local path, so `mkdir -p outputs` first (`outputs/` is git-ignored), and
   `/content` is erased when the runtime stops. Give the user
   direct `/view?filename=...&type=output` links and copies in `.amp/in/artifacts/`; ComfyUI's editor
   can render blank on a phone.
6. **Report units used**: balance before and after, plus the usage rate and time held, in the final
   message.

## Getting a GPU (requisition)

GPUs are often busy: `colab new` then fails with HTTP 503 for 10 to 30 minutes, which costs nothing.
Never wait for one in a working conversation.

1. **Start the grab in the background.** In an Amp orb:
   `amp orb service start studio-<name> --command 'bash scripts/studio-up.sh <name> <recipe> <grab_min> <idle_min> <gpu...>'`.
   It retries the GPUs in order, sets up the recipe, forwards port 8188, then runs
   `scripts/idle-stop.sh`, which stops the GPU after `<idle_min>` idle minutes (default plan: 60).
   Watch it with `amp orb service logs -n 20 studio-<name>` from the repo root; look for `GOT=A100`.
2. **Hand the waiting to someone else.** An orchestrating agent delegates the grab-and-run to a child
   thread or subagent. The child sends the parent one message when the GPU is assigned and one when the
   job is done or failed, with time and units. Elsewhere (Claude Code, Codex, a terminal), run
   `studio-up.sh` with `nohup` or in tmux and check its log.
3. **Hold, don't re-grab.** Once assigned, keep the session between jobs; the idle watchdog releases
   it. The watchdog only runs while its machine is up.
4. **Fall back when it matters.** Order GPUs by need, for example `A100 G4 L4` for MiniMax H3,
   `L4 T4` for small models. Record busy periods in the recipe README.
5. **One SSH connection per runtime.** Colab answers HTTP 429 to a second `colab ssh`. Use
   `scripts/colab-ssh.sh <name> ...` for every SSH command; it shares one connection with the port
   forward.

Failure codes: 503 = busy, retry or fall back. 412 (`Allocation refused (precondition failed)`) = too
many sessions or a temporary limit. 400 `Backend rejected accelerator` = not entitled. Do not raise
`COLAB_CLI_ASSIGN_RETRIES`: the CLI doubles its delay per retry, so large values wait for hours.

## Colab policy (from the Colab FAQ)

- Allowed with a positive unit balance: web UIs, `colab ssh`, port forwarding.
- Never: deepfakes (no face swaps or voice clones of real people without their consent), public file
  hosting or media serving, crypto mining, torrents, proxies, using several accounts to get around
  limits.
- Portal links to a running app are for the account owner, not for publishing.

## Secrets

- `COLAB_OAUTH_TOKEN_B64` holds a Google login with Colab, `cloud-platform`, and `drive.file` access.
  Never print it, log it, commit it, or paste it into a chat.
- The decoded token lives only in the local keyring (`~/.local/share/python_keyring/` on Linux). If a
  token ever reaches a terminal or log, clear the scrollback (`tmux clear-history`) and rotate it.
- `HF_TOKEN` is a Hugging Face token for gated models; it is already set in this project's orbs. Pass
  it to `aria2c` as `--header="Authorization: Bearer $HF_TOKEN"`; never log or commit it.
- `DRIVE_QUOTA_PROJECT` is a Google Cloud project id, not a secret. The Drive API refuses this login
  without one; `scripts/drive-save.sh` skips saving until it is set.

## Layout

- `docs/next-steps.md`: current state, measured numbers, remaining work and working agreements. Read first when continuing.
- `docs/runbook.md`: the end-to-end procedure, expected output per step, per-GPU notes, failure fixes.
- `docs/other-systems.md`: Claude Code, Codex, a laptop, another VM.
- `docs/amp-runner-on-colab.md`: an Amp runner on the Colab VM itself (Amp only), trade-offs and cleanup.
- `docs/workflows.md`: which models and workflows fit which GPU, area by area.
- `scripts/bootstrap.sh`: install and restore the login, then verify it.
- `scripts/login.sh`: one-time sign-in and export of the login secret.
- `scripts/probe-gpus.sh`: which GPUs this account can start; writes `probe-results/`.
- `config/account.env`: account defaults, GPU choices, rates, and `MIN_BALANCE`.
- `scripts/grab-gpu.sh`, `scripts/studio-up.sh`, `scripts/idle-stop.sh`, `scripts/colab-ssh.sh`: get a
  GPU, set it up, hold it, release it, and share one SSH connection.
- `scripts/drive-save.sh`, `scripts/drive_save.py`: copy a session's outputs to Google Drive.
- `recipes/draft-handoff/`: draft with LTX-2.5, re-render shots that miss the action with H3 from the draft's frame (`handoff.py`).
- `recipes/<name>/`: per-model setup (`models.txt`, `remote.sh`), workflow files, and measured times
  and units.
- `.agents/skills/colab-operator/`: Google's skill for the Colab CLI (vendored; `colab skill` prints
  the latest).
- `.agents/skills/colab-studio/`: how this repo runs a session, and the recipe index.
- `.claude/skills` links to `.agents/skills` so Claude Code finds the same skills.
