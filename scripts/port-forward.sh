#!/usr/bin/env bash
# Keep an SSH port forward into a Colab session's ComfyUI alive for as long as the session exists.
# Usage: scripts/port-forward.sh <session> [local_port=8188] [remote_port=8188]
#
# `colab-ssh.sh <session> -f -N -L 8188:localhost:8188` opens one background connection through the
# CLI's proxy. It dies with the VM, with a network blip, or when Colab reclaims the runtime, and
# nothing restarts it: the local port just stops answering while the GPU keeps billing. This keeper
# re-opens it. Colab allows one SSH connection per runtime, so the re-open goes through the same
# ControlMaster socket that scripts/colab-ssh.sh uses.
#
# It exits 0 when the session is gone, so a supervisor can treat "no session" as "nothing to keep".
set -uo pipefail
session="${1:-}"
if [ -z "$session" ]; then
  echo "usage: scripts/port-forward.sh <session> [local_port=8188] [remote_port=8188]" >&2
  exit 2
fi
lport="${2:-8188}"
rport="${3:-8188}"
here="$(cd "$(dirname "$0")/.." && pwd)"
ts() { date -u +%T; }

# Is anything listening on the local port? TCP only: ComfyUI itself may still be starting, which is
# not the forward's problem.
listening() { (exec 3<>"/dev/tcp/127.0.0.1/$lport") 2>/dev/null; }

while :; do
  if listening; then
    sleep 15
    continue
  fi
  if ! colab sessions </dev/null 2>/dev/null | grep -qF "[$session]"; then
    echo "$(ts) session $session is gone; port forward keeper exiting"
    exit 0
  fi
  echo "$(ts) port $lport is down; re-opening the forward to $session"
  # -f backgrounds the connection once it is up, so this returns in a second or two. A dead proxy
  # makes it fail; the loop retries rather than giving up.
  timeout 60 bash "$here/scripts/colab-ssh.sh" "$session" -f -N -L "$lport:localhost:$rport" \
    </dev/null || echo "$(ts) forward failed; retrying in 10s"
  sleep 10
done
