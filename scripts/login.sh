#!/usr/bin/env bash
# One-time Google sign-in for the Colab CLI.
#
# 1. Runs `colab sessions`, which prints a Google sign-in link and waits for a code.
#    Open the link in a browser signed in to the Google account that holds the
#    Colab / Google AI plan, click Allow, and paste the code back here.
# 2. With --export, prints the stored token as one base64 line. Paste that line into
#    the secret COLAB_OAUTH_TOKEN_B64 (Amp: project secret; elsewhere: your secret store
#    or environment). Never paste it into a chat.
#
# Revoke later: myaccount.google.com > Security > Third-party connections > Google Cloud SDK.
set -euo pipefail
TOOL_PY="$(uv tool dir)/google-colab-cli/bin/python"

if [ "${1:-}" = "--export" ]; then
	# Export only what is needed to refresh the login, so the line stays short.
	"$TOOL_PY" -c '
import base64, json, keyring
t = keyring.get_password("google-colab-cli", "oauth_token")
if not t:
    raise SystemExit("No Colab login stored yet; run scripts/login.sh first.")
info = json.loads(t)
keep = {k: info[k] for k in ("refresh_token", "client_id", "client_secret", "token_uri", "scopes") if k in info}
print(base64.b64encode(json.dumps(keep, separators=(",", ":")).encode()).decode())
'
	exit 0
fi

colab sessions
echo
echo "Signed in. Next: scripts/login.sh --export, and store the line as COLAB_OAUTH_TOKEN_B64."
