#!/usr/bin/env bash
# One-time Google sign-in for the Colab CLI.
#
# Do this in the user's own browser, not in the orb browser. Google's number-match
# 2FA expires before a remote browser renders the prompt, so the copy-paste flow
# below is the one that works.
#
# 1. `scripts/login.sh` runs `colab sessions`. With no login stored, the CLI prints
#      To authorize colab-cli, visit this URL in any browser:
#        https://accounts.google.com/o/oauth2/auth?...
#      After approving, Google will display an authorization code.
#      Enter the authorization code:
#    Open that URL in a browser signed in to the Google account that holds the
#    Colab / Google AI plan, click Allow, then paste the code at the prompt.
#    Paste it into the terminal (the Amp Terminal tab in an orb), never into a chat.
# 2. With --export, prints the stored token as one base64 line. Store that line as the
#    secret COLAB_OAUTH_TOKEN_B64 (Amp: project secret; elsewhere: your secret store
#    or environment), so scripts/bootstrap.sh can restore the login on any machine.
#    Never print, log, or commit it.
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
echo "Signed in. Check it with: colab whoami   (shows the email and scopes; never the token)"
echo "Next: scripts/login.sh --export, and store the line as COLAB_OAUTH_TOKEN_B64."
