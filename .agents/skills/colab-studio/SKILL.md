---
name: colab-studio
description: Runs a GPU session in this repo's Colab Studio for video, image, music, speech, 3D, or training work - balance check, start a runtime, pull models, open an app through a forwarded port, collect outputs, stop. Use for any task in this repo that needs a Colab GPU; load colab-operator for CLI details.
---

# Colab Studio session

The procedure, with expected output for every step and a table of failure signatures, is
[`docs/runbook.md`](../../../docs/runbook.md). Follow it in order. `AGENTS.md` has the rules that apply
to every session. This file is the short version and the recipe index.

## Quick path

```bash
bash scripts/bootstrap.sh                                  # once per machine; restores and checks the login
source config/account.env && colab usage                   # read-only; stop if below MIN_BALANCE
amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
amp orb service logs -n 20 studio-h3                       # GOT=A100, then "comfyui reachable"
amp orb portal 8188 --title 'ComfyUI'                      # give the printed URL to the user
colab stop -s h3; amp orb service stop studio-h3          # or let idle-stop release it
colab sessions && colab usage                              # confirm, then report units
```

## What wastes time, in one list

- **503 on assign is a busy GPU, not a refusal.** Wait or fall back; it costs nothing. 10-30 minute
  spells are normal. 412 means too many sessions or a temporary limit. "Backend rejected accelerator"
  means not entitled.
- **Never raise `COLAB_CLI_ASSIGN_RETRIES`.** The CLI waits `backoff * 2^n`; 10 retries is hours.
  `scripts/grab-gpu.sh` loops with one retry per attempt instead.
- **One SSH connection per runtime** (HTTP 429 for a second). Always use `scripts/colab-ssh.sh`; it
  shares one connection with the port forward.
- **`out=<filename>` per URL** in `models.txt`, or Hugging Face redirects save hash names and ComfyUI
  reports "Missing Models". Gated models need `HF_TOKEN`; `studio-up.sh` forwards it.
- **`colab download` takes one file and a full local path.** A folder fails; tar it on the VM first.
  `mkdir -p outputs` first, or the CLI cannot create the file. `/content` is erased when the runtime
  stops, so download before stopping. `scripts/drive-save.sh <name>` saves the outputs to Drive, and
  the idle watchdog runs it before stopping the GPU (it needs `DRIVE_QUOTA_PROJECT`).
- **ComfyUI's editor can be blank on a phone.** Use a laptop or direct `/view?filename=...` links.
- **The balance lags a few minutes.** `Usage rate` is live; that is how the A100's 6.73/hr was measured.
- **Never wait for a GPU in a working conversation.** Run the grab as a service, or delegate it to a
  child thread that messages the parent on assignment and on completion.

## Per-GPU, in one line each

| GPU | Rate | Use |
| --- | --- | --- |
| A100 | 6.73/hr measured, 40 GB SXM4, 83 GB RAM | Video and anything near 24 GB of weights. H3 864×480/5.2 s = 118 s; 1280×736/10.1 s = 344 s |
| G4 | ~10/hr (unmeasured) | Entitled but 503 on every attempt so far; best for bigger H3 jobs |
| L4 | ~1.9/hr | Models up to about 22 GB: images, speech, music, 3D |
| T4 | ~1.5/hr | Cheapest; small models and smoke tests |
| TPU v6e1/v5e1 | - | Training/batch; ComfyUI needs CUDA |
| H100 | - | Not entitled |

## Recipes

Each recipe lives in `recipes/<name>/` with `remote.sh` (runs on the VM), `models.txt` (aria2 download
list with `out=` names), and any workflow files. `recipes/minimax-h3/` is the first, with measured times
and units, and L4/T4 measurements, in its README.

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

Which model fits which GPU, area by area: [`docs/workflows.md`](../../../docs/workflows.md).
