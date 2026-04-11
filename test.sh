#!/bin/bash
# Integration tests for agent-light
# Usage: ./test.sh [--with-hardware]
# Without flags: simulates full flows without Arduino
# With --with-hardware: also tests serial communication

SCRIPT_DIR="$(dirname "$0")"
PASS=0
FAIL=0
WITH_HW=false
[ "$1" = "--with-hardware" ] && WITH_HW=true

# Colors
RED="\033[91m"
GREEN="\033[92m"
DIM="\033[90m"
RESET="\033[0m"

# Setup temp environment (isolated from real state)
TMP_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/light.sh" "$SCRIPT_DIR/register.sh" "$SCRIPT_DIR/unregister.sh" "$TMP_DIR/"
chmod +x "$TMP_DIR/light.sh" "$TMP_DIR/register.sh" "$TMP_DIR/unregister.sh"
mkfifo "$TMP_DIR/.serial_fifo"
export AGENT_LIGHT_DEBUG=1

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── Helpers ──

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    ${DIM}expected: $expected${RESET}"
    echo -e "    ${DIM}  actual: $actual${RESET}"
    ((FAIL++))
  fi
}

# Fire a hook event, return the FIFO command
fire() {
  local session_id="$1" event="$2" status="${3:-}"
  local json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"$event\"}"
  timeout 2 cat "$TMP_DIR/.serial_fifo" > "$TMP_DIR/.fifo_out" &
  local pid=$!
  if [ -n "$status" ]; then
    echo "$json" | "$TMP_DIR/light.sh" "$status" "$event"
  else
    echo "$json" | "$TMP_DIR/light.sh"
  fi
  sleep 0.3
  kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
  cat "$TMP_DIR/.fifo_out" 2>/dev/null
}

# Fire a hook event and discard FIFO output (for events we don't need to check)
fire_silent() {
  local session_id="$1" event="$2"
  local json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"$event\"}"
  # Drain FIFO in case the event writes to it
  timeout 1 cat "$TMP_DIR/.serial_fifo" > /dev/null &
  local pid=$!
  echo "$json" | "$TMP_DIR/light.sh"
  sleep 0.3
  kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
}

# Register a session to a group
reg() {
  echo "$1" > "$TMP_DIR/.last_session"
  "$TMP_DIR/register.sh" "$2" > /dev/null
}

# Unregister a group, return the FIFO command
unreg() {
  timeout 2 cat "$TMP_DIR/.serial_fifo" > "$TMP_DIR/.fifo_out" &
  local pid=$!
  "$TMP_DIR/unregister.sh" "$1" > /dev/null
  sleep 0.3
  kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
  cat "$TMP_DIR/.fifo_out" 2>/dev/null
}

state_for() {
  grep "^$1:" "$TMP_DIR/.group_state" 2>/dev/null | cut -d: -f2
}

# ============================================================
echo ""
echo "=== Full session lifecycle ==="
echo "  Register → running → waiting → running → done → unregister"
echo ""

SID="lifecycle-session-001"
reg "$SID" 1

OUT=$(fire "$SID" "UserPromptSubmit")
assert "prompt submit → red" "1R" "$OUT"

OUT=$(fire "$SID" "PreToolUse")
assert "tool use → red" "1R" "$OUT"

OUT=$(fire "$SID" "PermissionRequest")
assert "permission request → yellow" "1Y" "$OUT"

OUT=$(fire "$SID" "PostToolUse")
assert "tool approved, running → red" "1R" "$OUT"

OUT=$(fire "$SID" "Stop")
assert "response done → green" "1G" "$OUT"

OUT=$(unreg 1)
assert "unregister → off" "1O" "$OUT"

# Session events should now be skipped
fire_silent "$SID" "PreToolUse"
assert "events skipped after unregister" "" "$(state_for 1)"

# ============================================================
echo ""
echo "=== 4 concurrent sessions ==="
echo "  All 4 groups active, events route to correct group"
echo ""

S1="session-aaaa-1111" S2="session-bbbb-2222" S3="session-cccc-3333" S4="session-dddd-4444"
reg "$S1" 1; reg "$S2" 2; reg "$S3" 3; reg "$S4" 4

OUT=$(fire "$S1" "PreToolUse")
assert "session 1 → group 1 red" "1R" "$OUT"

OUT=$(fire "$S2" "PermissionRequest")
assert "session 2 → group 2 yellow" "2Y" "$OUT"

OUT=$(fire "$S3" "Stop")
assert "session 3 → group 3 green" "3G" "$OUT"

OUT=$(fire "$S4" "PreToolUse")
assert "session 4 → group 4 red" "4R" "$OUT"

# Verify state file has all 4 groups with correct states
assert "state: group 1 = R" "R" "$(state_for 1)"
assert "state: group 2 = Y" "Y" "$(state_for 2)"
assert "state: group 3 = G" "G" "$(state_for 3)"
assert "state: group 4 = R" "R" "$(state_for 4)"

