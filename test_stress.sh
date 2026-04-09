#!/bin/bash
# Stress tests for agent-light
# Focuses on race conditions, rapid-fire commands, and concurrent sessions
# Usage: ./test_stress.sh

SCRIPT_DIR="$(dirname "$0")"
PASS=0
FAIL=0

RED="\033[91m"
GREEN="\033[92m"
DIM="\033[90m"
BOLD="\033[1m"
RESET="\033[0m"

# Setup temp environment
TMP_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/light.sh" "$TMP_DIR/"
cp "$SCRIPT_DIR/register.sh" "$TMP_DIR/"
chmod +x "$TMP_DIR/light.sh" "$TMP_DIR/register.sh"
export AGENT_LIGHT_DEBUG=1

SESSION_A="aaaa-1111"
SESSION_B="bbbb-2222"

# Register sessions
echo "$SESSION_A" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 1 > /dev/null
echo "$SESSION_B" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 2 > /dev/null

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    ${DIM}expected: '$expected'${RESET}"
    echo -e "    ${DIM}  actual: '$actual'${RESET}"
    ((FAIL++))
  fi
}

# ============================================================
echo ""
echo -e "${BOLD}=== Test 1: FIFO drops commands when daemon reopens fd ===${RESET}"
echo -e "${DIM}The daemon does 'read cmd < FIFO' which opens/closes the fd each iteration."
echo -e "If two writes happen before the daemon reopens, the second may be lost.${RESET}"
echo ""

TEST_FIFO="$TMP_DIR/.test_fifo"
mkfifo "$TEST_FIFO"

# Simulate daemon with persistent fd (the fix)
RECEIVED="$TMP_DIR/received.txt"
> "$RECEIVED"
(
  exec 4<>"$TEST_FIFO"
  for i in $(seq 1 5); do
    if read -r cmd <&4; then
      echo "$cmd" >> "$RECEIVED"
    fi
  done
) &
DAEMON_PID=$!

# Rapid fire 5 commands (simulating concurrent hooks)
sleep 0.2
for i in 1 2 3 4 5; do
  echo "CMD$i" > "$TEST_FIFO" &
done
wait

sleep 1
kill $DAEMON_PID 2>/dev/null
wait $DAEMON_PID 2>/dev/null

COUNT=$(wc -l < "$RECEIVED" | tr -d ' ')
echo -e "  Sent 5 commands, daemon received: $COUNT"
assert "all 5 commands received" "5" "$COUNT"

if [ "$COUNT" -ne "5" ]; then
  echo -e "  ${RED}⚠ FIFO drops commands! This explains the orange light bug.${RESET}"
  echo -e "  ${DIM}Received:${RESET}"
  cat "$RECEIVED" | while read line; do echo "    $line"; done
fi

# ============================================================
echo ""
echo -e "${BOLD}=== Test 2: Same-second PermissionRequest + PreToolUse ===${RESET}"
echo -e "${DIM}Reproducing the exact scenario from the real log.${RESET}"
echo ""

TEST_FIFO2="$TMP_DIR/.serial_fifo"
mkfifo "$TEST_FIFO2"

RECEIVED2="$TMP_DIR/received2.txt"
> "$RECEIVED2"

# Simulate daemon reading
(
  exec 4<>"$TEST_FIFO2"
  for i in $(seq 1 3); do
    if read -r cmd <&4; then
      echo "$cmd" >> "$RECEIVED2"
    fi
  done
) &
DAEMON_PID2=$!

sleep 0.2

# Fire PermissionRequest and PreToolUse simultaneously (like real hooks do)
echo '{"session_id":"aaaa-1111","hook_event_name":"PermissionRequest","tool_name":"Bash"}' | "$TMP_DIR/light.sh" &
echo '{"session_id":"aaaa-1111","hook_event_name":"PreToolUse","tool_name":"Bash"}' | "$TMP_DIR/light.sh" &
wait %2 %3 2>/dev/null

# Then PostToolUse slightly later
sleep 0.5
echo '{"session_id":"aaaa-1111","hook_event_name":"PostToolUse","tool_name":"Bash"}' | "$TMP_DIR/light.sh" &
wait

sleep 1
kill $DAEMON_PID2 2>/dev/null
wait $DAEMON_PID2 2>/dev/null

echo "  Commands received by daemon:"
cat "$RECEIVED2" | while read line; do echo "    $line"; done
echo ""

COUNT2=$(wc -l < "$RECEIVED2" | tr -d ' ')
assert "all 3 commands received" "3" "$COUNT2"

LAST_CMD=$(tail -1 "$RECEIVED2")
assert "last command is 1R (red)" "1R" "$LAST_CMD"

# Check if 1Y was received (would cause yellow to flash)
if grep -q "1Y" "$RECEIVED2"; then
  echo -e "  ${DIM}Note: 1Y (yellow) was received — if 1R was lost, yellow stays on = orange${RESET}"
fi

