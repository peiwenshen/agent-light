#!/bin/bash
# Test suite for agent-light
# Usage: ./test.sh [--with-hardware]
# Without flags: tests software logic only (no Arduino needed)
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

# Setup temp environment
TMP_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/light.sh" "$TMP_DIR/"
cp "$SCRIPT_DIR/register.sh" "$TMP_DIR/"
chmod +x "$TMP_DIR/light.sh" "$TMP_DIR/register.sh"
export AGENT_LIGHT_DEBUG=1

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

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    ${DIM}expected to contain: $expected${RESET}"
    echo -e "    ${DIM}  actual: $actual${RESET}"
    ((FAIL++))
  fi
}

assert_file_contains() {
  local desc="$1" expected="$2" file="$3"
  if grep -q "$expected" "$file" 2>/dev/null; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    ${DIM}expected '$expected' in $file${RESET}"
    ((FAIL++))
  fi
}

# ============================================================
echo ""
echo "=== register.sh ==="

echo ""
echo "-- invalid input --"

OUT=$("$TMP_DIR/register.sh" 2>&1)
assert "no args → exit 1" "1" "$?"

OUT=$("$TMP_DIR/register.sh" 0 2>&1)
assert "group 0 → exit 1" "1" "$?"

OUT=$("$TMP_DIR/register.sh" 5 2>&1)
assert "group 5 → exit 1" "1" "$?"

OUT=$("$TMP_DIR/register.sh" abc 2>&1)
assert "group abc → exit 1" "1" "$?"

echo ""
echo "-- no session yet --"

rm -f "$TMP_DIR/.last_session"
OUT=$("$TMP_DIR/register.sh" 1 2>&1)
assert "no .last_session → exit 1" "1" "$?"
assert_contains "error message" "No session seen" "$OUT"

echo ""
echo "-- register session --"

echo "test-session-aaa" > "$TMP_DIR/.last_session"
OUT=$("$TMP_DIR/register.sh" 1 2>&1)
assert "register to group 1 → exit 0" "0" "$?"
assert_contains "shows session prefix" "test-ses" "$OUT"
assert_file_contains ".session_map has entry" "test-session-aaa 1" "$TMP_DIR/.session_map"

echo ""
echo "-- re-register same session to different group --"

OUT=$("$TMP_DIR/register.sh" 3 2>&1)
assert "re-register to group 3 → exit 0" "0" "$?"
# Should not have group 1 mapping anymore
if grep -q "test-session-aaa 1" "$TMP_DIR/.session_map" 2>/dev/null; then
  echo -e "  ${RED}✗${RESET} old group 1 mapping removed"
  ((FAIL++))
else
  echo -e "  ${GREEN}✓${RESET} old group 1 mapping removed"
  ((PASS++))
fi
assert_file_contains "new group 3 mapping exists" "test-session-aaa 3" "$TMP_DIR/.session_map"

echo ""
echo "-- register different session replaces group --"

echo "test-session-bbb" > "$TMP_DIR/.last_session"
OUT=$("$TMP_DIR/register.sh" 3 2>&1)
assert "new session to group 3 → exit 0" "0" "$?"
if grep -q "test-session-aaa 3" "$TMP_DIR/.session_map" 2>/dev/null; then
  echo -e "  ${RED}✗${RESET} old session removed from group 3"
  ((FAIL++))
else
  echo -e "  ${GREEN}✓${RESET} old session removed from group 3"
  ((PASS++))
fi
assert_file_contains "new session in group 3" "test-session-bbb 3" "$TMP_DIR/.session_map"

# ============================================================
echo ""
echo "=== light.sh ==="

# Create a FIFO to capture output instead of real serial
TEST_FIFO="$TMP_DIR/.serial_fifo"
mkfifo "$TEST_FIFO"

# Helper: run light.sh with stdin JSON and capture FIFO output
run_light() {
  local json="$1" args="${2:-}"
  local fifo_out=""
  # Read from FIFO in background with timeout
  timeout 2 cat "$TEST_FIFO" > "$TMP_DIR/.fifo_out" &
  local reader_pid=$!
  echo "$json" | $TMP_DIR/light.sh $args
  sleep 0.3
  kill $reader_pid 2>/dev/null
  wait $reader_pid 2>/dev/null
  cat "$TMP_DIR/.fifo_out" 2>/dev/null
}

echo ""
echo "-- unregistered session skipped --"

rm -f "$TMP_DIR/.session_map"
run_light '{"session_id":"unknown-session","hook_event_name":"PreToolUse"}' > /dev/null 2>&1
FIFO_OUT=$(cat "$TMP_DIR/.fifo_out" 2>/dev/null)
assert "unregistered session → no FIFO output" "" "$FIFO_OUT"
assert_file_contains "log shows SKIP" "SKIP" "$TMP_DIR/light.log"

echo ""
echo "-- session_id saved to .last_session --"

run_light '{"session_id":"save-me-123","hook_event_name":"Stop"}' > /dev/null 2>&1
SAVED=$(cat "$TMP_DIR/.last_session" 2>/dev/null)
assert "session_id saved" "save-me-123" "$SAVED"

echo ""
echo "-- registered session sends correct commands --"

# Register session
echo "sess-red-test" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 2 > /dev/null

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"PreToolUse"}')
assert "PreToolUse → 2R" "2R" "$FIFO_OUT"

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"Stop"}')
assert "Stop → 2G" "2G" "$FIFO_OUT"

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"PermissionRequest"}')
assert "PermissionRequest → 2Y" "2Y" "$FIFO_OUT"

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"UserPromptSubmit"}')
assert "UserPromptSubmit → 2R" "2R" "$FIFO_OUT"

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"PostToolUse"}')
assert "PostToolUse → 2R" "2R" "$FIFO_OUT"

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"StopFailure"}')
assert "StopFailure → 2Y" "2Y" "$FIFO_OUT"

echo ""
echo "-- CLI args override stdin event --"

FIFO_OUT=$(run_light '{"session_id":"sess-red-test","hook_event_name":"Stop"}' "running PreToolUse")
assert "CLI override → 2R (not 2G)" "2R" "$FIFO_OUT"

echo ""
echo "-- different groups --"

echo "sess-group1" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 1 > /dev/null
echo "sess-group4" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 4 > /dev/null

FIFO_OUT=$(run_light '{"session_id":"sess-group1","hook_event_name":"PreToolUse"}')
assert "group 1 session → 1R" "1R" "$FIFO_OUT"

FIFO_OUT=$(run_light '{"session_id":"sess-group4","hook_event_name":"Stop"}')
assert "group 4 session → 4G" "4G" "$FIFO_OUT"

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
# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "========================"
echo -e "  ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}"
echo "========================"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
