#!/bin/bash
# Show current LED group registrations and state.
# Usage: ./groups.sh

SCRIPT_DIR="$(dirname "$0")"
MAP_FILE="$SCRIPT_DIR/.session_map"
STATE_FILE="$SCRIPT_DIR/.group_state"

echo ""
echo "  LED Group Status"
echo "  ════════════════════════════════════════════"

for g in 1 2 3 4; do
  session=$(grep " $g$" "$MAP_FILE" 2>/dev/null | awk '{print $1}')
  state_line=$(grep "^$g:" "$STATE_FILE" 2>/dev/null)
  cmd=$(echo "$state_line" | cut -d: -f2)
  ts=$(echo "$state_line" | cut -d: -f5-6)

  case "$cmd" in
    R) color="🔴 running" ;;
    Y) color="🟡 waiting" ;;
    G) color="🟢 done" ;;
    *) color="⚫ off" ;;
  esac

  if [ -n "$session" ]; then
    echo "  Group $g: ${session:0:8}...  $color  ($ts)"
  else
    echo "  Group $g: (empty)"
  fi
done

echo ""