# ============================================================
echo ""
echo -e "${BOLD}=== Test 3: Rapid fire 20 commands to same group ===${RESET}"
echo -e "${DIM}Simulating a busy session with many tool calls.${RESET}"
echo ""

TEST_FIFO3="$TMP_DIR/.fifo3"
mkfifo "$TEST_FIFO3"

RECEIVED3="$TMP_DIR/received3.txt"
> "$RECEIVED3"

(
  exec 4<>"$TEST_FIFO3"
  for i in $(seq 1 20); do
    if read -r cmd <&4; then
      echo "$cmd" >> "$RECEIVED3"
    fi
  done
) &
DAEMON_PID3=$!

sleep 0.2

# Fire 20 commands rapidly
for i in $(seq 1 20); do
  echo "1R" > "$TEST_FIFO3" &
done
wait

sleep 2
kill $DAEMON_PID3 2>/dev/null
wait $DAEMON_PID3 2>/dev/null

COUNT3=$(wc -l < "$RECEIVED3" | tr -d ' ')
echo -e "  Sent 20 commands, daemon received: $COUNT3"
assert "all 20 commands received" "20" "$COUNT3"

if [ "$COUNT3" -ne "20" ]; then
  echo -e "  ${RED}⚠ Lost $((20 - COUNT3)) commands under rapid fire!${RESET}"
fi

# ============================================================
echo ""
echo -e "${BOLD}=== Test 4: Two sessions fire hooks simultaneously ===${RESET}"
echo -e "${DIM}Session A and B both trigger PreToolUse at the same time.${RESET}"
echo ""

TEST_FIFO4="$TMP_DIR/.fifo4"
mkfifo "$TEST_FIFO4"
rm -f "$TMP_DIR/.serial_fifo"  # remove old one
ln -s "$TEST_FIFO4" "$TMP_DIR/.serial_fifo"

RECEIVED4="$TMP_DIR/received4.txt"
> "$RECEIVED4"

(
  exec 4<>"$TEST_FIFO4"
  for i in $(seq 1 4); do
    if read -r cmd <&4; then
      echo "$cmd" >> "$RECEIVED4"
    fi
  done
) &
DAEMON_PID4=$!

sleep 0.2

# Both sessions fire at the same time
echo '{"session_id":"aaaa-1111","hook_event_name":"PreToolUse"}' | "$TMP_DIR/light.sh" &
echo '{"session_id":"bbbb-2222","hook_event_name":"PreToolUse"}' | "$TMP_DIR/light.sh" &
wait %2 %3 2>/dev/null

sleep 0.3

echo '{"session_id":"aaaa-1111","hook_event_name":"Stop"}' | "$TMP_DIR/light.sh" &
echo '{"session_id":"bbbb-2222","hook_event_name":"Stop"}' | "$TMP_DIR/light.sh" &
wait %2 %3 2>/dev/null

sleep 1
kill $DAEMON_PID4 2>/dev/null
wait $DAEMON_PID4 2>/dev/null

echo "  Commands received:"
cat "$RECEIVED4" | while read line; do echo "    $line"; done
echo ""

COUNT4=$(wc -l < "$RECEIVED4" | tr -d ' ')
assert "all 4 commands received" "4" "$COUNT4"

# Check both groups got commands
G1_COUNT=$(grep -c "^1" "$RECEIVED4" || true)
G2_COUNT=$(grep -c "^2" "$RECEIVED4" || true)
assert "group 1 got 2 commands" "2" "$G1_COUNT"
assert "group 2 got 2 commands" "2" "$G2_COUNT"

# ============================================================
echo ""
echo -e "${BOLD}=== Test 5: Command ordering ===${RESET}"
echo -e "${DIM}Send Y then R to same group — final state must be R, not Y.${RESET}"
echo ""

TEST_FIFO5="$TMP_DIR/.fifo5"
mkfifo "$TEST_FIFO5"

RECEIVED5="$TMP_DIR/received5.txt"
> "$RECEIVED5"

(
  exec 4<>"$TEST_FIFO5"
  for i in $(seq 1 2); do
    if read -r cmd <&4; then
      echo "$cmd" >> "$RECEIVED5"
    fi
  done
) &
DAEMON_PID5=$!

sleep 0.2

# Send yellow, then immediately red
echo "1Y" > "$TEST_FIFO5"
echo "1R" > "$TEST_FIFO5"

sleep 1
kill $DAEMON_PID5 2>/dev/null
wait $DAEMON_PID5 2>/dev/null

echo "  Commands received:"
cat "$RECEIVED5" | while read line; do echo "    $line"; done
echo ""

COUNT5=$(wc -l < "$RECEIVED5" | tr -d ' ')
assert "both commands received" "2" "$COUNT5"

LAST5=$(tail -1 "$RECEIVED5")
assert "last command is 1R" "1R" "$LAST5"

# ============================================================
# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "========================"
echo -e "  ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}"
echo "========================"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
