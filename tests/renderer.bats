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

@test "context at 42% with low tokens renders green, no ⚠" {
  CONTEXT_PCT=42 CONTEXT_TOKENS=150000 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" != *"⚠"* ]]
  # Green (0;175;80) on the percentage
  [[ "$output" == *"0;175;80"* ]]
}

@test "context at 42% with >=400k tokens renders yellow ⚠ (context rot threshold)" {
  CONTEXT_PCT=42 CONTEXT_TOKENS=420000 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
  clean=$(echo "$output" | strip_ansi)
  [[ "$clean" == *"⚠"* ]]
  # Yellow (230;200;0) on both the percentage and the warning, not red
  [[ "$output" == *"230;200;0"* ]]
  [[ "$output" != *"255;85;85"* ]]
}

@test "context at 90% overrides yellow (percent-alert wins over token-degrade)" {
  CONTEXT_PCT=90 CONTEXT_TOKENS=420000 run bash -c "$(declare -f sample_json); sample_json | bash '$RENDERER'"
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

# ── Static source checks ──────────────────────────────────────────────────────

@test "renderer passes bash -n syntax check" {
  bash -n "$RENDERER"
}

@test "no em-dash as sentence separator in docs" {
  ! grep -l '—' "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/CLAUDE.md" "$PROJECT_ROOT/CHANGELOG.md" "$PROJECT_ROOT/CONTRIBUTING.md" 2>/dev/null
}

@test "renderer version matches plugin manifest" {
  ver_r=$(bash "$RENDERER" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  ver_m=$(jq -r '.version' "$PROJECT_ROOT/.claude-plugin/plugin.json")
  [[ "$ver_r" == "$ver_m" ]]
}

@test "marketplace.json version matches plugin manifest" {
  ver_m=$(jq -r '.version' "$PROJECT_ROOT/.claude-plugin/plugin.json")
  ver_p=$(jq -r '.plugins[0].version' "$PROJECT_ROOT/.claude-plugin/marketplace.json")
  [[ "$ver_m" == "$ver_p" ]]
}
