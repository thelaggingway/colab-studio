#!/usr/bin/env bash
# One line about the GPU this machine holds.
# Usage: scripts/gpu-status.sh
#   session=h3 gpu=A100 count=1 idle=3m rate=6.73/hr balance=174.42 holder=active phase=holding desired=yes
#
# session  the session name the holder is using, or - ; count is how many sessions exist at all
# gpu      the accelerator Colab reports for it, or -
# idle     minutes since ComfyUI last had a job (the watchdog writes it; stale if it is not running)
# rate     the live usage rate, which is the honest number while the balance still lags
# balance  current compute units
# holder   systemd state of the holder service: active, activating, inactive, failed
# phase    what the holder is doing: starting, grabbing, holding, idle, failed
# desired  yes while a hold is requested
#
# Only free calls: `colab sessions` and `colab usage` never start or bill a GPU. scripts/gpu-monitor.sh
# reads this line, so keep it to key=value pairs separated by single spaces.
set -uo pipefail
cd "$(dirname "$0")/.."
source config/account.env
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

sessions="$(colab sessions </dev/null 2>&1 || true)"
names=()
gpus=()
while IFS= read -r line; do
  # A session line is "[name] endpoint | Hardware: X | ..."; the CLI's own "[colab] ..."
  # messages have no " | Hardware: ", so they are skipped.
  case "$line" in "["*"] "*"Hardware: "*) ;; *) continue ;; esac
  name="${line#\[}"; name="${name%%\]*}"
  hw="${line#*Hardware: }"; hw="${hw%% |*}"
  names+=("$name"); gpus+=("$hw")
done < <(printf '%s\n' "$sessions")

if [ ${#names[@]} -eq 0 ]; then
  session="-"; gpu="-"
else
  session="$(IFS=,; echo "${names[*]}")"
  gpu="$(IFS=,; echo "${gpus[*]}")"
fi

usage="$(colab usage </dev/null 2>&1 || true)"
balance="$(printf '%s\n' "$usage" | sed -n 's/^Current balance: \([0-9.]*\).*/\1/p' | head -1)"
rate="$(printf '%s\n' "$usage" | sed -n 's/^Usage rate: \([0-9.]*\)\/hr.*/\1/p' | head -1)"

idle="-"
if [ -f "$state/idle" ]; then
  idle="$(sed -n 's/.*idle=\([0-9]*\).*/\1/p' "$state/idle")m"
  seen="$(sed -n 's/.*ts=\([0-9]*\).*/\1/p' "$state/idle")"
  # The watchdog writes every minute; a stale file means it is not running, so the number is old.
  if [ -n "$seen" ] && [ $(( $(date +%s) - seen )) -gt 180 ]; then idle="$idle(stale)"; fi
fi

holder="$(systemctl --user is-active colab-gpu-holder.service 2>/dev/null || true)"
[ -n "$holder" ] || holder="unknown"
phase="-"
[ -f "$state/phase" ] && phase="$(head -1 "$state/phase")"
desired=no
[ -f "$state/desired" ] && desired=yes

printf 'session=%s gpu=%s count=%d idle=%s rate=%s/hr balance=%s holder=%s phase=%s desired=%s\n' \
  "$session" "$gpu" "${#names[@]}" "$idle" "${rate:-?}" "${balance:-?}" "$holder" "$phase" "$desired"
