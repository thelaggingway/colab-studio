# Colab Studio

On-demand Colab GPUs for video, image, music, speech, 3D, and model training, driven by an agent or by hand through the official [Colab CLI](https://github.com/googlecolab/google-colab-cli).

1. `bash scripts/bootstrap.sh`
2. First time only: `scripts/login.sh`, then store `scripts/login.sh --export` as `COLAB_OAUTH_TOKEN_B64`
3. `scripts/probe-gpus.sh`, then fill in `config/account.env`

Rules for agents are in [AGENTS.md](AGENTS.md). Other machines and agents: [docs/other-systems.md](docs/other-systems.md).

`.agents/skills/colab-operator/SKILL.md` is copied from googlecolab/google-colab-cli (Apache-2.0, commit 0abf82d, 2026-11-18).
