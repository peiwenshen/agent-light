#!/bin/bash
# Assign the most recently active Claude Code session to an LED group.
# Usage: ./register.sh <1-4>

SCRIPT_DIR="$(dirname "$0")"
MAP_FILE="$SCRIPT_DIR/.session_map"
LAST_SESSION_FILE="$SCRIPT_DIR/.last_session"

GROUP="$1"

if [[ ! "$GROUP" =~ ^[1-4]$ ]]; then
  echo "Usage: ./register.sh <1-4>"
  echo "Assigns the last active session to LED group N"
  exit 1
fi

if [ ! -f "$LAST_SESSION_FILE" ]; then
  echo "Error: No session seen yet. Send a message in Claude Code first."
  exit 1
fi

SESSION_ID=$(cat "$LAST_SESSION_FILE")
if [ -z "$SESSION_ID" ]; then
  echo "Error: Empty session ID"
  exit 1
fi

# Remove existing mapping for this session or this group
if [ -f "$MAP_FILE" ]; then
  grep -v "^$SESSION_ID " "$MAP_FILE" | grep -v " $GROUP$" > "$MAP_FILE.tmp"
  mv "$MAP_FILE.tmp" "$MAP_FILE"
fi

echo "$SESSION_ID $GROUP" >> "$MAP_FILE"
echo "Registered session ${SESSION_ID:0:8}... to LED group $GROUP"
