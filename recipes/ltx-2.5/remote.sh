#!/usr/bin/env bash
# Runs on the Colab VM: install ComfyUI, pull LTX-2.5 weights with aria2, start ComfyUI on 127.0.0.1:8188.
# Expects /content/models.txt (copied from this folder) and /content/.hf_token (the Lightricks repo is gated).
# Write the token first, without printing it:
#   printf %s "$HF_TOKEN" | bash scripts/colab-ssh.sh <session> 'umask 077; cat > /content/.hf_token'
set -euo pipefail
cd /content
[ -s /content/.hf_token ] || { echo "missing /content/.hf_token (Lightricks/LTX-2.5 is gated)" >&2; exit 1; }
[ -d ComfyUI ] || git clone -q --depth 1 https://github.com/comfyanonymous/ComfyUI
command -v aria2c >/dev/null || { apt-get -y -qq update >/dev/null; apt-get -y -qq install aria2 >/dev/null; }
( cd ComfyUI && pip install -q -r requirements.txt ) > /content/pip.log 2>&1 &
start=$(date +%s)
aria2c -q -x16 -s16 -j6 --auto-file-renaming=false --allow-overwrite=true \
  --header="Authorization: Bearer $(cat /content/.hf_token)" -i /content/models.txt
echo "download_seconds=$(( $(date +%s) - start ))"
wait
cd ComfyUI
curl -sf -o /dev/null http://127.0.0.1:8188/ && { echo "comfyui already running"; exit 0; }
nohup python main.py --listen 127.0.0.1 --port 8188 > /content/comfy.log 2>&1 < /dev/null &
echo "comfyui started"
