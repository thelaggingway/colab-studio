#!/usr/bin/env bash
# Installs everything an agent or a person needs to drive Colab from this machine.
# Works on Linux and macOS, from Amp (.agents/setup), Claude Code, Codex, or a terminal.
# Safe to run repeatedly.
#
# Login: if COLAB_OAUTH_TOKEN_B64 is set (base64 of the Colab CLI's OAuth token JSON,
# made by scripts/login.sh), it is restored into the keyring, so `colab` works
# without signing in again.
set -euo pipefail

say() { printf '[bootstrap] %s\n' "$*" >&2; }

# 1. uv, which installs the Colab CLI.
if ! command -v uv >/dev/null 2>&1; then
	say "installing uv"
	curl -LsSf https://astral.sh/uv/install.sh | sh
	export PATH="$HOME/.local/bin:$PATH"
fi

# 2. The Colab CLI. keyrings.alt gives machines without an OS keyring (Linux
# containers, orbs, CI) a file-based keyring for the login token.
say "installing google-colab-cli"
uv tool install --quiet --upgrade google-colab-cli --with keyrings.alt
TOOL_PY="$(uv tool dir)/google-colab-cli/bin/python"

# 3. On Linux without a desktop keyring, use the file keyring. macOS keeps its Keychain.
if [ "$(uname -s)" = "Linux" ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
	mkdir -p "$HOME/.config/python_keyring"
	printf '[backend]\ndefault-keyring=keyrings.alt.file.PlaintextKeyring\n' \
		>"$HOME/.config/python_keyring/keyringrc.cfg"
	chmod 600 "$HOME/.config/python_keyring/keyringrc.cfg"
fi

# 4. Restore the login token, if provided.
if [ -n "${COLAB_OAUTH_TOKEN_B64:-}" ]; then
	# Decode in Python: GNU and BSD base64 disagree on the decode flag.
	"$TOOL_PY" -c '
import base64, os, keyring
token = base64.b64decode(os.environ["COLAB_OAUTH_TOKEN_B64"]).decode()
keyring.set_password("google-colab-cli", "oauth_token", token)
'
	data_dir="$("$TOOL_PY" -c 'import keyring.util.platform_ as p; print(p.data_root())')"
	[ -d "$data_dir" ] && chmod -R go-rwx "$data_dir"
	say "restored Colab login from COLAB_OAUTH_TOKEN_B64"
else
	say "COLAB_OAUTH_TOKEN_B64 not set; run scripts/login.sh once to sign in"
fi

# 5. SSH key for `colab ssh` (port forwarding, shell commands). The public key is
# sent per connection, so a fresh key per machine is fine.
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
	mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
	ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519" -C colab-studio
fi

# 6. Download helper for the local side (model lists are pulled on the Colab VM itself).
if ! command -v aria2c >/dev/null 2>&1; then
	if command -v apt-get >/dev/null 2>&1; then
		(sudo -n apt-get install -y -qq aria2 >/dev/null 2>&1 || true)
	elif command -v brew >/dev/null 2>&1; then
		brew install -q aria2 || true
	fi
fi

say "done: $(colab version 2>/dev/null | head -1 || echo 'colab not on PATH; add ~/.local/bin')"
