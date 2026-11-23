#!/usr/bin/env bash
# Runs on the Colab VM: install ComfyUI, pull MiniMax H3 weights with aria2, start ComfyUI on 127.0.0.1:8188.
# Expects /content/models.txt (copied from this folder). scripts/studio-up.sh does both steps.
set -euo pipefail
cd /content
[ -d ComfyUI ] || git clone -q --depth 1 https://github.com/comfyanonymous/ComfyUI
command -v aria2c >/dev/null || { apt-get -y -qq update >/dev/null; apt-get -y -qq install aria2 >/dev/null; }
( cd ComfyUI && pip install -q -r requirements.txt ) > /content/pip.log 2>&1 &
start=$(date +%s)
aria2c -q -x16 -s16 -j5 --auto-file-renaming=false --allow-overwrite=true -i /content/models.txt
echo "download_seconds=$(( $(date +%s) - start ))"
wait
cd ComfyUI
nohup python main.py --listen 127.0.0.1 --port 8188 > /content/comfy.log 2>&1 < /dev/null &
echo "comfyui started"
