#!/usr/bin/env bash
# Get a GPU, set up a recipe on it, forward ComfyUI's port, then hold the GPU until it has been idle.
# Usage: scripts/studio-up.sh <session> <recipe> <grab_minutes> <idle_minutes> <gpu> [gpu...]
#   e.g. scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4
# In an Amp orb run it as a supervised service, so it survives CLI restarts:
#   amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
# On a machine that should hold the GPU itself, run scripts/gpu-holder.sh instead: it runs this
# script as a systemd --user service (see docs/gpu-holder.md).
# Set STUDIO_KEEP=1 to leave the GPU running when setup fails (for debugging).
# Set STUDIO_PARK=0 to exit when the watchdog releases the GPU instead of parking forever; the
# durable holder uses that, because its supervisor must not grab a fresh GPU.
# Full procedure and expected output: docs/runbook.md
set -euo pipefail
cd "$(dirname "$0")/.."
source config/account.env
if [ $# -lt 5 ]; then
  echo "usage: scripts/studio-up.sh <session> <recipe> <grab_minutes> <idle_minutes> <gpu> [gpu...]" >&2
  exit 2
fi
session="$1"; recipe="recipes/$2"; grab="$3"; idle="$4"; shift 4
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
mkdir -p "$state"
export COLAB_STUDIO_STATE="$state"
ts() { date -u +%T; }
balance() { colab usage </dev/null 2>&1 | sed -n 's/^Current balance: \([0-9.]*\).*/\1/p' | head -1; }
phase() { printf '%s\n' "$1" >"$state/phase"; }

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
forward_pid=""
cleanup() {
  rc=$?
  [ -n "$forward_pid" ] && kill "$forward_pid" 2>/dev/null
  if [ "$rc" -ne 0 ] && [ "$assigned" = 1 ] && [ "${STUDIO_KEEP:-0}" != "1" ]; then
    echo "$(ts) failed (rc=$rc); stopping $session so it stops billing"
    colab stop -s "$session" </dev/null || true
    colab sessions </dev/null || true
  fi
}
trap cleanup EXIT
# Stopping or restarting the service must not release the GPU: the idle watchdog is what
# releases it. (SIGKILL and an orb shutdown cannot be caught; Colab's idle timeout is the backstop.)
trap 'exit 0' TERM INT

phase grabbing
rm -f "$state/released" "$state/idle"
# grab-gpu.sh adopts a session that already exists instead of asking for a second GPU, so the
# session this run ends up with may not be the name we passed. It prints SESSION=<name> either way.
set +e
bash scripts/grab-gpu.sh "$session" "$grab" "$@" 2>&1 | tee "$state/grab.log"
grab_rc=${PIPESTATUS[0]}
set -e
if [ "$grab_rc" -ne 0 ]; then
  echo "$(ts) no GPU held (grab exited $grab_rc)"
  exit "$grab_rc"
fi
session="$(sed -n 's/^SESSION=//p' "$state/grab.log" | tail -1)"
[ -n "$session" ] || session="$1"
assigned=1
t0=$(date +%s)
printf '%s\n' "$session" >"$state/session"
printf '%s\n' "$b0" >"$state/balance_start"
phase holding
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

# The forward dies on its own when the VM or the network hiccups; the keeper re-opens it and exits
# when the session is gone.
bash scripts/port-forward.sh "$session" 8188 8188 &
forward_pid=$!
up=0
for _ in $(seq 120); do
  if curl -sf -o /dev/null http://127.0.0.1:8188/; then up=1; break; fi
  sleep 1
done
if [ "$up" != 1 ]; then
  echo "$(ts) comfyui did not answer on 127.0.0.1:8188 in 120s; read /content/comfy.log on the VM" >&2
  exit 1
fi
echo "$(ts) comfyui reachable on 127.0.0.1:8188 after $(( $(date +%s) - t0 ))s"
echo "$(ts) open it with: amp orb portal 8188 --title 'ComfyUI'  (or http://127.0.0.1:8188 on this machine)"

bash scripts/idle-stop.sh "$session" "$idle"
if [ "${STUDIO_PARK:-1}" = 1 ]; then
  # The service supervisor restarts this script when it exits, so exiting here would grab a
  # fresh GPU seconds after the watchdog released the last one. Park until the service is
  # stopped instead.
  echo "$(ts) $session released by the watchdog; stop this service with: amp orb service stop <name>"
  sleep infinity
fi
echo "$(ts) $session released by the watchdog"