# ============================================================
echo ""
echo "=== Session takeover ==="
echo "  New session replaces old one on same group"
echo ""

OLD="old-session-xxxx" NEW="new-session-yyyy"
reg "$OLD" 2

OUT=$(fire "$OLD" "PreToolUse")
assert "old session active on group 2" "2R" "$OUT"

# New session takes over group 2
reg "$NEW" 2

OUT=$(fire "$NEW" "Stop")
assert "new session works on group 2" "2G" "$OUT"

# Old session should be skipped (no longer mapped)
fire_silent "$OLD" "PreToolUse"
# State should still be green from new session, not red from old
assert "old session ignored, state unchanged" "G" "$(state_for 2)"

# ============================================================
echo ""
echo "=== Session moves between groups ==="
echo "  Same session re-registers from group 1 → group 3"
echo ""

MOVER="moving-session-zzzz"
reg "$MOVER" 1

OUT=$(fire "$MOVER" "PreToolUse")
assert "initially on group 1" "1R" "$OUT"

# Move to group 3
reg "$MOVER" 3

OUT=$(fire "$MOVER" "Stop")
assert "now routes to group 3" "3G" "$OUT"

# Events should NOT go to group 1 anymore
fire_silent "$MOVER" "PreToolUse"
# Group 1 state should still be R from before the move, not updated
assert "group 1 not updated after move" "R" "$(state_for 1)"

# ============================================================
echo ""
echo "=== Rapid event burst ==="
echo "  Simulate fast tool calls (PreToolUse/PostToolUse cycles)"
echo ""

BURST="burst-session-fast"
reg "$BURST" 1

# Drain FIFO in background while firing rapid events
cat "$TMP_DIR/.serial_fifo" > /dev/null &
DRAIN_PID=$!

for i in 1 2 3 4 5; do
  echo "{\"session_id\":\"$BURST\",\"hook_event_name\":\"PreToolUse\"}" | "$TMP_DIR/light.sh"
  echo "{\"session_id\":\"$BURST\",\"hook_event_name\":\"PostToolUse\"}" | "$TMP_DIR/light.sh"
done

kill $DRAIN_PID 2>/dev/null; wait $DRAIN_PID 2>/dev/null || true

# Final event: verify correct output after burst
OUT=$(fire "$BURST" "Stop")
assert "correct state after 5 rapid tool cycles" "1G" "$OUT"
assert "state file consistent after burst" "G" "$(state_for 1)"

# ============================================================
echo ""
echo "=== Unregistered sessions never leak ==="
echo "  Events from unknown sessions produce no FIFO commands"
echo ""

# Clear all state
rm -f "$TMP_DIR/.session_map" "$TMP_DIR/.group_state"

fire_silent "ghost-session-1" "PreToolUse"
fire_silent "ghost-session-2" "Stop"
fire_silent "ghost-session-3" "PermissionRequest"

assert "no state file entries from ghosts" "" "$(cat "$TMP_DIR/.group_state" 2>/dev/null)"

# But last_session should still be tracked (for registration)
assert "last_session still captured" "ghost-session-3" "$(cat "$TMP_DIR/.last_session" 2>/dev/null)"

# ============================================================
echo ""
echo "=== Unregister mid-session ==="
echo "  Unregister while session is running, then re-register"
echo ""

BOUNCE="bounce-session-mid"
reg "$BOUNCE" 4

OUT=$(fire "$BOUNCE" "PreToolUse")
assert "running before unregister" "4R" "$OUT"

OUT=$(unreg 4)
assert "unregister turns off LED" "4O" "$OUT"

fire_silent "$BOUNCE" "PostToolUse"
assert "events skipped while unregistered" "" "$(state_for 4)"

# Re-register same session
reg "$BOUNCE" 4
OUT=$(fire "$BOUNCE" "Stop")
assert "works again after re-register" "4G" "$OUT"

# ============================================================
if $WITH_HW; then
  echo ""
  echo "=== Hardware tests (Arduino) ==="

  SERIAL_FIFO="$SCRIPT_DIR/.serial_fifo"
  if [ ! -p "$SERIAL_FIFO" ]; then
    echo -e "  ${RED}✗${RESET} serial daemon not running (start ./serial_daemon.sh first)"
    ((FAIL++))
  else
    echo ""
    echo "Visual check — each group lights up for 1.5s:"
    for g in 1 2 3 4; do
      for c in R Y G; do
        case $c in R) name="red";; Y) name="yellow";; G) name="green";; esac
        echo -n "  Group $g $name... "
        echo "${g}${c}" > "$SERIAL_FIFO"
        sleep 1.5
        echo "${g}O" > "$SERIAL_FIFO"
        echo "done"
      done
    done
    echo ""
    echo "  If all 12 LEDs lit up correctly, hardware is good."
    echo "  Otherwise, check wiring for the group/color that failed."
  fi
fi

# ============================================================
echo ""
echo "========================"
echo -e "  ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}"
echo "========================"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
