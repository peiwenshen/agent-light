#!/bin/bash
# Real-time status display for agent light
# Run in a separate terminal: ./status.sh

LOG_FILE="$(dirname "$0")/light.log"
touch "$LOG_FILE"

# ANSI colors
BLUE="\033[48;5;27m\033[97m"
GREEN="\033[48;5;34m\033[97m"
YELLOW="\033[48;5;220m\033[30m"
RED="\033[48;5;196m\033[97m"
DIM="\033[48;5;236m\033[245m"
RESET="\033[0m"
BOLD="\033[1m"

get_light() {
  local last
  last=$(tail -1 "$LOG_FILE" 2>/dev/null)
  echo "$last"
}

get_color_block() {
  local status="$1"
  case "$status" in
    *RUNNING*) echo -e "${BLUE}  ● RUNNING  ${RESET}" ;;
    *DONE*)    echo -e "${GREEN}  ● DONE     ${RESET}" ;;
    *WAITING*) echo -e "${YELLOW}  ● WAITING  ${RESET}" ;;
    *ERROR*)   echo -e "${RED}  ● ERROR    ${RESET}" ;;
    *)         echo -e "${DIM}  ○ IDLE     ${RESET}" ;;
  esac
}

get_dot() {
  local status="$1"
  case "$status" in
    *RUNNING*) echo -e "\033[94m●\033[0m" ;;
    *DONE*)    echo -e "\033[92m●\033[0m" ;;
    *WAITING*) echo -e "\033[93m●\033[0m" ;;
    *ERROR*)   echo -e "\033[91m●\033[0m" ;;
    *)         echo -e "\033[90m○\033[0m" ;;
  esac
}

while true; do
  clear
  last=$(get_light)
  timestamp=$(echo "$last" | awk '{print $1}')

  echo ""
  echo -e "  ${BOLD}╔══════════════════════════════╗${RESET}"
  echo -e "  ${BOLD}║     🤖 AGENT LIGHT          ║${RESET}"
  echo -e "  ${BOLD}╚══════════════════════════════╝${RESET}"
  echo ""
  echo -e "  $(get_color_block "$last")"
  echo ""

  if [ -n "$timestamp" ]; then
    echo -e "  Last update: ${BOLD}$timestamp${RESET}"
  else
    echo -e "  Last update: ${DIM}--:--:--${RESET}"
  fi

  echo ""
  echo -e "  ── Recent History ──────────"
  echo ""

  # Show last 8 events as a timeline
  tail -8 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
    ts=$(echo "$line" | awk '{print $1}')
    dot=$(get_dot "$line")
    label=$(echo "$line" | awk '{print $3}')
    echo -e "  $dot $ts  $label"
  done

  # If no history
  if [ ! -s "$LOG_FILE" ]; then
    echo -e "  ${DIM}No events yet...${RESET}"
  fi

  echo ""
  echo -e "  ${DIM}Refreshing every 1s · Ctrl+C to quit${RESET}"

  sleep 1
done
