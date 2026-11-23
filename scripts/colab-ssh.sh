#!/usr/bin/env bash
# Plain ssh into a Colab session through the CLI's proxy, so stdin, -L forwards and -f work normally.
# Usage: scripts/colab-ssh.sh <session> [ssh args...]
#   scripts/colab-ssh.sh h3 'bash -s' < recipes/minimax-h3/remote.sh
#   scripts/colab-ssh.sh h3 -f -N -L 8188:localhost:8188
session="$1"; shift
opts=()
while [ $# -gt 0 ] && [[ "$1" == -* ]]; do
  opts+=("$1"); shift
  [[ "${opts[-1]}" =~ ^-[LRDo]$ ]] && { opts+=("$1"); shift; }
done
# Colab allows one SSH connection per runtime (HTTP 429 otherwise), so every call shares one master.
exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes \
  -o ControlMaster=auto -o ControlPath="/tmp/colab-ssh-$session" -o ControlPersist=yes \
  -o ProxyCommand="$(command -v colab) ssh --proxy-mode -s $session" "${opts[@]}" root@colab "$@"
