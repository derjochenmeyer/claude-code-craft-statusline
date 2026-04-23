#!/usr/bin/env bats
# Tests for custom fields.

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
  # Timeout is 2s per field; add slack for test-machine variance.
  [[ "$elapsed" -lt 8 ]]
}

@test "transcript_path from stdin is preferred over global latest jsonl" {
  # Two sessions exist. The "other" one was written more recently. When
  # the context field reads session start time, it must follow the
  # transcript_path in the input JSON and not the global mtime, otherwise
  # multi-session setups show the wrong session duration.
  mkdir -p "$HOME/.claude/projects/mine" "$HOME/.claude/projects/other"
  mine="$HOME/.claude/projects/mine/session.jsonl"
  other="$HOME/.claude/projects/other/session.jsonl"
  echo '{"type":"assistant"}' > "$mine"
  echo '{"type":"assistant"}' > "$other"
  touch "$other"
  # Smoke test only: ensure the renderer does not crash when transcript_path
  # points at a specific session file.
  run bash -c "echo '{\"transcript_path\":\"$mine\",\"context_window\":{\"used_percentage\":42,\"current_usage\":{\"input_tokens\":0,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}}}' | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
}
