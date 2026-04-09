#!/bin/bash
# Simulates a real Claude Code session calling hooks in order.
# Verifies the FIFO commands match expected output.
# Usage: ./test_simulation.sh

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

TEST_FIFO="$TMP_DIR/.serial_fifo"
mkfifo "$TEST_FIFO"

SESSION_A="a1b2c3d4-1111-2222-3333-444455556666"
SESSION_B="f7e8d9c0-aaaa-bbbb-cccc-ddddeeeeffff"

# Register sessions
echo "$SESSION_A" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 1 > /dev/null
echo "$SESSION_B" > "$TMP_DIR/.last_session"
"$TMP_DIR/register.sh" 2 > /dev/null

# Helper: send hook event and capture FIFO output
fire_hook() {
  local session_id="$1" event="$2" tool_name="${3:-}"
  local json

  case "$event" in
    UserPromptSubmit)
      json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hello\"}"
      ;;
    PreToolUse)
      json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"$tool_name\",\"tool_input\":{}}"
      ;;
    PostToolUse)
      json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"$tool_name\",\"tool_input\":{},\"tool_output\":\"ok\"}"
      ;;
    PermissionRequest)
      json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"$tool_name\"}"
      ;;
    Stop)
      json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"Stop\",\"stop_reason\":\"end_turn\"}"
      ;;
    StopFailure)
      json="{\"session_id\":\"$session_id\",\"hook_event_name\":\"StopFailure\",\"error\":\"api_error\"}"
      ;;
  esac

  timeout 2 cat "$TEST_FIFO" > "$TMP_DIR/.fifo_out" &
  local pid=$!
  echo "$json" | "$TMP_DIR/light.sh"
  sleep 0.3
  kill $pid 2>/dev/null
  wait $pid 2>/dev/null
  cat "$TMP_DIR/.fifo_out" 2>/dev/null
}

assert_cmd() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}✓${RESET} $desc → ${BOLD}$actual${RESET}"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    ${DIM}expected: $expected, got: $actual${RESET}"
    ((FAIL++))
  fi
}

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 1: Simple question (no tools) ===${RESET}"
echo -e "${DIM}User asks a question, Claude responds with text only${RESET}"
echo ""

OUT=$(fire_hook "$SESSION_A" "UserPromptSubmit")
assert_cmd "User sends message" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "Stop")
assert_cmd "Claude finishes responding" "1G" "$OUT"

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 2: Read a file ===${RESET}"
echo -e "${DIM}User asks to read a file, auto-approved${RESET}"
echo ""

OUT=$(fire_hook "$SESSION_A" "UserPromptSubmit")
assert_cmd "User sends message" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Read")
assert_cmd "PreToolUse (Read)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PostToolUse" "Read")
assert_cmd "PostToolUse (Read)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "Stop")
assert_cmd "Claude finishes" "1G" "$OUT"

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 3: Bash command needs permission ===${RESET}"
echo -e "${DIM}User asks to run a command, permission required${RESET}"
echo ""

OUT=$(fire_hook "$SESSION_A" "UserPromptSubmit")
assert_cmd "User sends message" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Bash")
assert_cmd "PreToolUse (Bash)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PermissionRequest" "Bash")
assert_cmd "Permission prompt shown" "1Y" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PostToolUse" "Bash")
assert_cmd "User approved, Bash ran" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "Stop")
assert_cmd "Claude finishes" "1G" "$OUT"

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 4: Multiple tools ===${RESET}"
echo -e "${DIM}Claude reads a file, edits it, then runs tests${RESET}"
echo ""

OUT=$(fire_hook "$SESSION_A" "UserPromptSubmit")
assert_cmd "User sends message" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Read")
assert_cmd "PreToolUse (Read)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PostToolUse" "Read")
assert_cmd "PostToolUse (Read)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Edit")
assert_cmd "PreToolUse (Edit)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PostToolUse" "Edit")
assert_cmd "PostToolUse (Edit)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Bash")
assert_cmd "PreToolUse (Bash)" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PermissionRequest" "Bash")
assert_cmd "Permission for Bash" "1Y" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PostToolUse" "Bash")
assert_cmd "Bash completed" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "Stop")
assert_cmd "Claude finishes" "1G" "$OUT"

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 5: Two sessions concurrently ===${RESET}"
echo -e "${DIM}Session A (Group 1) and Session B (Group 2) interleaved${RESET}"
echo ""

OUT=$(fire_hook "$SESSION_A" "UserPromptSubmit")
assert_cmd "A: User sends message" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_B" "UserPromptSubmit")
assert_cmd "B: User sends message" "2R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Read")
assert_cmd "A: PreToolUse" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_B" "PreToolUse" "Bash")
assert_cmd "B: PreToolUse" "2R" "$OUT"

OUT=$(fire_hook "$SESSION_B" "PermissionRequest" "Bash")
assert_cmd "B: Permission prompt" "2Y" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PostToolUse" "Read")
assert_cmd "A: PostToolUse" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "Stop")
assert_cmd "A: Done" "1G" "$OUT"

OUT=$(fire_hook "$SESSION_B" "PostToolUse" "Bash")
assert_cmd "B: Bash ran" "2R" "$OUT"

OUT=$(fire_hook "$SESSION_B" "Stop")
assert_cmd "B: Done" "2G" "$OUT"

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 6: Unregistered session ===${RESET}"
echo -e "${DIM}A third session fires hooks but isn't registered${RESET}"
echo ""

UNREGISTERED="99999999-0000-0000-0000-000000000000"

OUT=$(fire_hook "$UNREGISTERED" "UserPromptSubmit")
assert_cmd "Unregistered → no command" "" "$OUT"

OUT=$(fire_hook "$UNREGISTERED" "PreToolUse" "Read")
assert_cmd "Unregistered tool → no command" "" "$OUT"

OUT=$(fire_hook "$UNREGISTERED" "Stop")
assert_cmd "Unregistered stop → no command" "" "$OUT"

# ============================================================
echo ""
echo -e "${BOLD}=== Scenario 7: API error ===${RESET}"
echo -e "${DIM}Claude hits an API error mid-task${RESET}"
echo ""

OUT=$(fire_hook "$SESSION_A" "UserPromptSubmit")
assert_cmd "User sends message" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "PreToolUse" "Read")
assert_cmd "PreToolUse" "1R" "$OUT"

OUT=$(fire_hook "$SESSION_A" "StopFailure")
assert_cmd "API error → waiting" "1Y" "$OUT"

# ============================================================
# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "========================"
echo -e "  ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}"
echo "========================"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
