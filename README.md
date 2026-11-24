# Colab Studio

On-demand Colab GPUs for video, image, music, speech, 3D, and model training, driven by an agent or by
hand through the official [Colab CLI](https://github.com/googlecolab/google-colab-cli). Any agent works:
point Amp, Claude Code, Codex or another coding agent at this repository and ask it to follow this README.

## What you need

- A Google account with Colab compute units: a Colab Pro / Pro+ subscription, a Google AI Pro or Ultra
  plan (Pro gives 200 units a month), or pay-as-you-go units. Check with `colab usage` after login.
- A Linux or macOS machine with `bash`, `curl` and `git`. The bootstrap installs `uv` and the Colab CLI.
- Your own browser for a one-time Google sign-in (a remote or headless browser fails Google's 2FA).
- Optional: a Hugging Face token (`HF_TOKEN`) for gated models such as LTX-2.5, with each gated model's
  licence accepted once on huggingface.co. A fine-grained token needs "read access to public gated repos".
- Optional: a free Google Cloud project with the Drive API enabled, to save outputs to Google Drive.
- `ffmpeg` on the agent machine if you use `recipes/draft-handoff/`.

## Set up (any device, any person)

1. `git clone https://github.com/thelaggingway/colab-studio && cd colab-studio`
2. `bash scripts/bootstrap.sh` installs everything. If `COLAB_OAUTH_TOKEN_B64` is set it restores that
   login; otherwise continue with step 3.
3. `bash scripts/login.sh`: open the printed Google link in your own browser, approve, and paste the code
   back into the terminal. To reuse the login on other machines or agents, run `scripts/login.sh --export`
   and store the line it prints as the secret `COLAB_OAUTH_TOKEN_B64` (never in a chat or a commit).
4. `colab whoami` and `colab usage`: your email, the three scopes, and your unit balance.
5. **Make `config/account.env` yours.** It holds the repo owner's values. Run `bash scripts/probe-gpus.sh`
   (it starts and immediately stops each GPU, under 0.01 units) and set `GRANTED_GPUS`, `GPU`, `GPU_SMALL`
   and `PLAN` from its result. Set `DRIVE_QUOTA_PROJECT` to your own Cloud project id, or `DRIVE_SAVE=0` to skip
   Drive saves: the owner's project will refuse your login. You can also override any non-empty value in
   the environment instead of editing the file, for example `DRIVE_SAVE=0 GPU=L4 bash scripts/...`.
6. Follow [docs/runbook.md](docs/runbook.md) for a session: balance, GPU requisition, recipe setup,
   ComfyUI, generate, collect outputs, release the GPU. Each step lists its expected output and fixes.

In an Amp project on this repo, steps 1-2 happen automatically (`.agents/setup`); store
`COLAB_OAUTH_TOKEN_B64` and `HF_TOKEN` as project secrets. Claude Code, Codex, laptops and other VMs:
[docs/other-systems.md](docs/other-systems.md).

## Where things are

| Read | For |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Rules every agent follows: balance floor, always release GPUs, Colab policy, secrets |
| [docs/runbook.md](docs/runbook.md) | The step-by-step session procedure and failure table |
| [docs/next-steps.md](docs/next-steps.md) | Current state, measured numbers, remaining work. Start here when continuing earlier work |
| [docs/workflows.md](docs/workflows.md) | Which models fit A100, L4 and T4, area by area |
| [docs/amp-runner-on-colab.md](docs/amp-runner-on-colab.md) | Amp only: running an Amp runner on the Colab VM itself, measured setup, trade-offs, cleanup |
| [docs/prior-art.md](docs/prior-art.md) | Existing Colab notebooks, launchers and ComfyUI workflows worth reusing |
| `recipes/` | Ready recipes with measured time and units: `minimax-h3`, `ltx-2.5`, `draft-handoff` |
| `.agents/skills/` | Agent skills (`colab-studio`, Google's `colab-operator`); `.claude/skills` links here |

`.agents/skills/colab-operator/SKILL.md` is copied from googlecolab/google-colab-cli (Apache-2.0, commit 0abf82d, 2026-11-18).
