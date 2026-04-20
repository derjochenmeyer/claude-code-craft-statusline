#!/usr/bin/env bash
# Shared helpers for bats tests.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$PROJECT_ROOT/craft-statusline.sh"
WIZARD="$PROJECT_ROOT/craft-statusline-wizard.sh"
INSTALLER="$PROJECT_ROOT/install.sh"

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
  local fh="${FIVE_H:-15}"
  local sd="${SEVEN_D:-30}"
  local cost="${COST:-0.85}"
  cat <<EOF
{"model":{"display_name":"$model"},"context_window":{"used_percentage":$ctx},"rate_limits":{"five_hour":{"used_percentage":$fh},"seven_day":{"used_percentage":$sd}},"cost":{"total_cost_usd":$cost}}
EOF
}

# Render with a temporary copy of the renderer so we can tweak SHOW_* flags
# without touching the canonical script.
render_with_flags() {
  local flags="$1" tmp json
  tmp=$(mktemp)
  cp "$RENDERER" "$tmp"
  chmod +x "$tmp"
  while IFS= read -r line; do
    local key="${line%%=*}" val="${line#*=}"
    # Replace only the value on the variable line; keep comments intact.
    sed -i.bak "s/^${key}=.*/${key}=${val}/" "$tmp" 2>/dev/null || perl -i -pe "s/^${key}=.*/${key}=${val}/" "$tmp"
  done <<< "$flags"
  rm -f "${tmp}.bak"
  if [[ -t 0 ]]; then
    json=$(sample_json)
    echo "$json" | bash "$tmp"
  else
    bash "$tmp"
  fi
  rm -f "$tmp"
}
