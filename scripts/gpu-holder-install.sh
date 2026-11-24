#!/usr/bin/env bash
# Install the GPU holder and its monitor as systemd --user services on this machine.
# Usage: scripts/gpu-holder-install.sh
# Needs no sudo: user units, plus linger (already on for this account; the script says if it is not).
# It enables the monitor timer now, and enables (does not start) the holder: a GPU is grabbed only
# when scripts/gpu-request.sh asks for one. See docs/gpu-holder.md.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
conf="${COLAB_STUDIO_CONFIG:-$HOME/.config/colab-studio}"
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$unit_dir" "$conf" "$state"

for unit in colab-gpu-holder.service colab-gpu-monitor.service colab-gpu-monitor.timer; do
  sed "s|@REPO@|$repo|g" "$repo/config/systemd/$unit" >"$unit_dir/$unit"
  echo "installed $unit_dir/$unit"
done

if [ ! -f "$conf/alerts.env" ]; then
  cat >"$conf/alerts.env" <<'EOF'
# Where the GPU monitor sends alerts, and its caps. See docs/gpu-holder.md.
# Uncomment one line. Without a webhook, alerts only go to
# ~/.local/state/colab-studio/monitor.log.
#
# ntfy (no account or credential; pick a long random topic and subscribe to it in the ntfy app):
#ALERT_WEBHOOK=https://ntfy.sh/colab-studio-CHANGE-ME
# Slack incoming webhook (create one in the Slack app settings):
#ALERT_WEBHOOK=https://hooks.slack.com/services/T000/B000/xxxx
#
# Same alert at most this often, in minutes.
#ALERT_REPEAT_MIN=60
# Alert above this live usage rate (units/hr). A100 6.73, L4 1.9, T4 1.5, G4 about 10.
#RATE_CAP=12
# Alert once a single hold has spent this many units.
#SPEND_CAP_UNITS=25
# Restart the holder when the GPU is lost or the holder dies (1 = yes), at most every N minutes.
#MONITOR_RESTART=1
#RESTART_COOLDOWN_MIN=15
EOF
  echo "wrote $conf/alerts.env (no webhook set yet: alerts go to $state/monitor.log)"
fi

systemctl --user daemon-reload
systemctl --user enable --now colab-gpu-monitor.timer
# Enabled so a hold survives a reboot; the holder exits at once unless a hold is requested.
systemctl --user enable colab-gpu-holder.service

echo
echo "linger (must be yes for the services to run without a login and after a reboot):"
loginctl show-user "$USER" -p Linger || true
echo
systemctl --user list-timers colab-gpu-monitor.timer --no-pager
echo
echo "next: scripts/gpu-request.sh <session> <recipe> [grab_min] [idle_min] [gpu...]"
