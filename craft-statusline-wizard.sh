#!/bin/bash
# craft-statusline-wizard, interactive field configurator
# https://github.com/derjochenmeyer/claude-code-craft-statusline
#
# Run: bash ~/.claude/craft-statusline-wizard.sh
# Flags:
#   --version   print version and exit

set -uo pipefail

VERSION="1.0.0"

if [[ "${1:-}" == "--version" ]]; then
  echo "craft-statusline-wizard $VERSION"
  exit 0
fi

: "${HOME:?HOME is not set; cannot locate ~/.claude}"

STATUSLINE="$HOME/.claude/craft-statusline.sh"
GITHUB_RAW="https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main"

# ── Portable sed in-place ─────────────────────────────────────────────────────
if sed --version 2>/dev/null | grep -q GNU; then
  sed_inplace() { sed -i "$@"; }
else
  sed_inplace() { sed -i '' "$@"; }
fi

# ── jq resolution ─────────────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
  JQ=jq
elif [[ -x "$HOME/.claude/bin/jq" ]]; then
  JQ="$HOME/.claude/bin/jq"
else
  JQ=""
fi

echo ""
echo "craft-statusline wizard"
echo "────────────────────────────────────"

if [[ -z "$JQ" ]]; then
  echo ""
  echo "  Warning: jq not found (PATH or ~/.claude/bin/)."
  echo "  Settings.json integration will be skipped."
  echo "  Re-run install.sh to install jq automatically."
fi

if [[ ! -f "$STATUSLINE" ]]; then
  echo ""
  echo "  craft-statusline.sh is not installed."
  echo ""
  read -rp "  Install it now? [Y/n]  " answer </dev/tty
  answer="${answer:-Y}"
  if [[ "$(echo "$answer" | tr '[:lower:]' '[:upper:]')" == "Y" ]]; then
    download_tmp="${STATUSLINE}.tmp.$$"
    if ! curl -fL --show-error "$GITHUB_RAW/craft-statusline.sh" -o "$download_tmp"; then
      rm -f "$download_tmp"
      echo "  Download failed. Aborting."
      exit 1
    fi
    if ! head -1 "$download_tmp" | grep -q "^#!"; then
      rm -f "$download_tmp"
      echo "  Downloaded file does not look like a shell script. Aborting."
      exit 1
    fi
    mv "$download_tmp" "$STATUSLINE"
    chmod +x "$STATUSLINE"
    echo "  Installed."
  else
    echo "  Aborted."
    exit 0
  fi
fi

get_val() {
  local raw
  raw=$(grep "^$1=" "$STATUSLINE" | cut -d= -f2 | tr -d '[:space:]' | cut -d'#' -f1)
  [[ "$raw" == "true" ]] && echo "true" || echo "false"
}

ask() {
  local step="$1"
  local name="$2"
  local desc="$3"
  local var="$4"
  local current
  current=$(get_val "$var")

  local current_label
  [[ "$current" == "true" ]] && current_label="on" || current_label="off"

  local input
  read -rp "  $step  $name  $desc  (currently: $current_label)  1/0: " input </dev/tty

  case "$input" in
    1) echo "true"  ;;
    0) echo "false" ;;
    *) echo "$current" ;;
  esac
}

echo ""
echo "  Enter 1 to enable, 0 to disable, or press Enter to keep the current value."
echo ""

val_model=$(ask    "[1/7]" "model   " "current model name            " "SHOW_MODEL")
val_effort=$(ask   "[2/7]" "effort  " "effort level from settings    " "SHOW_EFFORT")
val_context=$(ask  "[3/7]" "context " "context window usage          " "SHOW_CONTEXT")
val_rate=$(ask     "[4/7]" "rate    " "5h and 7d token usage         " "SHOW_RATE_LIMITS")
val_cost=$(ask     "[5/7]" "cost    " "USD cost (API billing only!)  " "SHOW_COST")
val_branch=$(ask   "[6/7]" "branch  " "git branch + status + tracking" "SHOW_BRANCH")
val_activity=$(ask "[7/7]" "activity" "thinking / executing / research" "SHOW_ACTIVITY")

label() { [[ "$1" == "true" ]] && echo "on" || echo "off"; }

