#!/usr/bin/env bash
# Get a GPU, set up a recipe on it, forward ComfyUI's port, then hold the GPU until it has been idle.
# Usage: scripts/studio-up.sh <session> <recipe> <grab_minutes> <idle_minutes> <gpu> [gpu...]
#   e.g. scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4
# In an Amp orb run it as a supervised service, so it survives CLI restarts:
#   amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
# Set STUDIO_KEEP=1 to leave the GPU running when setup fails (for debugging).
# Full procedure and expected output: docs/runbook.md
set -euo pipefail
cd "$(dirname "$0")/.."
source config/account.env
if [ $# -lt 5 ]; then
  echo "usage: scripts/studio-up.sh <session> <recipe> <grab_minutes> <idle_minutes> <gpu> [gpu...]" >&2
  exit 2
fi
session="$1"; recipe="recipes/$2"; grab="$3"; idle="$4"; shift 4
ts() { date -u +%T; }
balance() { colab usage </dev/null 2>&1 | sed -n 's/^Current balance: \([0-9.]*\).*/\1/p' | head -1; }

# Rule 1 of AGENTS.md: do not start a GPU below MIN_BALANCE.
b0="$(balance)"
if [ -z "$b0" ]; then
  echo "$(ts) could not read the balance; run 'colab usage' by hand, then retry" >&2
  exit 1
fi
echo "$(ts) balance before: $b0 units (MIN_BALANCE=$MIN_BALANCE)"
if awk "BEGIN{exit !($b0 < $MIN_BALANCE)}"; then
  echo "$(ts) balance below MIN_BALANCE; not starting a GPU" >&2
  exit 1
fi

# A GPU that is up keeps billing. If anything after the grab fails, release it.
assigned=0
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$assigned" = 1 ] && [ "${STUDIO_KEEP:-0}" != "1" ]; then
    echo "$(ts) failed (rc=$rc); stopping $session so it stops billing"
    colab stop -s "$session" </dev/null || true
    colab sessions </dev/null || true
  fi
}
trap cleanup EXIT

bash scripts/grab-gpu.sh "$session" "$grab" "$@"
assigned=1
t0=$(date +%s)
echo "$(ts) gpu assigned; usage now:"
colab usage </dev/null | LC_ALL=C tr -cd '\11\12\40-\176' | head -2

if [ -f "$recipe/models.txt" ]; then
  bash scripts/colab-ssh.sh "$session" 'cat > /content/models.txt' <"$recipe/models.txt"
fi
# HF_TOKEN lets a recipe pull gated models. It goes over ssh stdin, never in argv or a log.
if [ -n "${HF_TOKEN:-}" ]; then
  printf '%s' "$HF_TOKEN" | bash scripts/colab-ssh.sh "$session" 'umask 077; cat > /content/.hf_token'
  echo "$(ts) HF_TOKEN forwarded to /content/.hf_token"
fi
bash scripts/colab-ssh.sh "$session" 'bash -s' <"$recipe/remote.sh"
echo "$(ts) setup done in $(( $(date +%s) - t0 ))s"

bash scripts/colab-ssh.sh "$session" -f -N -L 8188:localhost:8188
up=0
for _ in $(seq 60); do
  if curl -sf -o /dev/null http://127.0.0.1:8188/; then up=1; break; fi
  sleep 5
done
if [ "$up" != 1 ]; then
  echo "$(ts) comfyui did not answer on 127.0.0.1:8188 in 300s; read /content/comfy.log on the VM" >&2
  exit 1
fi
echo "$(ts) comfyui reachable on 127.0.0.1:8188 after $(( $(date +%s) - t0 ))s"
echo "$(ts) open it with: amp orb portal 8188 --title 'ComfyUI'  (or http://127.0.0.1:8188 on this machine)"

bash scripts/idle-stop.sh "$session" "$idle"
