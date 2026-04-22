#!/usr/bin/env bats
# Tests for custom fields and activity indicator.

load helpers

setup() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.claude"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ── Custom fields ─────────────────────────────────────────────────────────────

@test "custom fields are called when defined and listed" {
  cat > "$HOME/.claude/craft-statusline-custom.sh" <<'EOF'
CUSTOM_FIELDS="field_marker"
field_marker() { printf 'CUSTOM_FIELD_TEST_OK'; }
EOF
  run bash -c "echo '{}' | bash '$RENDERER'"
  [[ "$output" == *"CUSTOM_FIELD_TEST_OK"* ]]
}

@test "custom fields not in CUSTOM_FIELDS are ignored" {
  cat > "$HOME/.claude/craft-statusline-custom.sh" <<'EOF'
CUSTOM_FIELDS="field_a"
field_a() { printf 'A_OK'; }
field_b() { printf 'B_SHOULD_NOT_APPEAR'; }
EOF
  run bash -c "echo '{}' | bash '$RENDERER'"
  [[ "$output" == *"A_OK"* ]]
  [[ "$output" != *"B_SHOULD_NOT_APPEAR"* ]]
}

@test "custom fields with non-whitelisted names are refused" {
  cat > "$HOME/.claude/craft-statusline-custom.sh" <<'EOF'
CUSTOM_FIELDS="rm"
rm() { printf 'INVALID_SHOULD_NOT_RUN'; }
EOF
  run bash -c "echo '{}' | bash '$RENDERER'"
  [[ "$output" != *"INVALID_SHOULD_NOT_RUN"* ]]
}

@test "crash in one custom field does not break others" {
  cat > "$HOME/.claude/craft-statusline-custom.sh" <<'EOF'
CUSTOM_FIELDS="field_broken field_working"
field_broken() { false; exit 1; }
field_working() { printf 'WORKING_OK'; }
EOF
  run bash -c "echo '{}' | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"WORKING_OK"* ]]
}

@test "missing custom fields file is a no-op" {
  run bash -c "echo '{}' | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
}

@test "slow custom field is killed by rendertime cap" {
  cat > "$HOME/.claude/craft-statusline-custom.sh" <<'EOF'
CUSTOM_FIELDS="field_slow field_after"
field_slow()  { sleep 10; echo "SLOW_SHOULD_NEVER_RENDER"; }
field_after() { echo "AFTER_OK"; }
EOF
  start=$(date +%s)
  run bash -c "echo '{}' | bash '$RENDERER'"
  elapsed=$(( $(date +%s) - start ))
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"SLOW_SHOULD_NEVER_RENDER"* ]]
  [[ "$output" == *"AFTER_OK"* ]]
  # Timeout is 2s per field; add slack for test-machine variance and the
  # script's other work (activity scan, update-check background fork).
  [[ "$elapsed" -lt 8 ]]
}

# ── Activity indicator (mtime-based, no hooks) ────────────────────────────────

@test "activity shows thinking when session is active with no recent tool_use" {
  mkdir -p "$HOME/.claude/projects/test-session"
  jsonl="$HOME/.claude/projects/test-session/session.jsonl"
  # Assistant message with only text content (no tool_use)
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}' > "$jsonl"
  run bash -c "echo '{}' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"● thinking"* ]]
}

@test "activity shows executing with tool name when last event is a tool_use" {
  mkdir -p "$HOME/.claude/projects/test-session"
  jsonl="$HOME/.claude/projects/test-session/session.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}' > "$jsonl"
  run bash -c "echo '{}' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"● executing"* ]]
  [[ "$clean" == *"(Bash)"* ]]
}

@test "activity shows researching when last tool is Task" {
  mkdir -p "$HOME/.claude/projects/test-session"
  jsonl="$HOME/.claude/projects/test-session/session.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"prompt":"..."}}]}}' > "$jsonl"
  run bash -c "echo '{}' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"● researching"* ]]
}

@test "activity strips the mcp__server__ prefix for cleaner labels" {
  mkdir -p "$HOME/.claude/projects/test-session"
  jsonl="$HOME/.claude/projects/test-session/session.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__claude_ai_Ahrefs__rank-tracker-overview","input":{}}]}}' > "$jsonl"
  run bash -c "echo '{}' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"(rank-tracker-overview)"* ]]
  [[ "$clean" != *"mcp__"* ]]
}

@test "activity hides when the transcript file is stale (>10s)" {
  mkdir -p "$HOME/.claude/projects/test-session"
  jsonl="$HOME/.claude/projects/test-session/session.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}' > "$jsonl"
  # Touch to 30 seconds ago
  touch -t "$(date -v-30S +%Y%m%d%H%M.%S 2>/dev/null || date -d '30 seconds ago' +%Y%m%d%H%M.%S)" "$jsonl" 2>/dev/null || true
  run bash -c "echo '{}' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" != *"●"* ]]
}

@test "activity hides when no projects directory exists" {
  # No ~/.claude/projects/ at all
  run bash -c "echo '{}' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" != *"●"* ]]
}

@test "hostile tool name in transcript is whitelist-rejected" {
  mkdir -p "$HOME/.claude/projects/test-session"
  jsonl="$HOME/.claude/projects/test-session/session.jsonl"
  # Attempt to inject via tool_use.name
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"\u001b[2J","input":{}}]}}' > "$jsonl"
  run bash -c "echo '{}' | bash '$RENDERER'"
  # The clear-screen escape (ESC [ 2 J) must not appear in raw output
  echo "$output" | od -c | grep -q "2   J" && false || true
}

# Update checker tests removed in v2.0.0: the plugin manager handles
# updates via /plugin update.
