#!/bin/bash
# Software simulation of agent light — compare with physical LEDs
# Usage: ./simulate.sh
# Run in a separate terminal alongside the physical lights

SCRIPT_DIR="$(dirname "$0")"
STATE_FILE="$SCRIPT_DIR/.group_state"

# ANSI colors matching real LEDs
BG_RED="\033[48;5;196m\033[97m"
BG_YLW="\033[48;5;220m\033[30m"
BG_GRN="\033[48;5;34m\033[97m"
BG_OFF="\033[48;5;236m\033[245m"
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[90m"

DOT_RED="\033[91m●\033[0m"
DOT_YLW="\033[93m●\033[0m"
DOT_GRN="\033[92m●\033[0m"
DOT_OFF="\033[90m○\033[0m"

render_group() {
  local group="$1"
  local line=$(grep "^$group:" "$STATE_FILE" 2>/dev/null)

  local cmd=$(echo "$line" | cut -d: -f2)
  local status=$(echo "$line" | cut -d: -f3)
  local event=$(echo "$line" | cut -d: -f4)
  local ts=$(echo "$line" | cut -d: -f5-6)
  local sid=$(echo "$line" | cut -d: -f7)

  # LED indicator
  local led_r="$DOT_OFF"
  local led_y="$DOT_OFF"
  local led_g="$DOT_OFF"
  local bg="$BG_OFF"
  local label="OFF"

  case "$cmd" in
    R) led_r="$DOT_RED"; bg="$BG_RED"; label="RUNNING" ;;
    Y) led_y="$DOT_YLW"; bg="$BG_YLW"; label="WAITING" ;;
    G) led_g="$DOT_GRN"; bg="$BG_GRN"; label="DONE   " ;;
    O|"") bg="$BG_OFF"; label="OFF    " ;;
  esac

  echo -e "  ${BOLD}Group $group${RESET}  $led_r $led_y $led_g  ${bg} $label ${RESET}  ${DIM}${event:-—}  ${ts:-—}  sid:${sid:-—}${RESET}"
}

touch "$STATE_FILE"

while true; do
  clear
  echo ""
  echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "  ${BOLD}║           🤖 AGENT LIGHT — SOFTWARE SIM                ║${RESET}"
  echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  for g in 1 2 3 4; do
    render_group "$g"
  done

  echo ""
  echo -e "  ${DIM}── Legend ──${RESET}"
  echo -e "  $DOT_RED Red = Running   $DOT_YLW Yellow = Waiting   $DOT_GRN Green = Done   $DOT_OFF Off"
  echo ""

  # Mismatch detection: check if state file is stale (>5 min old)
  for g in 1 2 3 4; do
    line=$(grep "^$g:" "$STATE_FILE" 2>/dev/null)
    if [ -n "$line" ]; then
      ts=$(echo "$line" | cut -d: -f5-6)
      if [ -n "$ts" ]; then
        state_epoch=$(date -j -f "%m-%d %H:%M:%S" "$ts" "+%s" 2>/dev/null)
        now_epoch=$(date "+%s")
        if [ -n "$state_epoch" ]; then
          age=$(( now_epoch - state_epoch ))
          cmd=$(echo "$line" | cut -d: -f2)
          if [ "$age" -gt 300 ] && [ "$cmd" = "R" ]; then
            echo -e "  ${BG_RED} ⚠ Group $g stuck on RED for ${age}s — session may be dead ${RESET}"
          fi
        fi
      fi
    fi
  done

  echo ""
  echo -e "  ${DIM}Compare with physical LEDs · Refreshing every 0.5s · Ctrl+C to quit${RESET}"

  sleep 0.5
done
