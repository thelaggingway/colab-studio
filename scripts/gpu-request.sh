#!/usr/bin/env bash
# Ask this machine to hold a GPU, and keep holding it after this shell and its agent thread are gone.
# Usage: scripts/gpu-request.sh <session> <recipe> [grab_minutes=60] [idle_minutes=60] [gpu...]
#   e.g. scripts/gpu-request.sh h3 minimax-h3 60 60 A100 L4
# Defaults: GPUs "$GPU $GPU_SMALL" from config/account.env. Writes ~/.config/colab-studio/holder.env,
# marks the hold as wanted, and (re)starts the colab-gpu-holder service.
# A session that is already running is adopted, not doubled (see scripts/grab-gpu.sh).
# Watch it with scripts/gpu-status.sh, or: journalctl --user -u colab-gpu-holder -f
set -euo pipefail
cd "$(dirname "$0")/.."
source config/account.env
conf="${COLAB_STUDIO_CONFIG:-$HOME/.config/colab-studio}"
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ $# -lt 2 ]; then
  echo "usage: scripts/gpu-request.sh <session> <recipe> [grab_minutes=60] [idle_minutes=60] [gpu...]" >&2
  exit 2
fi
session="$1"; recipe="$2"
shift 2
grab_min=60
idle_min=60
if [ $# -gt 0 ]; then grab_min="$1"; shift; fi
if [ $# -gt 0 ]; then idle_min="$1"; shift; fi
gpus="${*:-$GPU $GPU_SMALL}"

if [ ! -f "recipes/$recipe/remote.sh" ]; then
  echo "no recipes/$recipe/remote.sh; see the recipe index in .agents/skills/colab-studio/SKILL.md" >&2
  exit 2
fi
if ! colab whoami </dev/null >/dev/null 2>&1; then
  echo "not signed in; run scripts/login.sh in the user's own browser first (docs/runbook.md step 1)" >&2
  exit 1
fi

mkdir -p "$conf" "$state"
cat >"$conf/holder.env" <<EOF
# Written by scripts/gpu-request.sh on $(date -u +%FT%TZ). Read by scripts/gpu-holder.sh.
HOLDER_SESSION=$session
HOLDER_RECIPE=$recipe
HOLDER_GRAB_MIN=$grab_min
HOLDER_IDLE_MIN=$idle_min
HOLDER_GPUS="$gpus"
EOF
printf 'requested %s\n' "$(date -u +%FT%TZ)" >"$state/desired"
# reset-failed first: after a burst of failures systemd refuses a restart until the unit is cleared.
systemctl --user reset-failed colab-gpu-holder.service 2>/dev/null || true
systemctl --user restart colab-gpu-holder.service

echo "holding $session with $recipe on $gpus (grab ${grab_min}m, idle ${idle_min}m)"
echo "watch:   journalctl --user -u colab-gpu-holder -f"
echo "status:  scripts/gpu-status.sh"
echo "release: scripts/gpu-release.sh $session"
