#!/usr/bin/env bash
# Hold one Colab GPU from this machine, outside any agent thread.
#
# An Amp orb pauses when its thread goes idle and dies when the thread crashes; either way the port
# forward and the idle watchdog stop, and Colab reclaims the runtime about 20 minutes later. This
# script runs the same flow (scripts/studio-up.sh: adopt or grab, recipe setup, port forward, idle
# watchdog) as a systemd --user service, so a held GPU outlives the thread that asked for it, a
# logout, and a reboot. See docs/gpu-holder.md.
#
# Usage: scripts/gpu-holder.sh
#   Reads ~/.config/colab-studio/holder.env (written by scripts/gpu-request.sh):
#     HOLDER_SESSION   session name to create, e.g. h3
#     HOLDER_RECIPE    recipe directory under recipes/, e.g. minimax-h3
#     HOLDER_GRAB_MIN  minutes to keep trying for a GPU (default 60)
#     HOLDER_IDLE_MIN  idle minutes before the watchdog releases it (default 60)
#     HOLDER_GPUS      GPUs to try in order (default $GPU)
#   and holds only while $COLAB_STUDIO_STATE/desired exists, so the unit can be enabled at boot
#   without grabbing a GPU nobody asked for.
#
# Exit codes: 0 = released by the watchdog or stopped on request, non-zero = failed (the unit's
# Restart=on-failure tries again while the hold is still requested).
set -uo pipefail
cd "$(dirname "$0")/.."
source config/account.env
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
conf="${COLAB_STUDIO_CONFIG:-$HOME/.config/colab-studio}"
mkdir -p "$state"
[ -f "$conf/holder.env" ] && . "$conf/holder.env"
export COLAB_STUDIO_STATE="$state"
ts() { date -u +%T; }
phase() { printf '%s\n' "$1" >"$state/phase"; }

# One holder at a time: a second one would grab a second GPU.
exec 9>"$state/holder.lock"
if ! flock -n 9; then
  echo "$(ts) another holder is already running; exiting"
  exit 0
fi

if [ ! -f "$state/desired" ]; then
  echo "$(ts) no hold requested ($state/desired is absent); exiting"
  phase idle
  exit 0
fi

session="${HOLDER_SESSION:-gpu}"
recipe="${HOLDER_RECIPE:-}"
gpus="${HOLDER_GPUS:-$GPU}"
grab_min="${HOLDER_GRAB_MIN:-60}"
idle_min="${HOLDER_IDLE_MIN:-60}"
if [ -z "$recipe" ] || [ ! -f "recipes/$recipe/remote.sh" ]; then
  echo "$(ts) HOLDER_RECIPE is unset or recipes/$recipe/remote.sh does not exist; run scripts/gpu-request.sh" >&2
  phase failed
  exit 2
fi

echo "$(ts) holding: session=$session recipe=$recipe gpus=$gpus grab=${grab_min}m idle=${idle_min}m"
phase starting
STUDIO_PARK=0 bash scripts/studio-up.sh "$session" "$recipe" "$grab_min" "$idle_min" $gpus
rc=$?

if [ "$rc" -eq 0 ] && [ -f "$state/released" ]; then
  # The watchdog stopped the GPU, so the hold is finished. Clear it, or the next boot would grab
  # another GPU nobody asked for.
  rm -f "$state/desired" "$state/released" "$state/idle" "$state/session"
  phase idle
  echo "$(ts) hold finished: the idle watchdog released $session; nothing is held now"
  exit 0
fi
if [ "$rc" -eq 0 ]; then
  # Stopped on request (systemctl --user stop, or a reboot). Keep the hold so the next start or
  # boot adopts the same session again; scripts/gpu-release.sh is how a hold is ended.
  phase idle
  echo "$(ts) holder stopped on request; the hold stays requested for the next start or boot"
  exit 0
fi
phase failed
echo "$(ts) holder failed (rc=$rc); systemd retries while the hold is still requested" >&2
exit "$rc"
