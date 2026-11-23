#!/usr/bin/env bash
# Keep asking Colab for a GPU until one is free or time runs out. Busy GPUs answer 503.
# Usage: scripts/grab-gpu.sh <session> <minutes> <gpu> [gpu...]   e.g. grab-gpu.sh h3 60 A100 G4
# Prints GOT=<gpu> and exits 0 on success; exits 1 when time runs out.
set -u
session="$1"; minutes="$2"; shift 2
export COLAB_CLI_ASSIGN_RETRIES=1 COLAB_CLI_RETRY_BACKOFF=10
end=$(( $(date +%s) + minutes * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
  for g in "$@"; do
    if colab new -s "$session" --gpu "$g" </dev/null >"/tmp/grab-$session.log" 2>&1; then
      echo "$(date -u +%T) GOT=$g"; exit 0
    fi
    echo "$(date -u +%T) $g busy"
  done
done
echo "$(date -u +%T) no GPU after ${minutes}m"; exit 1
