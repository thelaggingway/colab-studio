# Running Colab Studio outside Amp

The repo does not depend on Amp. Every system needs the same three things: run `scripts/bootstrap.sh`, provide the secret `COLAB_OAUTH_TOKEN_B64`, and point the agent at `AGENTS.md` and `.agents/skills/`.

| System | Setup | Where the secret goes | Skills and rules |
| --- | --- | --- | --- |
| Amp orb | Automatic (`.agents/setup`) | Project secret on the colab-studio project | `AGENTS.md`, `.agents/skills/` |
| Claude Code | `bash scripts/bootstrap.sh` once per machine | Shell environment or a `.env` you do not commit | `CLAUDE.md` points to `AGENTS.md`; `.claude/skills` links to `.agents/skills` |
| Codex CLI | `bash scripts/bootstrap.sh` | Shell environment | Reads `AGENTS.md` |
| Laptop terminal | `bash scripts/bootstrap.sh` | Not needed on macOS: run `scripts/login.sh` once and the Keychain keeps the login | Use the commands in the skills by hand |
| Another VM (InstaBox, a server) | `bash scripts/bootstrap.sh` in its setup step | That machine's secret store | Same as above |

## Signing in on a new machine

Either set `COLAB_OAUTH_TOKEN_B64` before running the bootstrap, or run `scripts/login.sh` on that machine and approve the link in any browser signed in to the account.

## Changing Google account or plan

1. Run `scripts/login.sh` while signed in to the new account, then `scripts/login.sh --export` and replace the secret everywhere it is stored.
2. Run `scripts/probe-gpus.sh` and update `config/account.env` from its results.
3. Revoke the old login: myaccount.google.com > Security > Third-party connections > Google Cloud SDK.
