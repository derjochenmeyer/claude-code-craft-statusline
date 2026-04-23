#!/usr/bin/env bash
# Shared helpers for bats tests.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$PROJECT_ROOT/scripts/craft-statusline.sh"

# Strip ANSI escape codes so we can match against plain text.
strip_ansi() {
  # SC2016: single-quoted sed pattern intentional
  sed $'s/\x1b\\[[0-9;]*m//g'
}

# Build a sample Claude Code statusline JSON payload. Override fields via
# environment variables for targeted scenarios.
sample_json() {
  local model="${MODEL_NAME:-claude-sonnet-4-6}"
  local ctx="${CONTEXT_PCT:-42}"
  local ctx_tokens="${CONTEXT_TOKENS:-0}"   # sum stored in cache_read for simplicity
  local fh="${FIVE_H:-15}"
  local sd="${SEVEN_D:-30}"
  local cost="${COST:-0.85}"
  cat <<EOF
{"model":{"display_name":"$model"},"context_window":{"used_percentage":$ctx,"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":$ctx_tokens}},"rate_limits":{"five_hour":{"used_percentage":$fh},"seven_day":{"used_percentage":$sd}},"cost":{"total_cost_usd":$cost}}
EOF
}

