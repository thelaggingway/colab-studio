# Running Colab Studio outside Amp

The repo does not depend on Amp. Every system needs the same three things: run `scripts/bootstrap.sh`,
provide the secret `COLAB_OAUTH_TOKEN_B64`, and point the agent at `AGENTS.md`, `docs/runbook.md`, and
`.agents/skills/`.

| System | Setup | Where the secret goes | Skills and rules |
| --- | --- | --- | --- |
| Amp orb | Automatic (`.agents/setup`) | Project secret on the colab-studio project | `AGENTS.md`, `.agents/skills/` |
| Claude Code | `bash scripts/bootstrap.sh` once per machine | Shell environment or a `.env` you do not commit | `CLAUDE.md` points to `AGENTS.md`; `.claude/skills` links to `.agents/skills` |
| Codex CLI | `bash scripts/bootstrap.sh` | Shell environment | Reads `AGENTS.md` |
| Laptop terminal | `bash scripts/bootstrap.sh` | Not needed on macOS: run `scripts/login.sh` once and the Keychain keeps the login | Use the commands in `docs/runbook.md` by hand |
| Another VM (InstaBox, a server) | `bash scripts/bootstrap.sh` in its setup step | That machine's secret store | Same as above |

The bootstrap ends with a read-only `colab sessions`, so a successful run proves the login works.

## Signing in on a new machine

Either set `COLAB_OAUTH_TOKEN_B64` before running the bootstrap, or run `scripts/login.sh` on that
machine:

1. It prints `To authorize colab-cli, visit this URL in any browser:` and a Google link.
2. Open the link in your own browser, signed in to the account that holds the Colab plan, and approve.
3. Paste the code Google shows into the terminal prompt.

Do not sign in through a remote browser (the orb Desktop, a VNC session): Google's number-match 2FA
expires before the remote screen updates. If you signed in that way and it failed, the copy-paste flow
above is the fix.

Check the result with `colab whoami`: it prints the email and the scopes (it must include
`/auth/colaboratory`, `/auth/cloud-platform`, `/auth/drive.file`) and never the token.

## Hugging Face token (gated models)

Gated models such as FLUX.2 dev need a Hugging Face token. Export it on the machine that runs the
session:

```bash
export HF_TOKEN=hf_...        # or put it in your shell profile or secret store
```

`scripts/studio-up.sh` forwards it to the VM as `/content/.hf_token`, and a recipe's `remote.sh` adds
`--header="Authorization: Bearer $(cat /content/.hf_token)"` to aria2. If you download by hand, pass
the same header and never log the token. Public models work without it.

## Saving outputs to Google Drive

`scripts/drive-save.sh <session>` copies `/content/ComfyUI/output` to
`<DRIVE_FOLDER>/outputs/<date>/<session>/` using the restored login, with no browser and no
per-session consent. It runs on the machine that holds the login: an orb, a laptop, another VM.

It does not use `colab drivemount`, which asks for browser approval on every runtime. Instead it
calls the Drive API directly, which needs a Google Cloud project to bill quota to. Create a free
project, enable the Drive API, and set `DRIVE_QUOTA_PROJECT` in `config/account.env`; until then the
script skips and says so.

## Running a session without Amp

The steps in `docs/runbook.md` work as written, with three differences:

- **No portal.** The port forward is enough: after
  `bash scripts/colab-ssh.sh <name> -f -N -L 8188:localhost:8188`, open `http://127.0.0.1:8188` in a
  browser on that machine.
- **No supervised service.** Run the grab in the background and read its log:
  ```bash
  nohup bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4 > /tmp/studio-h3.log 2>&1 &
  tail -f /tmp/studio-h3.log        # "GOT=A100", then "comfyui reachable"
  ```
  `nohup` and tmux are the right tool here; inside an Amp orb they are not (the orb's supervised
  services are).
- **No watchdog if the machine sleeps.** `scripts/idle-stop.sh` runs on that machine, so a laptop that
  suspends cannot stop the GPU. Stop it yourself with `colab stop -s <name>` when the work ends.

## Changing Google account or plan

1. Run `scripts/login.sh` while signed in to the new account, then `scripts/login.sh --export` and
   replace `COLAB_OAUTH_TOKEN_B64` everywhere it is stored.
2. Run `scripts/probe-gpus.sh` and update `config/account.env` from its results (granted GPUs, default
   `GPU` and `GPU_SMALL`, rates).
3. Revoke the old login: myaccount.google.com > Security > Third-party connections > Google Cloud SDK.
