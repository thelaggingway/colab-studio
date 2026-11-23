#!/usr/bin/env bash
# Plain ssh into a Colab session through the CLI's proxy, so stdin, -L forwards and -f work normally.
# Colab allows one SSH connection per runtime (a second gets HTTP 429), so every call shares one
# ControlMaster connection, including the port forward started by scripts/studio-up.sh.
#
# Usage: scripts/colab-ssh.sh <session> [ssh args...]
#   scripts/colab-ssh.sh h3 'bash -s' < recipes/minimax-h3/remote.sh
#   scripts/colab-ssh.sh h3 -f -N -L 8188:localhost:8188
#   scripts/colab-ssh.sh h3 'nvidia-smi -L'
session="${1:-}"
if [ -z "$session" ]; then
  echo "usage: scripts/colab-ssh.sh <session> [ssh args...]" >&2
  exit 2
fi
shift
opts=()
while [ $# -gt 0 ] && [[ "$1" == -* ]]; do
  opts+=("$1"); shift
  [[ "${opts[-1]}" =~ ^-[LRDo]$ ]] && { opts+=("$1"); shift; }
done
if [ ${#opts[@]} -eq 0 ] && [ $# -eq 0 ]; then
  echo "colab-ssh.sh: give a command ('bash -s') or ssh options (-f -N -L port:localhost:port)" >&2
  exit 2
fi
# BatchMode: an agent has no password to type, so fail instead of prompting.
exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o BatchMode=yes \
  -o ControlMaster=auto -o ControlPath="/tmp/colab-ssh-$session" -o ControlPersist=yes \
  -o ProxyCommand="$(command -v colab) ssh --proxy-mode -s $session" "${opts[@]}" root@colab "$@"
