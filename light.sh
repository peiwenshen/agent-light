#!/bin/bash
# agent-light: multi-session status light for Claude Code
# Usage: ./light.sh [status] [event]
# Reads session_id from hook stdin JSON to route to correct LED group.

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="$SCRIPT_DIR/light.log"
MAP_FILE="$SCRIPT_DIR/.session_map"
LAST_SESSION_FILE="$SCRIPT_DIR/.last_session"
FIFO="$SCRIPT_DIR/.serial_fifo"
TIMESTAMP=$(date '+%H:%M:%S')

STATUS="${1:-}"
EVENT="${2:-direct}"
SESSION_ID=""

# Read hook JSON from stdin (non-blocking)
if [ ! -t 0 ]; then
  INPUT=$(cat)
  SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$STATUS" ]; then
    EVENT=$(echo "$INPUT" | grep -o '"hook_event_name":"[^"]*"' | head -1 | cut -d'"' -f4)
    case "$EVENT" in
      UserPromptSubmit)  STATUS="running" ;;
      PreToolUse)        STATUS="running" ;;
      PostToolUse)       STATUS="running" ;;
      Stop)              STATUS="done"    ;;
      Notification)      STATUS="waiting" ;;
      PermissionRequest) STATUS="waiting" ;;
      StopFailure)       STATUS="waiting" ;;
      *)                 STATUS="off"     ;;
    esac
  fi
fi

# Save last seen session for registration
if [ -n "$SESSION_ID" ]; then
  echo "$SESSION_ID" > "$LAST_SESSION_FILE"
fi

# Look up group (default to 1)
GROUP=1
if [ -n "$SESSION_ID" ] && [ -f "$MAP_FILE" ]; then
  MAPPED=$(grep "^$SESSION_ID " "$MAP_FILE" | awk '{print $2}')
  if [ -n "$MAPPED" ]; then
    GROUP="$MAPPED"
  fi
fi

# Map status to command char
case "$STATUS" in
  running) ICON="🔴"; LABEL="RUNNING"; CMD="R" ;;
  done)    ICON="🟢"; LABEL="DONE";    CMD="G" ;;
  waiting) ICON="🟡"; LABEL="WAITING"; CMD="Y" ;;
  error)   ICON="🔴"; LABEL="ERROR";   CMD="R" ;;
  *)       ICON="⚫"; LABEL="OFF";     CMD="O" ;;
esac

# Log with group and session info
echo "$TIMESTAMP [G$GROUP] $ICON $LABEL ($STATUS) [$EVENT] sid=${SESSION_ID:0:8}" >> "$LOG_FILE"

# Send to Arduino via FIFO: group number + command
if [ -p "$FIFO" ]; then
  echo "${GROUP}${CMD}" > "$FIFO"
fi