echo ""
echo "  Your configuration:"
echo ""
echo "    model    $(label "$val_model")     effort   $(label "$val_effort")     context  $(label "$val_context")"
echo "    rate     $(label "$val_rate")     cost     $(label "$val_cost")     branch   $(label "$val_branch")"
echo "    activity $(label "$val_activity")"
echo ""
if [[ "$val_cost" == "true" ]]; then
  echo "  NOTE: cost is an API-billing metric. On Pro/Team/Max flat-rate plans,"
  echo "        this number is a hypothetical pay-per-token equivalent, not your"
  echo "        actual invoice. Your real constraints on those plans are 5h/7d rate limits."
  echo ""
fi
echo "  Advanced toggles (context-alert ⚠, update-checker ⬆) live at the top of"
echo "  $STATUSLINE and can be edited directly."

apply_all() {
  local target="$1"
  sed_inplace "s/^SHOW_MODEL=.*/SHOW_MODEL=$val_model/"                 "$target" || return 1
  sed_inplace "s/^SHOW_EFFORT=.*/SHOW_EFFORT=$val_effort/"              "$target" || return 1
  sed_inplace "s/^SHOW_CONTEXT=.*/SHOW_CONTEXT=$val_context/"           "$target" || return 1
  sed_inplace "s/^SHOW_RATE_LIMITS=.*/SHOW_RATE_LIMITS=$val_rate/"      "$target" || return 1
  sed_inplace "s/^SHOW_COST=.*/SHOW_COST=$val_cost/"                    "$target" || return 1
  sed_inplace "s/^SHOW_BRANCH=.*/SHOW_BRANCH=$val_branch/"              "$target" || return 1
  sed_inplace "s/^SHOW_ACTIVITY=.*/SHOW_ACTIVITY=$val_activity/"        "$target" || return 1
  return 0
}

preview_tmp=$(mktemp)
cp "$STATUSLINE" "$preview_tmp"
if ! apply_all "$preview_tmp"; then
  rm -f "$preview_tmp"
  echo "  sed failed while building the preview. Nothing changed."
  exit 1
fi
if ! bash -n "$preview_tmp" 2>/dev/null; then
  rm -f "$preview_tmp"
  echo "  preview script has syntax errors. Refusing to apply. Nothing changed."
  exit 1
fi

echo -n "  Preview: "
echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":30}},"cost":{"total_cost_usd":0.85}}' \
  | bash "$preview_tmp"

echo ""

read -rp "  Apply? [Y/n]  " confirm </dev/tty
confirm="${confirm:-Y}"
if [[ "$(echo "$confirm" | tr '[:lower:]' '[:upper:]')" != "Y" ]]; then
  rm -f "$preview_tmp"
  echo "  Aborted. No changes made."
  echo ""
  exit 0
fi

if [[ -x "$STATUSLINE" ]]; then
  chmod +x "$preview_tmp"
fi
if ! mv "$preview_tmp" "$STATUSLINE"; then
  rm -f "$preview_tmp"
  echo "  Failed to write $STATUSLINE. Nothing changed."
  exit 1
fi

echo "  Applied."
echo "  Note: emoji and color are always on. Edit ~/.claude/craft-statusline.sh directly to change them."

if [[ -n "$JQ" ]]; then
  current_cmd=$("$JQ" -r '.statusLine.command // "NOT_CONFIGURED"' "$HOME/.claude/settings.json" 2>/dev/null)
  if [[ "$current_cmd" != *"craft-statusline"* ]]; then
    echo ""
    if [[ "$current_cmd" != "NOT_CONFIGURED" ]]; then
      echo "  Current status bar: $current_cmd"
    fi
    read -rp "  Activate craft-statusline in settings.json? [Y/n]  " activate </dev/tty
    activate="${activate:-Y}"
    if [[ "$(echo "$activate" | tr '[:lower:]' '[:upper:]')" == "Y" ]]; then
      tmp=$(mktemp)
      if "$JQ" '.statusLine = {"type": "command", "command": "~/.claude/craft-statusline.sh", "refreshInterval": 5000}' \
        "$HOME/.claude/settings.json" > "$tmp" && mv "$tmp" "$HOME/.claude/settings.json"; then
        echo "  Activated."
      else
        rm -f "$tmp"
        echo "  Failed to update settings.json."
      fi
    fi
  fi
else
  echo ""
  echo "  Skipping settings.json activation (jq not available)."
  echo "  After installing jq, run /craft-statusline install to activate."
fi

echo ""
echo "  Done. Changes are applied immediately, no restart required."
echo ""
