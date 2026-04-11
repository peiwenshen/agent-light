#!/bin/bash
# agent-light: multi-session status light for Claude Code
# Usage: ./light.sh [status] [event]
# Reads session_id from hook stdin JSON to route to correct LED group.
# Set AGENT_LIGHT_DEBUG=1 to enable logging to light.log

SCRIPT_DIR="$(dirname "$0")"
MAP_FILE="$SCRIPT_DIR/.session_map"
LAST_SESSION_FILE="$SCRIPT_DIR/.last_session"
FIFO="$SCRIPT_DIR/.serial_fifo"

log() { [ "${AGENT_LIGHT_DEBUG:-}" = "1" ] && echo "$(date '+%m-%d %H:%M:%S') $*" >> "$SCRIPT_DIR/light.log"; }

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

# Look up group (unregistered sessions are ignored)
GROUP=""
if [ -n "$SESSION_ID" ] && [ -f "$MAP_FILE" ]; then
  GROUP=$(grep "^$SESSION_ID " "$MAP_FILE" | awk '{print $2}')
fi

# Skip unregistered sessions
if [ -z "$GROUP" ]; then
  log "[--] ⚫ SKIP ($STATUS) [$EVENT] sid=${SESSION_ID:0:8}"
  exit 0
fi

# Map status to command char
case "$STATUS" in
  running) ICON="🔴"; LABEL="RUNNING"; CMD="R" ;;
  done)    ICON="🟢"; LABEL="DONE";    CMD="G" ;;
  waiting) ICON="🟡"; LABEL="WAITING"; CMD="Y" ;;
  error)   ICON="🔴"; LABEL="ERROR";   CMD="R" ;;
  *)       ICON="⚫"; LABEL="OFF";     CMD="O" ;;
esac

log "[G$GROUP] $ICON $LABEL ($STATUS) [$EVENT] sid=${SESSION_ID:0:8}"

# Update state file (always, for software simulation)
STATE_FILE="$SCRIPT_DIR/.group_state"
touch "$STATE_FILE"
# Atomic update: replace the line for this group
NEW_LINE="$GROUP:$CMD:$STATUS:$EVENT:$(date '+%m-%d %H:%M:%S'):${SESSION_ID:0:8}"
if grep -q "^$GROUP:" "$STATE_FILE" 2>/dev/null; then
  grep -v "^$GROUP:" "$STATE_FILE" > "$STATE_FILE.tmp"
  echo "$NEW_LINE" >> "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
else
  echo "$NEW_LINE" >> "$STATE_FILE"
fi

# Send to Arduino via FIFO: group number + command
if [ -p "$FIFO" ]; then
  echo "${GROUP}${CMD}" > "$FIFO"
fi
