#!/usr/bin/env bash
# Watch the held GPU and alert on problems. Runs from a systemd timer every few minutes, so a paused
# or crashed agent thread cannot silence it. See docs/gpu-holder.md.
#
# Usage: scripts/gpu-monitor.sh [--test]
#   --test sends one test alert and exits, to check the channel.
#
# Alerts go to $ALERT_WEBHOOK when it is set (an ntfy topic URL, or a Slack incoming webhook URL),
# and always to $COLAB_STUDIO_STATE/monitor.log. The same alert repeats at most every
# ALERT_REPEAT_MIN minutes. Configuration lives in ~/.config/colab-studio/alerts.env:
#   ALERT_WEBHOOK=https://ntfy.sh/colab-studio-xxxxxxxx      # no account needed
#   ALERT_WEBHOOK=https://hooks.slack.com/services/T.../B.../...   # Slack incoming webhook
#   ALERT_REPEAT_MIN=60        RATE_CAP=12        SPEND_CAP_UNITS=25
#   MONITOR_RESTART=1          RESTART_COOLDOWN_MIN=15
set -uo pipefail
cd "$(dirname "$0")/.."
source config/account.env
state="${COLAB_STUDIO_STATE:-$HOME/.local/state/colab-studio}"
conf="${COLAB_STUDIO_CONFIG:-$HOME/.config/colab-studio}"
mkdir -p "$state"
[ -f "$conf/alerts.env" ] && . "$conf/alerts.env"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_KIND="${ALERT_KIND:-}"
ALERT_REPEAT_MIN="${ALERT_REPEAT_MIN:-60}"
RATE_CAP="${RATE_CAP:-12}"                 # units/hr; above a G4 (about 10) and well above an A100
SPEND_CAP_UNITS="${SPEND_CAP_UNITS:-25}"   # units spent since this hold started; about 3.7 A100 hours
MONITOR_RESTART="${MONITOR_RESTART:-1}"
RESTART_COOLDOWN_MIN="${RESTART_COOLDOWN_MIN:-15}"
log="$state/monitor.log"
ts() { date -u +%FT%TZ; }

# One alert per key per repeat window, so a condition that lasts an hour is one message, not twelve.
alert() {
  local key="$1" msg="$2" last prev
  last="$state/alert-$key"
  if [ -f "$last" ]; then
    prev="$(cat "$last")"
    if [ $(( ($(date +%s) - prev) / 60 )) -lt "$ALERT_REPEAT_MIN" ]; then return 0; fi
  fi
  printf '%s\n' "$(date +%s)" >"$last"
  printf '%s ALERT %s: %s\n' "$(ts)" "$key" "$msg" >>"$log"
  if [ -z "$ALERT_WEBHOOK" ]; then
    printf '%s (no ALERT_WEBHOOK set; alert only in %s)\n' "$(ts)" "$log" >>"$log"
    return 0
  fi
  local kind="$ALERT_KIND"
  [ -n "$kind" ] || case "$ALERT_WEBHOOK" in *ntfy*) kind=ntfy ;; *) kind=json ;; esac
  local ok=1
  if [ "$kind" = ntfy ]; then
    curl -fsS -m 20 -H "Title: colab gpu $key" -H "Priority: high" --data-binary "$msg" \
      "$ALERT_WEBHOOK" >/dev/null || ok=0
  else
    curl -fsS -m 20 -H 'Content-type: application/json' \
      --data-binary "$(jq -n --arg t "colab gpu $key: $msg" '{text:$t}')" "$ALERT_WEBHOOK" >/dev/null || ok=0
  fi
  [ "$ok" = 1 ] && printf '%s sent %s alert\n' "$(ts)" "$kind" >>"$log" \
    || printf '%s FAILED to send alert to %s\n' "$(ts)" "$ALERT_WEBHOOK" >>"$log"
}

if [ "${1:-}" = "--test" ]; then
  printf 'monitor test from %s\n%s\n' "$(hostname)" "$(bash scripts/gpu-status.sh)"
  alert test "monitor test from $(hostname): $(bash scripts/gpu-status.sh)"
  exit 0
fi

