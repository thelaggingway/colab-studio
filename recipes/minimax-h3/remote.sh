#!/usr/bin/env bash
# Runs on the Colab VM: install ComfyUI, pull MiniMax H3 weights with aria2, start ComfyUI on 127.0.0.1:8188.
# Expects /content/models.txt (copied from this folder by scripts/studio-up.sh) and, for gated
# models, /content/.hf_token (forwarded by studio-up.sh from the HF_TOKEN environment variable).
# Prints one "<phase>_seconds=N" line per phase, so the next real run can time the setup.
set -euo pipefail
cd /content

# 1. ComfyUI itself: 64 MB, about 5 s. The model folders live inside it, so the download
#    cannot start until this finishes.
t=$(date +%s)
[ -d ComfyUI ] || git clone -q --depth 1 https://github.com/comfyanonymous/ComfyUI
echo "clone_seconds=$(( $(date +%s) - t ))"

# 2. Dependencies in the background, in parallel with the download. uv resolves and fetches in
#    parallel: 63 s against 177 s for pip on ComfyUI's requirements with torch already present
#    (measured 2026-11-23, clean environments, same network). Falls back to pip.
( cd ComfyUI
  t=$(date +%s)
  command -v uv >/dev/null 2>&1 || python -m pip install -q uv >/dev/null 2>&1 || true
  if ! command -v uv >/dev/null 2>&1 || ! uv pip install --system -q -r requirements.txt; then
    python -m pip install -q -r requirements.txt
  fi
  echo "pip_seconds=$(( $(date +%s) - t ))" ) >/content/pip.log 2>&1 &
pip_pid=$!

# 3. aria2. The Colab image's package lists are usually fresh, so try without `apt-get update`
#    first; otherwise that update is a slow step on every fresh runtime.
t=$(date +%s)
if ! command -v aria2c >/dev/null 2>&1; then
  apt-get install -y -qq aria2 >/dev/null 2>&1 ||
    { apt-get -y -qq update >/dev/null; apt-get -y -qq install aria2 >/dev/null; }
fi
echo "apt_seconds=$(( $(date +%s) - t ))"

# 4. Models. The out= lines in models.txt matter: without them Hugging Face redirects are
#    saved under hash names, and ComfyUI then reports "Missing Models".
hf=()
if [ -s /content/.hf_token ]; then
  hf=(--header="Authorization: Bearer $(cat /content/.hf_token)")
  echo "using HF_TOKEN for downloads"
fi
t=$(date +%s)
aria2c -q -x16 -s16 -j5 --auto-file-renaming=false --allow-overwrite=true "${hf[@]}" -i /content/models.txt
echo "download_seconds=$(( $(date +%s) - t ))"

# 5. Dependencies must finish before ComfyUI starts; a failure has to stop the run.
if ! wait "$pip_pid"; then
  echo "dependency install failed; see /content/pip.log"
  exit 1
fi
grep -h '^pip_seconds=' /content/pip.log || true

# 6. Every file models.txt names must be there, or the workflow reports missing models.
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
