#!/bin/bash
# Remove a session from an LED group and turn off its LEDs.
# Usage: ./unregister.sh <1-4>

SCRIPT_DIR="$(dirname "$0")"
MAP_FILE="$SCRIPT_DIR/.session_map"
FIFO="$SCRIPT_DIR/.serial_fifo"
STATE_FILE="$SCRIPT_DIR/.group_state"

GROUP="$1"

if [[ ! "$GROUP" =~ ^[1-4]$ ]]; then
  echo "Usage: ./unregister.sh <1-4>"
  echo "Removes the session assigned to LED group N"
  exit 1
fi

if [ ! -f "$MAP_FILE" ]; then
  echo "No sessions registered."
  exit 1
fi

SESSION_ID=$(grep " $GROUP$" "$MAP_FILE" | awk '{print $1}')
if [ -z "$SESSION_ID" ]; then
  echo "No session registered to group $GROUP."
  exit 1
fi

# Remove mapping
grep -v " $GROUP$" "$MAP_FILE" > "$MAP_FILE.tmp"
mv "$MAP_FILE.tmp" "$MAP_FILE"

# Turn off LEDs
if [ -p "$FIFO" ]; then
  echo "${GROUP}O" > "$FIFO"
fi

# Clear state file entry
if [ -f "$STATE_FILE" ]; then
  grep -v "^$GROUP:" "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
fi

echo "Unregistered session ${SESSION_ID:0:8}... from LED group $GROUP"
