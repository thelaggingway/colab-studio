#!/usr/bin/env bash
# Get a GPU, set up a recipe on it, forward ComfyUI's port, then hold the GPU until it has been idle.
# Usage: scripts/studio-up.sh <session> <recipe> <grab_minutes> <idle_minutes> <gpu> [gpu...]
#   e.g. scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4
# In an Amp orb run it as a supervised service:
#   amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
set -euo pipefail
cd "$(dirname "$0")/.."
session="$1"; recipe="recipes/$2"; grab="$3"; idle="$4"; shift 4
ts() { date -u +%T; }

bash scripts/grab-gpu.sh "$session" "$grab" "$@"
t0=$(date +%s); echo "$(ts) gpu assigned"
colab usage </dev/null | LC_ALL=C tr -cd '\11\12\40-\176' | head -1

[ -f "$recipe/models.txt" ] && bash scripts/colab-ssh.sh "$session" 'cat > /content/models.txt' < "$recipe/models.txt"
bash scripts/colab-ssh.sh "$session" 'bash -s' < "$recipe/remote.sh"
echo "$(ts) setup done in $(( $(date +%s) - t0 ))s"

bash scripts/colab-ssh.sh "$session" -f -N -L 8188:localhost:8188
for _ in $(seq 60); do curl -sf -o /dev/null http://127.0.0.1:8188/ && break; sleep 5; done
echo "$(ts) comfyui reachable on 127.0.0.1:8188 after $(( $(date +%s) - t0 ))s"

bash scripts/idle-stop.sh "$session" "$idle"
