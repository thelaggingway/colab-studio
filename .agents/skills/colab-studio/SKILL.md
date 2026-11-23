---
name: colab-studio
description: Runs a GPU session in this repo's Colab Studio for video, image, music, speech, 3D, or training work - balance check, start a runtime, pull models, open an app through a forwarded port, collect outputs, stop. Use for any task in this repo that needs a Colab GPU; load colab-operator for CLI details.
---

# Colab Studio session

Read `AGENTS.md` first: its rules on balance, stopping, and Colab policy apply to every step here.

## Session steps

1. `source config/account.env`, then `colab usage`. Stop if the balance is below `MIN_BALANCE`. If `GPU` is empty, run `scripts/probe-gpus.sh` and fill in `config/account.env` first.
2. Start: `colab new -s <task> --gpu "$GPU"`. An HTTP 503 "Service Unavailable" from `/tun/m/assign` means the GPU type is busy, not that the account lacks it; the CLI retries (`COLAB_CLI_ASSIGN_RETRIES`, `COLAB_CLI_RETRY_BACKOFF`, delay doubles each time). If it still fails, fall back to the next GPU in `GRANTED_GPUS` or try later. "Backend rejected accelerator" means not entitled.
3. Install and download on the VM, for example:
   ```bash
   colab ssh -s <task> -- 'apt-get -y -qq install aria2 >/dev/null; aria2c -x16 -s16 -d /content/models -o model.safetensors https://huggingface.co/<repo>/resolve/main/<file>' </dev/null > /tmp/<task>-setup.log 2>&1
   ```
4. Start the app in the background on the VM so the shell returns, with its log in `/content/<app>.log`.
5. For a web app, forward its port to this machine:
   ```bash
   ssh -f -N -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -o ProxyCommand="$(command -v colab) ssh --proxy-mode -s <task>" \
     -L <port>:localhost:<port> root@colab
   ```
   In an Amp orb, then run `amp orb portal <port> --title '<app>'` and give the user the link.
6. Collect results with `colab download -s <task> /content/output/<file> outputs/`.
7. Stop: `colab stop -s <task>`, then `colab sessions` to confirm, then `colab usage` and report units used.

The port forward in step 5 and the `root@colab` user are still to be confirmed on a live runtime; record what works here.

## Recipes

Each recipe will live in `recipes/<name>/` with `remote.sh` (runs on the VM), `models.txt` (download list), and any workflow files. None are written yet; they are added after the first probe and port-forward test.

| Area | First model | Licence | Notes |
| --- | --- | --- | --- |
| Video with sound | MiniMax H3 via ComfyUI | MiniMax community; excludes US, EU, UK, South Korea | About 24 GB peak in ComfyUI |
| Video | Wan 2.2, LTX-2.5 | Apache 2.0 / LTX community | LTX needs 32 GB or more |
| Images | Z-Image Turbo, Qwen-Image-2512 | Apache 2.0 | |
| Songs | ACE-Step 1.5 | MIT | Under 4 GB |
| Speech to text | Qwen3-ASR 1.7B, Whisper large-v3-turbo | Apache / MIT | Batch jobs, no web UI needed |
| Text to speech | Chatterbox, Qwen3-TTS | MIT / Apache | Clone only consenting voices |
| Image to 3D | TRELLIS.2-4B | MIT | |
| Fine-tuning | Unsloth Studio | Apache | |
