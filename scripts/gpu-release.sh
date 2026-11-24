#!/usr/bin/env bash
# End a hold: stop the holder, save the session's outputs, and stop the GPU.
# Usage: scripts/gpu-release.sh [session]
# Without an argument it uses the session the holder recorded. Safe to run when nothing is held.
#
# This is the deliberate way to end a hold. `systemctl --user stop colab-gpu-holder` only pauses it:
# the hold stays requested, so the holder adopts the same session again on the next start or boot.
set -uo pipefail
cd "$(dirname "$0")/.."
source config/account.env
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
ts() { date -u +%T; }

session="${1:-}"
[ -z "$session" ] && [ -f "$state/session" ] && session="$(cat "$state/session")"

rm -f "$state/desired"
systemctl --user stop colab-gpu-holder.service 2>/dev/null
if [ -z "$session" ]; then
  echo "$(ts) no session recorded and none given; nothing held"
  colab sessions </dev/null 2>&1 || true
  exit 0
fi
if ! colab sessions </dev/null 2>&1 | grep -qF "[$session]"; then
  echo "$(ts) $session is not running; hold cleared"
  rm -f "$state/session" "$state/idle" "$state/phase"
  exit 0
fi

# /content goes away with the runtime, so save first. Capped like the watchdog's save.
if command -v timeout >/dev/null 2>&1; then
  timeout 900 bash scripts/drive-save.sh "$session" || echo "$(ts) drive-save did not finish; outputs stay only on the VM"
else
  bash scripts/drive-save.sh "$session" || echo "$(ts) drive-save did not finish; outputs stay only on the VM"
fi
colab stop -s "$session" </dev/null
colab sessions </dev/null || true
colab usage </dev/null | LC_ALL=C tr -cd '\11\12\40-\176' | head -2 || true
rm -f "$state/session" "$state/idle" "$state/phase" "$state/balance_start" "$state/released"
