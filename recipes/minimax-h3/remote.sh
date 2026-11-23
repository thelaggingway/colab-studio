#!/usr/bin/env bash
# Runs on the Colab VM: install ComfyUI, pull MiniMax H3 weights with aria2, start ComfyUI on 127.0.0.1:8188.
# Expects /content/models.txt (copied from this folder by scripts/studio-up.sh) and, for gated
# models, /content/.hf_token (forwarded by studio-up.sh from the HF_TOKEN environment variable).
set -euo pipefail
cd /content
[ -d ComfyUI ] || git clone -q --depth 1 https://github.com/comfyanonymous/ComfyUI
command -v aria2c >/dev/null || { apt-get -y -qq update >/dev/null; apt-get -y -qq install aria2 >/dev/null; }
( cd ComfyUI && pip install -q -r requirements.txt ) > /content/pip.log 2>&1 &
start=$(date +%s)
hf=()
if [ -s /content/.hf_token ]; then
  hf=(--header="Authorization: Bearer $(cat /content/.hf_token)")
  echo "using HF_TOKEN for downloads"
fi
# The out= lines in models.txt matter: without them Hugging Face redirects are saved
# under hash names, and ComfyUI then reports "Missing Models".
aria2c -q -x16 -s16 -j5 --auto-file-renaming=false --allow-overwrite=true "${hf[@]}" -i /content/models.txt
echo "download_seconds=$(( $(date +%s) - start ))"
wait

# Every file models.txt names must be there, or the workflow reports missing models.
missing=0
while read -r f; do
  [ -s "$f" ] || { echo "missing: $f"; missing=1; }
done < <(awk '/^[[:space:]]*dir=/ {sub(/^[[:space:]]*dir=/,""); d=$0}
              /^[[:space:]]*out=/ {sub(/^[[:space:]]*out=/,""); print d "/" $0}' /content/models.txt)
if [ "$missing" != 0 ]; then
  echo "download incomplete; check /content/models.txt and /content/pip.log"
  exit 1
fi

cd ComfyUI
nohup python main.py --listen 127.0.0.1 --port 8188 > /content/comfy.log 2>&1 < /dev/null &
echo "comfyui started"
