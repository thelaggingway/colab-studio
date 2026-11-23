#!/usr/bin/env bash
# Stop a Colab session after it has been idle for a while, so a held GPU does not burn units.
# Activity = a ComfyUI job running, queued, or newly finished on the forwarded port.
# Usage: scripts/idle-stop.sh <session> [idle_minutes=60] [comfy_url=http://127.0.0.1:8188]
# In an Amp orb run it as a supervised service so it survives CLI restarts:
#   amp orb service start idle-stop-<session> --command 'bash scripts/idle-stop.sh <session> 60'
# Caveat: it only runs while this machine is up. If the orb is paused or killed, it cannot
# stop the GPU; Colab's own idle timeout is the backstop. Stop the GPU by hand when the work ends.
set -u
if [ $# -lt 1 ]; then
  echo "usage: scripts/idle-stop.sh <session> [idle_minutes=60] [comfy_url]" >&2
  exit 2
fi
session="$1"; minutes="${2:-60}"; url="${3:-http://127.0.0.1:8188}"
here="$(cd "$(dirname "$0")/.." && pwd)"
last_active=$(date +%s); last_hist=""
while :; do
  q=$(curl -s -m 10 "$url/queue" 2>/dev/null)
  busy=$(printf '%s' "$q" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin); print(len(d.get("queue_running",[]))+len(d.get("queue_pending",[])))
except Exception: print(0)')
  hist=$(curl -s -m 10 "$url/history?max_items=1" 2>/dev/null | md5sum | cut -c1-12)
  if [ "$busy" != "0" ] || { [ -n "$last_hist" ] && [ "$hist" != "$last_hist" ]; }; then
    last_active=$(date +%s)
  fi
  last_hist="$hist"
  idle=$(( ($(date +%s) - last_active) / 60 ))
  echo "$(date -u +%T) busy=$busy idle=${idle}m"
  if [ "$idle" -ge "$minutes" ]; then
    echo "idle for ${idle}m, stopping $session"
    # Save finished outputs to Drive before the runtime, and /content, go away. Skipped when
    # Drive is not configured; capped so a slow upload cannot hold the GPU forever.
    if command -v timeout >/dev/null 2>&1; then
      timeout 900 bash "$here/scripts/drive-save.sh" "$session" ||
        echo "drive-save did not finish; outputs stay only on the VM" >&2
    else
      bash "$here/scripts/drive-save.sh" "$session" ||
        echo "drive-save did not finish; outputs stay only on the VM" >&2
    fi
    if colab stop -s "$session" </dev/null; then
      colab sessions </dev/null || true
      colab usage </dev/null | LC_ALL=C tr -cd '\11\12\40-\176' | head -2 || true
      exit 0
    fi
    echo "colab stop failed; stop it by hand: colab stop -s $session" >&2
    exit 1
  fi
  sleep 60
done
