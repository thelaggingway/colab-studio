# Colab Studio

This repo turns a Google account's Colab compute units into on-demand GPUs for creative and ML work: video, images, music, speech, 3D, and model training. Any agent (Amp, Claude Code, Codex) or a person at a terminal drives it through the official Colab CLI (`colab`).

## Setup

- Amp orbs run `.agents/setup`, which runs `scripts/bootstrap.sh`.
- Anywhere else, run `scripts/bootstrap.sh` yourself. `docs/other-systems.md` covers Claude Code, Codex, a laptop, and other machines.
- The Google login comes from the secret `COLAB_OAUTH_TOKEN_B64`. If it is missing, `colab` will ask for a sign-in; follow `scripts/login.sh`.
- Check the login with `colab sessions` (read-only). Check the balance with `colab usage`.

## Rules for every session

1. **Check the balance first** with `colab usage`. Do not start a GPU if the balance is below `MIN_BALANCE` in `config/account.env`.
2. **Use the GPU from `config/account.env`** unless the task needs another one. Only the GPUs listed there as granted are known to work for this account; re-run `scripts/probe-gpus.sh` after any plan change.
3. **Always name sessions** (`-s <name>`) and **always stop them** with `colab stop -s <name>` when the work ends, including after errors. Units are spent every minute a runtime exists. Before ending a turn, run `colab sessions` and confirm nothing you started is still running.
4. **Download model files on the Colab VM** (`aria2c` from Hugging Face into `/content`). Do not move model weights through this machine or Google Drive.
5. **Copy results back** (`colab download`) into `outputs/` (git-ignored) before stopping; `/content` is erased when the runtime stops.
6. **Report units used**: balance before and after, in the final message.

## Colab policy (from the Colab FAQ)

- Allowed with a positive unit balance: web UIs, `colab ssh`, port forwarding.
- Never: deepfakes (no face swaps or voice clones of real people without their consent), public file hosting or media serving, crypto mining, torrents, proxies, using several accounts to get around limits.
- Portal links to a running app are for the account owner, not for publishing.

## Secrets

- `COLAB_OAUTH_TOKEN_B64` holds a Google login with Colab, `cloud-platform`, and `drive.file` access. Never print it, log it, commit it, or paste it into a chat.
- The decoded token lives only in the local keyring (`~/.local/share/python_keyring/` on Linux).

## Layout

- `scripts/bootstrap.sh`: install and restore the login.
- `scripts/login.sh`: one-time sign-in and export of the login secret.
- `scripts/probe-gpus.sh`: which GPUs this account can start; writes `probe-results/`.
- `config/account.env`: account defaults that come from the probe.
- `.agents/skills/colab-operator/`: Google's skill for the Colab CLI (vendored; `colab skill` prints the latest).
- `.agents/skills/colab-studio/`: how this repo runs a session, and the recipe index.
- `.claude/skills` links to `.agents/skills` so Claude Code finds the same skills.
