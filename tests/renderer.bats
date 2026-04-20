#!/usr/bin/env bats
# Black-box tests for craft-statusline.sh.
# Run: bats tests/

load helpers

setup() {
  unset MODEL_NAME CONTEXT_PCT FIVE_H SEVEN_D COST
  # Sandbox HOME so tests do not touch the developer's real ~/.claude.
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.claude"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ── CLI flags ─────────────────────────────────────────────────────────────────

@test "--version prints a semver and exits 0" {
  run bash "$RENDERER" --version
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ craft-statusline\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "--doctor exits 0 and reports environment" {
  run bash "$RENDERER" --doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"environment report"* ]]
  [[ "$output" == *"jq:"* ]]
  [[ "$output" == *"SHOW_"* ]]
}

# ── Basic rendering ───────────────────────────────────────────────────────────

@test "renders modern Claude Code display_name with paren suffix" {
  # "Opus 4.7 (1M context)" must render as "Opus 4.7" (compact).
  payload='{"model":{"id":"claude-opus-4-7[1m]","display_name":"Opus 4.7 (1M context)"}}'
  run bash -c "echo '$payload' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"Opus 4.7"* ]]
  [[ "$clean" != *"1M context"* ]]
}

@test "still shortens legacy claude-opus-4-7 id format" {
  payload='{"model":{"id":"claude-opus-4-7"}}'
  run bash -c "echo '$payload' | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"Opus 4.7"* ]]
}

@test "renders model, context, and rate limits for a normal payload" {
  run bash -c "$(sample_json | sed 's/"/\\"/g' | sed 's/^/echo "/;s/$/"/') | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"Sonnet 4.6"* ]]
  [[ "$clean" == *"42%"* ]]
  [[ "$clean" == *"5h"* ]]
  [[ "$clean" == *"7d"* ]]
}

@test "empty JSON object produces non-crashing output" {
  run bash -c "echo '{}' | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
}

@test "invalid JSON does not crash" {
  run bash -c "echo 'not json' | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
}

# ── Color thresholds ──────────────────────────────────────────────────────────

@test "context 42% renders green" {
  CONTEXT_PCT=42 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  [[ "$output" == *"0;175;80"* ]]
}

@test "rate limit 72% renders orange" {
  FIVE_H=72 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  [[ "$output" == *"255;176;85"* ]]
}

@test "rate limit 88% renders red" {
  FIVE_H=88 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  [[ "$output" == *"255;85;85"* ]]
}

# ── Context alert ─────────────────────────────────────────────────────────────

@test "context below threshold has no alert symbol" {
  CONTEXT_PCT=80 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" != *"⚠"* ]]
}

@test "context at or above threshold shows red ⚠" {
  CONTEXT_PCT=90 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"⚠"* ]]
  # Red color (255;85;85) must be present near the warning
  [[ "$output" == *"255;85;85"* ]]
}

# ── Security: escape-injection defense ────────────────────────────────────────

@test "hostile model display_name gets scrubbed" {
  hostile='{"model":{"display_name":"\u001b[2J\u001b[H"}}'
  run bash -c "echo '$hostile' | bash '$RENDERER'"
  [[ "$status" -eq 0 ]]
  echo "$output" | od -c | grep -q "2   J" && false || true
}

@test "hostile effort value gets scrubbed by whitelist" {
  bad_effort='$(rm -rf /)'
  [[ ! "$bad_effort" =~ ^[A-Za-z0-9_-]+$ ]]
}

@test "valid effort values pass the whitelist" {
  for v in low normal high ultrathink token-efficient_1 xhigh; do
    [[ "$v" =~ ^[A-Za-z0-9_-]+$ ]]
  done
}

# ── Installer / wizard flags ──────────────────────────────────────────────────

@test "installer --version prints version and jq version" {
  run bash "$INSTALLER" --version
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"installer"* ]]
  [[ "$output" == *"bundles jq"* ]]
}

@test "wizard --version prints semver and exits 0" {
  run bash "$WIZARD" --version
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ craft-statusline-wizard\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ── Static source checks ──────────────────────────────────────────────────────

@test "all three scripts pass bash -n syntax check" {
  bash -n "$RENDERER"
  bash -n "$WIZARD"
  bash -n "$INSTALLER"
}

@test "no em-dash as sentence separator in docs" {
  ! grep -l '—' "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/CLAUDE.md" "$PROJECT_ROOT/CHANGELOG.md" "$PROJECT_ROOT/CONTRIBUTING.md" 2>/dev/null
}

@test "version string is consistent across renderer, wizard, installer" {
  ver_r=$(bash "$RENDERER"  --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  ver_w=$(bash "$WIZARD"    --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  ver_i=$(bash "$INSTALLER" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [[ "$ver_r" == "$ver_w" ]]
  [[ "$ver_r" == "$ver_i" ]]
}