line="$(bash scripts/gpu-status.sh)"
val() { printf '%s\n' "$line" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -1; }
# A number, or a ? that means "could not read it" (not signed in, Colab unreachable).
isnum() { case "$1" in ''|*[!0-9.]*) return 1 ;; esac; return 0; }
count="$(val count)"; holder="$(val holder)"; phase="$(val phase)"; desired="$(val desired)"
session="$(val session)"; gpu="$(val gpu)"; rate="$(val rate)"; balance="$(val balance)"
count="${count:-0}"; holder="${holder:-unknown}"; phase="${phase:--}"; desired="${desired:-no}"
rate="${rate%/hr}"   # gpu-status prints "6.73/hr" for people; the checks want the number

# Restart the holder so it grabs or adopts again, but not more often than the cooldown and never
# with the balance below MIN_BALANCE.
restart_holder() {
  local why="$1" now prev
  [ "$MONITOR_RESTART" = 1 ] || return 0
  now="$(date +%s)"
  if [ -f "$state/last_restart" ]; then
    prev="$(cat "$state/last_restart")"
    if [ $(( (now - prev) / 60 )) -lt "$RESTART_COOLDOWN_MIN" ]; then
      printf '%s restart skipped (%s): one %sm ago\n' "$(ts)" "$why" "$(( (now - prev) / 60 ))" >>"$log"
      return 0
    fi
  fi
  if isnum "$balance" && awk "BEGIN{exit !($balance < $MIN_BALANCE)}"; then
    printf '%s restart skipped (%s): balance %s is below MIN_BALANCE %s\n' \
      "$(ts)" "$why" "$balance" "$MIN_BALANCE" >>"$log"
    return 0
  fi
  printf '%s\n' "$now" >"$state/last_restart"
  printf '%s restarting colab-gpu-holder (%s)\n' "$(ts)" "$why" >>"$log"
  # reset-failed first: after StartLimitBurst a plain restart is refused until the unit is cleared.
  systemctl --user reset-failed colab-gpu-holder.service 2>/dev/null
  systemctl --user restart colab-gpu-holder.service
}

if [ "$count" -gt 1 ]; then
  alert many-sessions "$count sessions are running ($session); each one bills. Stop the ones you do not need: colab stop -s <name>"
fi

if [ "$desired" = yes ]; then
  case "$phase" in
    holding)
      if [ "$count" -eq 0 ]; then
        alert gpu-lost "hold requested but no Colab session exists (last: $session $gpu); the GPU was lost. Restarting the holder to grab another. Balance $balance, rate $rate/hr"
        restart_holder gpu-lost
      elif [ "$holder" != active ] && [ "$holder" != activating ]; then
        alert holder-down "holder is $holder while $session ($gpu) is still running: no idle watchdog, so it bills until Colab reclaims it. Restarting the holder"
        restart_holder holder-down
      fi
      ;;
    grabbing)
      if [ "$holder" != active ] && [ "$holder" != activating ]; then
        alert holder-down "holder is $holder while it should be waiting for a GPU; no GPU is held. Restarting the holder"
        restart_holder holder-down
      fi
      ;;
    *)
      if [ "$holder" = failed ]; then
        alert holder-failed "the holder failed (phase $phase) with a hold requested; see journalctl --user -u colab-gpu-holder -n 40. Restarting it"
        restart_holder holder-failed
      elif [ "$holder" != active ] && [ "$holder" != activating ]; then
        alert holder-not-running "a hold is requested but the holder is $holder and nothing is being held; start it with: systemctl --user start colab-gpu-holder"
      fi
      ;;
  esac
else
  if [ "$count" -gt 0 ]; then
    alert unheld-session "session $session ($gpu) is running with no hold requested, so it bills with no watchdog. Stop it: colab stop -s $session"
  fi
fi

if isnum "$rate" && awk "BEGIN{exit !($rate > $RATE_CAP)}"; then
  alert rate-cap "usage rate is $rate/hr, over the $RATE_CAP/hr cap ($session $gpu). Balance $balance"
fi

if [ -f "$state/balance_start" ] && isnum "$balance"; then
  start="$(cat "$state/balance_start")"
  if awk "BEGIN{exit !($start - $balance > $SPEND_CAP_UNITS)}"; then
    alert spend-cap "this hold has spent $(awk "BEGIN{printf \"%.2f\", $start - $balance}") units, over the $SPEND_CAP_UNITS cap ($start at grab, $balance now, $session $gpu)"
  fi
fi
