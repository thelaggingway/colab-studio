#!/usr/bin/env bash
# Copy a session's finished outputs to Google Drive, using the restored Colab CLI login.
#
# Usage: scripts/drive-save.sh <session> [remote_dir=/content/ComfyUI/output] [date=UTC today]
# Writes to "<DRIVE_FOLDER>/outputs/<date>/<session>/" in Drive, keeping subfolders.
#
# Run it on the machine that holds the login (an Amp orb, a laptop, another VM): it lists the
# files over ssh, downloads each one with `colab download`, then uploads them with
# scripts/drive_save.py. The token never leaves the keyring and is never printed.
#
# Drive refuses this login without a quota project, so set DRIVE_QUOTA_PROJECT in
# config/account.env once (see docs/runbook.md). With DRIVE_SAVE=auto and no project, this
# exits 0 without uploading, so the GPU can still be released.
set -euo pipefail
cd "$(dirname "$0")/.."
source config/account.env
session="${1:-}"
remote="${2:-/content/ComfyUI/output}"
date="${3:-$(date -u +%F)}"
if [ -z "$session" ]; then
  echo "usage: scripts/drive-save.sh <session> [remote_dir] [date]" >&2
  exit 2
fi
if [ "${DRIVE_SAVE:-auto}" = "0" ]; then
  echo "drive-save: DRIVE_SAVE=0, skipped"
  exit 0
fi
project="${DRIVE_QUOTA_PROJECT:-${GOOGLE_CLOUD_PROJECT:-}}"
if [ -z "$project" ] && [ "${DRIVE_SAVE:-auto}" = "auto" ]; then
  echo "drive-save: skipped, no DRIVE_QUOTA_PROJECT set (docs/runbook.md step 7)"
  exit 0
fi

list="$(bash scripts/colab-ssh.sh "$session" "cd '$remote' 2>/dev/null && find . -type f -printf '%P\n' | sort" </dev/null || true)"
if [ -z "$list" ]; then
  echo "drive-save: no files under $remote on $session"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
n=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mkdir -p "$tmp/$(dirname "$rel")"
  colab download -s "$session" "$remote/$rel" "$tmp/$rel" </dev/null >/dev/null
  n=$((n + 1))
done <<<"$list"
echo "drive-save: copied $n file(s) from $session:$remote"

TOOL_PY="$(uv tool dir 2>/dev/null)/google-colab-cli/bin/python"
if [ ! -x "$TOOL_PY" ]; then
  echo "drive-save: the Colab CLI is not installed; run scripts/bootstrap.sh" >&2
  exit 1
fi
args=("$tmp" --dest "$DRIVE_FOLDER/outputs/$date/$session")
if [ -n "$project" ]; then args+=(--quota-project "$project"); fi
if [ -n "${DRIVE_VERIFY:-}" ]; then args+=(--verify); fi
exec "$TOOL_PY" scripts/drive_save.py "${args[@]}"
