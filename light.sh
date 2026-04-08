#!/bin/bash
# agent-light: simulate status light in terminal
# Usage: ./light.sh [status]
# Statuses: running, done, waiting, error, off
# When called without args, reads hook event JSON from stdin to auto-detect status.

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="$SCRIPT_DIR/light.log"
TIMESTAMP=$(date '+%H:%M:%S')

STATUS="${1:-}"
EVENT="${2:-direct}"

if [ -z "$STATUS" ]; then
  # Read hook event from stdin JSON
  INPUT=$(cat)
  EVENT=$(echo "$INPUT" | grep -o '"hook_event_name":"[^"]*"' | head -1 | cut -d'"' -f4)
  case "$EVENT" in
    PreToolUse)    STATUS="running" ;;
    Stop)          STATUS="done"    ;;
    Notification)  STATUS="waiting" ;;
    *)             STATUS="off"     ;;
  esac
fi

case "$STATUS" in
  running) ICON="🔵"; LABEL="RUNNING"; CMD="R" ;;
  done)    ICON="🟢"; LABEL="DONE";    CMD="G" ;;
  waiting) ICON="🟡"; LABEL="WAITING"; CMD="Y" ;;
  error)   ICON="🔴"; LABEL="ERROR";   CMD="R" ;;
  *)       ICON="⚫"; LABEL="OFF";     CMD="O" ;;
esac

# Log to file (hooks run in background, can't see stdout)
echo "$TIMESTAMP $ICON $LABEL ($STATUS) [$EVENT]" >> "$LOG_FILE"

# Send to Arduino via FIFO (serial_daemon.sh keeps port open)
FIFO="$SCRIPT_DIR/.serial_fifo"
if [ -p "$FIFO" ]; then
  echo "$CMD" > "$FIFO"
fi
