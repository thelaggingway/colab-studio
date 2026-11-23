#!/usr/bin/env bash
# Keep asking Colab for a GPU until one is free or time runs out. Busy GPUs answer HTTP 503.
# Usage: scripts/grab-gpu.sh <session> <minutes> <gpu> [gpu...]   e.g. grab-gpu.sh h3 60 A100 G4
# Prints GOT=<gpu> and exits 0 on success; exits 1 when time runs out, when Colab refuses
# the assignment (HTTP 412), or when no requested GPU is left.
#
# Output is one line per attempt, so it can be read back from a service log:
#   16:27:05 A100 busy (503)
#   16:27:16 G4 rejected (not entitled; dropping it)
#   16:31:02 GOT=A100
#
# Each attempt uses one CLI retry (~10 s), not a long retry ladder: the CLI doubles its
# delay per retry (backoff * 2^n), so large COLAB_CLI_ASSIGN_RETRIES values wait for hours.
#
# COLAB_NEW_ARGS adds flags to every `colab new`, e.g. COLAB_NEW_ARGS=--high-mem for the
# high-RAM T4 (12.7 GB RAM cannot hold MiniMax H3's 21 GB + 15 GB files; 51 GB can).
set -u
if [ $# -lt 3 ]; then
  echo "usage: scripts/grab-gpu.sh <session> <minutes> <gpu> [gpu...]" >&2
  exit 2
fi
session="$1"; minutes="$2"; shift 2
export COLAB_CLI_ASSIGN_RETRIES=1 COLAB_CLI_RETRY_BACKOFF=10
log="${GRAB_LOG:-/tmp/grab-$session.log}"
pause="${GRAB_PAUSE:-5}"
end=$(( $(date +%s) + minutes * 60 ))
gpus=("$@")
ts() { date -u +%T; }

while [ ${#gpus[@]} -gt 0 ] && [ "$(date +%s)" -lt "$end" ]; do
  left=()
  for g in "${gpus[@]}"; do
    if colab new -s "$session" --gpu "$g" ${COLAB_NEW_ARGS:-} </dev/null >"$log" 2>&1; then
      echo "$(ts) GOT=$g"
      exit 0
    fi
    if grep -q "Backend rejected accelerator" "$log"; then
      echo "$(ts) $g rejected (not entitled; dropping it)"
      continue
    fi
    if grep -q -E "precondition failed|HTTP 412" "$log"; then
      echo "$(ts) $g refused (HTTP 412: too many sessions or a temporary limit); stopping"
      echo "  see 'colab sessions'; stop a session you started, then retry" >&2
      exit 1
    fi
    if ! grep -q -E "Service Unavailable|HTTP 503" "$log"; then
      # Anything else (auth, bad name, network) will not fix itself by retrying.
      echo "$(ts) $g failed: $(LC_ALL=C tr -cd '\11\12\40-\176' <"$log" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-160)"
      echo "  full output: $log" >&2
      exit 1
    fi
    echo "$(ts) $g busy (503)"
    left+=("$g")
  done
  gpus=("${left[@]}")
  if [ ${#gpus[@]} -gt 0 ]; then sleep "$pause"; fi
done

echo "$(ts) no GPU after ${minutes}m${gpus[*]:+ (tried ${gpus[*]})}; last output: $log"
exit 1
