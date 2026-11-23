#!/usr/bin/env bash
# Finds out which accelerators this Google account can start right now.
# For each GPU it asks Colab for a runtime; if one is granted it reads nvidia-smi
# and stops it at once. A refusal costs nothing; a granted runtime costs a few
# minutes of units. Results go to probe-results/<date>.md.
#
# Usage: scripts/probe-gpus.sh [GPU ...]   (default: G4 H100 A100 L4 T4)
set -uo pipefail
cd "$(dirname "$0")/.."

gpus=("$@")
[ ${#gpus[@]} -eq 0 ] && gpus=(G4 H100 A100 L4 T4)

mkdir -p probe-results
out="probe-results/$(date -u +%Y-%m-%d).md"
log="$(mktemp)"

{
	echo "# GPU probe $(date -u +'%Y-%m-%d %H:%M UTC')"
	echo
	echo "Balance before:"
	echo '```'
	colab usage 2>&1
	echo '```'
	echo
	echo "| GPU | Result | Device reported | Detail |"
	echo "| --- | --- | --- | --- |"
} >"$out"

for gpu in "${gpus[@]}"; do
	name="probe-$(echo "$gpu" | tr '[:upper:]' '[:lower:]')"
	echo "== $gpu" >&2
	if colab new -s "$name" --gpu "$gpu" >"$log" 2>&1; then
		device="$(colab ssh -s "$name" -- 'nvidia-smi --query-gpu=name,memory.total --format=csv,noheader' </dev/null 2>/dev/null | tail -1)"
		[ -z "$device" ] && device="$(echo '!nvidia-smi --query-gpu=name,memory.total --format=csv,noheader' | colab exec -s "$name" 2>/dev/null | tail -1)"
		colab stop -s "$name" >/dev/null 2>&1 || colab stop -s "$name"
		echo "| $gpu | granted | ${device:-unknown} | stopped right away |" >>"$out"
	else
		detail="$(tr '\n|' '  ' <"$log" | sed 's/  */ /g' | cut -c1-160)"
		echo "| $gpu | refused | | $detail |" >>"$out"
	fi
done

{
	echo
	echo "Balance after:"
	echo '```'
	colab usage 2>&1
	echo '```'
	echo
	echo "Active sessions (should be none):"
	echo '```'
	colab sessions 2>&1
	echo '```'
} >>"$out"

rm -f "$log"
cat "$out"
