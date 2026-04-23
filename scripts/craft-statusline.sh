#!/bin/bash
# craft-statusline
# https://github.com/derjochenmeyer/claude-code-craft-statusline
#
# Plugin renderer. Wired up by Claude Code via the user's settings.json
# pointing at ${CLAUDE_PLUGIN_ROOT}/scripts/craft-statusline.sh.
#
# Configuration is supplied by the plugin's userConfig as
# CLAUDE_PLUGIN_OPTION_<KEY> environment variables (see plugin.json).
# The :on / :off / :status slash commands edit those values in
# ~/.claude/settings.json under pluginConfigs.craft-statusline.options.*
#
# Flags:
#   --version   print version and exit
#   --doctor    run environment checks and exit

VERSION="3.0.0"

# Boolean coercion: anything except literal "true" → false.
bool_opt() {
  local v="$1" default="$2"
  [[ -z "$v" ]] && v="$default"
  [[ "$v" == "true" ]] && echo "true" || echo "false"
}

# ── Configuration (from plugin userConfig, with sane defaults) ────
SHOW_MODEL=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_MODEL:-}" "true")
SHOW_BRANCH=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_BRANCH:-}" "true")
SHOW_CONTEXT=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_CONTEXT:-}" "true")
SHOW_CONTEXT_ALERT=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_CONTEXT_ALERT:-}" "true")
SHOW_RATE_LIMITS=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_RATE_LIMITS:-}" "true")
SHOW_COST=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_COST:-}" "false")
SHOW_COLOR=$(bool_opt "${CLAUDE_PLUGIN_OPTION_SHOW_COLOR:-}" "true")
# Effort is always shown when SHOW_MODEL is on (always paired). Removed as
# a separate toggle in v2.0.0 since the two never made sense apart.
SHOW_EFFORT="$SHOW_MODEL"

# ── Thresholds ───────────────────────────────────────────────────
# Context field traffic light:
#   tokens <  CONTEXT_DEGRADE_AT_TOKENS  → green, no symbol
#   tokens >= CONTEXT_DEGRADE_AT_TOKENS  → yellow + ⚠  (context rot / quality degrades)
#   percent >= CONTEXT_ALERT_AT          → red    + ⚠  (compact is imminent)
# Rot trumps Yellow. The degrade threshold is absolute because context rot
# is a model-behaviour problem, not a fill-level problem: on a 1M window,
# 85% is way past the point of degraded recall.
CONTEXT_ALERT_AT="${CLAUDE_PLUGIN_OPTION_CONTEXT_ALERT_AT:-85}"
CONTEXT_DEGRADE_AT_TOKENS="${CLAUDE_PLUGIN_OPTION_CONTEXT_DEGRADE_AT_TOKENS:-400000}"
# NOTE: 400k reflects Anthropic's public MRCR v2 numbers for the Claude 4
# family (roughly 15-17 pp accuracy drop between 256k and 1M).
# Re-validate when new model generations ship.

# ── Security bounds ──────────────────────────────────────────────
# Hard caps on any user-influenced string we render. Defence-in-depth on
# top of the whitelist regex: even if something gets past the character
# class, the length clamp prevents pathological inputs from reaching
# printf %b.
MAX_MODEL_LEN=64
MAX_EFFORT_LEN=32
MAX_BRANCH_LEN=128

# Guard against unset HOME.
: "${HOME:?HOME is not set; cannot locate ~/.claude}"

# jq is a hard requirement. The plugin's :install command verifies it
# before activating, so by the time we run here it should be present.
# If it disappeared since install, we render nothing rather than garbage.
find_jq() {
  command -v jq 2>/dev/null
}

# ── CLI flags ────────────────────────────────────────────────────
case "${1:-}" in
  --version)
    echo "craft-statusline $VERSION"
    exit 0
    ;;
  --doctor)
    echo "craft-statusline $VERSION, environment report"
    echo "════════════════════════════════════════════════"
    printf '  %-24s ' "bash:"
    echo "$BASH_VERSION"

    printf '  %-24s ' "jq:"
    jq_bin=$(find_jq)
    if [[ -z "$jq_bin" ]]; then
      echo "NOT FOUND, the statusline will render nothing"
    else
      jq_version=$("$jq_bin" --version 2>/dev/null || echo "?")
      echo "$jq_bin ($jq_version)"
    fi

    printf '  %-24s ' "git:"
    if command -v git >/dev/null 2>&1; then
      git --version
    else
      echo "not found (branch field will be skipped)"
    fi

    settings="$HOME/.claude/settings.json"
    printf '  %-24s ' "settings.json:"
    if [[ ! -f "$settings" ]]; then
      echo "does not exist"
    elif [[ -n "$jq_bin" ]] && ! "$jq_bin" empty "$settings" 2>/dev/null; then
      echo "EXISTS but is not valid JSON"
    else
      echo "$settings"
      if [[ -n "$jq_bin" ]]; then
        cmd=$("$jq_bin" -r '.statusLine.command // "NOT_CONFIGURED"' "$settings" 2>/dev/null)
        printf '  %-24s ' "  statusLine.command:"
        echo "$cmd"
        interval=$("$jq_bin" -r '.statusLine.refreshInterval // "(unset)"' "$settings" 2>/dev/null)
        printf '  %-24s ' "  refreshInterval:"
        echo "$interval"
        effort=$("$jq_bin" -r '.effortLevel // "(unset)"' "$settings" 2>/dev/null)
        printf '  %-24s ' "  effortLevel:"
        echo "$effort"
      fi
    fi

    printf '  %-24s ' "renderer path:"
    echo "${CLAUDE_PLUGIN_ROOT:-(not set, run from a Claude Code session)}/scripts/craft-statusline.sh"

    printf '  %-24s ' "custom fields file:"
    if [[ -f "$HOME/.claude/craft-statusline-custom.sh" ]]; then
      echo "$HOME/.claude/craft-statusline-custom.sh"
    else
      echo "not present (optional)"
    fi

    echo ""
    echo "  Active configuration (resolved from CLAUDE_PLUGIN_OPTION_* env):"
    printf '    %-30s %s\n' "SHOW_MODEL=" "$SHOW_MODEL"
    printf '    %-30s %s\n' "SHOW_BRANCH=" "$SHOW_BRANCH"
    printf '    %-30s %s\n' "SHOW_CONTEXT=" "$SHOW_CONTEXT"
    printf '    %-30s %s\n' "SHOW_CONTEXT_ALERT=" "$SHOW_CONTEXT_ALERT"
    printf '    %-30s %s\n' "SHOW_RATE_LIMITS=" "$SHOW_RATE_LIMITS"
    printf '    %-30s %s\n' "SHOW_COST=" "$SHOW_COST"
    printf '    %-30s %s\n' "SHOW_COLOR=" "$SHOW_COLOR"
    printf '    %-30s %s\n' "CONTEXT_ALERT_AT=" "$CONTEXT_ALERT_AT"
    printf '    %-30s %s\n' "CONTEXT_DEGRADE_AT_TOKENS=" "$CONTEXT_DEGRADE_AT_TOKENS"
    echo ""
    exit 0
    ;;
esac

JQ=$(find_jq)
if [[ -z "$JQ" ]]; then
  exit 0
fi

export LC_NUMERIC=C
input=$(cat)
parts=()

# ── Colors ───────────────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
green='\033[38;2;0;175;80m'
yellow='\033[38;2;230;200;0m'
orange='\033[38;2;255;176;85m'
red='\033[38;2;255;85;85m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
rst='\033[0m'
# State-aware branch palette. Picked in the branch block based on the
# dominant git signal (conflict > diverged > behind > combined > ahead > ...).
bg_clean='\033[48;2;30;150;70m';     fg_clean='\033[38;2;210;255;220m'
bg_ahead='\033[48;2;200;130;20m';    fg_ahead='\033[38;2;255;230;130m'
bg_behind='\033[48;2;30;110;160m';   fg_behind='\033[38;2;180;230;255m'
bg_combined='\033[48;2;210;90;30m';  fg_combined='\033[38;2;255;200;155m'
bg_untracked='\033[48;2;80;95;130m'; fg_untracked='\033[38;2;200;215;245m'
bg_stashed='\033[48;2;130;55;170m';  fg_stashed='\033[38;2;235;195;255m'
bg_conflict='\033[48;2;190;40;60m';  fg_conflict='\033[38;2;255;180;185m'
effort_col='\033[38;2;255;175;60m'

color_for_pct() {
  [[ "$SHOW_COLOR" != "true" ]] && return
  local p=${1%%.*}
  if   [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 85 )); then printf '%s' "$red"
  elif [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 70 )); then printf '%s' "$orange"
  elif [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 50 )); then printf '%s' "$yellow"
  elif [[ "$p" =~ ^[0-9]+$ ]];                   then printf '%s' "$green"
  fi
}
# ─────────────────────────────────────────────────────────────────

sep="${dim}│${rst}"

# ── Session transcript discovery ─────────────────────────────────
# The context field uses the transcript's creation time to show session
# duration. Prefer the harness-supplied transcript_path from stdin (correct
# in multi-session setups); fall back to the most-recently-modified jsonl
# across all projects only when the input lacks it.
session_file=""
if [[ -n "$input" ]]; then
  candidate=$(echo "$input" | "$JQ" -r 'if (.transcript_path | type) == "string" then .transcript_path else empty end' 2>/dev/null)
  if [[ -n "$candidate" && -r "$candidate" ]]; then
    session_file="$candidate"
  fi
fi
if [[ -z "$session_file" && -d "$HOME/.claude/projects" ]]; then
  session_file=$(find "$HOME/.claude/projects" -type f -name "*.jsonl" -print0 2>/dev/null \
                 | xargs -0 ls -t 2>/dev/null \
                 | head -1)
fi

# ── Model + effort ───────────────────────────────────────────────
if [[ "$SHOW_MODEL" == "true" ]]; then
  model=$(echo "$input" | "$JQ" -r '
    if (.model | type) == "object" then
      (if (.model.display_name | type) == "string" then .model.display_name
       elif (.model.id | type) == "string" then .model.id
       else empty end)
    elif (.model | type) == "string" then .model
    else empty end
  ' 2>/dev/null)
  model=$(echo "$model" | sed 's/^[Cc]laude[- ]//' | sed 's/^\([a-z]*\)-\([0-9]*\)-\([0-9]*\).*/\1 \2.\3/')
  model=$(echo "$model" | sed 's/ *([^)]*)//g')
  model=$(echo "$model" | awk '{$1=toupper(substr($1,1,1)) substr($1,2); print}')
  if [[ ${#model} -gt $MAX_MODEL_LEN || ! "$model" =~ ^[A-Za-z0-9\ ._-]+$ ]]; then
    model=""
  fi
  if [[ -n "$model" ]]; then
    model_str="${blue}${model}${rst}"
    if [[ "$SHOW_EFFORT" == "true" ]]; then
      effort=$("$JQ" -r 'if (.effortLevel | type) == "string" then .effortLevel else empty end' ~/.claude/settings.json 2>/dev/null)
      if [[ ${#effort} -gt $MAX_EFFORT_LEN || ! "$effort" =~ ^[A-Za-z0-9_-]+$ ]]; then
        effort=""
      fi
      [[ -n "$effort" ]] && model_str+="${dim}▸${rst}${effort_col}${effort}${rst}"
    fi
    parts+=("$model_str")
  fi
fi

# ── Git branch + status ──────────────────────────────────────────
if [[ "$SHOW_BRANCH" == "true" ]]; then
  branch=$(git branch --show-current 2>/dev/null)
  if [[ ${#branch} -gt $MAX_BRANCH_LEN || ! "$branch" =~ ^[A-Za-z0-9/._-]+$ ]]; then
    branch=""
  fi
  if [[ -n "$branch" ]]; then
    git_porcelain=$(git status --porcelain 2>/dev/null)
    staged=0; unstaged=0; untracked=0; conflicts=0
    if [[ -n "$git_porcelain" ]]; then
      staged=$(printf '%s\n' "$git_porcelain" | awk '/^[MADRC]/{n++} END{print n+0}')
      unstaged=$(printf '%s\n' "$git_porcelain" | awk '/^.[MD]/{n++} END{print n+0}')
      untracked=$(printf '%s\n' "$git_porcelain" | awk '/^\?\?/{n++} END{print n+0}')
      conflicts=$(printf '%s\n' "$git_porcelain" | awk '/^(UU|AA|DD)/{n++} END{print n+0}')
    fi
    ahead=$(git rev-list "@{u}..HEAD" --count 2>/dev/null || echo 0)
    behind=$(git rev-list "HEAD..@{u}" --count 2>/dev/null || echo 0)
    stash=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
    git_meta=""
    [[ "$ahead"     -gt 0 ]] && git_meta+=" ⇡${ahead}"
    [[ "$behind"    -gt 0 ]] && git_meta+=" ⇣${behind}"
    [[ "$stash"     -gt 0 ]] && git_meta+=" *${stash}"
    [[ "$staged"    -gt 0 ]] && git_meta+=" +${staged}"
    [[ "$unstaged"  -gt 0 ]] && git_meta+=" !${unstaged}"
    [[ "$untracked" -gt 0 ]] && git_meta+=" ?${untracked}"
    [[ "$conflicts" -gt 0 ]] && git_meta+=" ⚠${conflicts}"
    [[ -z "$git_meta" ]] && git_meta=" ✔"

    # Pick the dominant signal. Priority runs from "blocking" (conflict)
    # down to "nothing going on" (clean). combined covers the common
    # working-tree-with-several-kinds-of-changes case.
    local_changes=0
    [[ "$staged"    -gt 0 ]] && local_changes=$((local_changes + 1))
    [[ "$unstaged"  -gt 0 ]] && local_changes=$((local_changes + 1))
    [[ "$untracked" -gt 0 ]] && local_changes=$((local_changes + 1))
    if   [[ "$conflicts" -gt 0 ]];                              then bg_cur="$bg_conflict";  fg_cur="$fg_conflict"
    elif [[ "$ahead" -gt 0 && "$behind" -gt 0 ]];               then bg_cur="$bg_combined";  fg_cur="$fg_combined"
    elif [[ "$behind" -gt 0 ]];                                 then bg_cur="$bg_behind";    fg_cur="$fg_behind"
    elif [[ "$ahead" -gt 0 && "$local_changes" -gt 0 ]];        then bg_cur="$bg_combined";  fg_cur="$fg_combined"
    elif [[ "$local_changes" -ge 2 ]];                          then bg_cur="$bg_combined";  fg_cur="$fg_combined"
    elif [[ "$ahead" -gt 0 ]];                                  then bg_cur="$bg_ahead";     fg_cur="$fg_ahead"
    elif [[ "$unstaged" -gt 0 ]];                               then bg_cur="$bg_ahead";     fg_cur="$fg_ahead"
    elif [[ "$staged" -gt 0 ]];                                 then bg_cur="$bg_clean";     fg_cur="$fg_clean"
    elif [[ "$untracked" -gt 0 ]];                              then bg_cur="$bg_untracked"; fg_cur="$fg_untracked"
    elif [[ "$stash" -gt 0 ]];                                  then bg_cur="$bg_stashed";   fg_cur="$fg_stashed"
    else                                                             bg_cur="$bg_clean";     fg_cur="$fg_clean"
    fi

    parts+=("${bg_cur}${fg_cur} ${branch}${git_meta} ${rst}")
  fi
fi

# ── Context + session duration ───────────────────────────────────
if [[ "$SHOW_CONTEXT" == "true" ]]; then
  ctx=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // empty' 2>/dev/null)
  if [[ -n "$ctx" ]]; then
    # Absolute token count from the LAST API call. Claude Code's docs
    # explicitly recommend current_usage.* over total_* (cumulative session
    # totals are a separate, pre-compact figure). Sum input + cache_creation
    # + cache_read; exclude output (it belongs to the next turn).
    ctx_tokens=$(echo "$input" | "$JQ" -r '
      (.context_window.current_usage.input_tokens // 0)
      + (.context_window.current_usage.cache_creation_input_tokens // 0)
      + (.context_window.current_usage.cache_read_input_tokens // 0)
    ' 2>/dev/null)
    ctx_tokens=${ctx_tokens:-0}
    # Traffic light: red (percent >= ALERT) > yellow (tokens >= DEGRADE) > green.
    ctx_int=${ctx%%.*}
    if [[ "$SHOW_COLOR" == "true" ]]; then
      if [[ "$ctx_int" =~ ^[0-9]+$ ]] && (( ctx_int >= CONTEXT_ALERT_AT )); then
        c="$red"
      elif [[ "$ctx_tokens" =~ ^[0-9]+$ ]] && (( ctx_tokens >= CONTEXT_DEGRADE_AT_TOKENS )); then
        c="$yellow"
      else
        c="$green"
      fi
    else
      c=""
    fi
    prefix="ctx${dim}▸${rst}"
    dur_str=""
    if [[ -n "$session_file" ]]; then
      # GNU stat (-c %W) is checked BEFORE BSD stat (-f %B) because GNU
      # stat silently accepts -f for filesystem info, returning a mount
      # point string that would look like a valid (but wrong) number to
      # the fallback. Linux-first ordering keeps the behaviour correct
      # on both Linux and macOS.
      start_epoch=$(stat -c "%W" "$session_file" 2>/dev/null || stat -f "%B" "$session_file" 2>/dev/null || echo 0)
      if [[ "$start_epoch" == "0" ]]; then
        start_epoch=$(stat -c "%Y" "$session_file" 2>/dev/null || stat -f "%m" "$session_file" 2>/dev/null || echo 0)
      fi
      if [[ "$start_epoch" =~ ^[0-9]+$ && "$start_epoch" -gt 0 ]]; then
        secs=$(( $(date +%s) - start_epoch ))
        if (( secs > 0 )); then
          h=$(( secs / 3600 ))
          m=$(( (secs % 3600) / 60 ))
          if (( h > 0 )); then
            dur_str=" ${dim}(${h}h${m}m)${rst}"
          else
            dur_str=" ${dim}(${m}m)${rst}"
          fi
        fi
      fi
    fi
    # ⚠ shares the %-text color. Symbol appears on yellow and red, not on green.
    alert=""
    if [[ "$SHOW_CONTEXT_ALERT" == "true" && -n "$c" && "$c" != "$green" ]]; then
      alert=" ${c}⚠${rst}"
    fi
    parts+=("${prefix}${c}${ctx}%${rst}${alert}${dur_str}")
  fi
fi

# ── Rate limits ──────────────────────────────────────────────────
if [[ "$SHOW_RATE_LIMITS" == "true" ]]; then
  five_h=$(echo "$input" | "$JQ" -r 'if .rate_limits.five_hour.used_percentage then (.rate_limits.five_hour.used_percentage * 10 | round / 10 | tostring) else empty end' 2>/dev/null)
  seven_d=$(echo "$input" | "$JQ" -r 'if .rate_limits.seven_day.used_percentage then (.rate_limits.seven_day.used_percentage * 10 | round / 10 | tostring) else empty end' 2>/dev/null)
  if [[ -n "$five_h" ]]; then
    c=$(color_for_pct "$five_h")
    parts+=("5h▸${c}${five_h}%${rst}")
  fi
  if [[ -n "$seven_d" ]]; then
    c=$(color_for_pct "$seven_d")
    parts+=("7d▸${c}${seven_d}%${rst}")
  fi
fi

# ── Session cost (API-billing only) ──────────────────────────────
# Off by default because on flat-rate plans (Pro/Team/Max) this number
# is a hypothetical pay-per-token equivalent, not the user's invoice.
if [[ "$SHOW_COST" == "true" ]]; then
  cost=$(echo "$input" | "$JQ" -r '.cost.total_cost_usd // empty' 2>/dev/null)
  if [[ -n "$cost" ]] && [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    cost_num=$(LC_ALL=C printf "%.2f" "$cost" 2>/dev/null)
    [[ -n "$cost_num" ]] && parts+=("cost▸${cost_num}\$")
  fi
fi

# ── Custom fields ────────────────────────────────────────────────
# Sourced from ~/.claude/craft-statusline-custom.sh if it exists. The
# file defines shell functions whose names must match the whitelist
# ^field_[A-Za-z0-9_]+$. Set CUSTOM_FIELDS to a space-separated list of
# those function names, in the order you want them rendered.
#
# Each function runs under a hard rendertime cap so a sleeping or
# hanging field cannot block the refresh. Fields are sourced (not
# eval'd) and run in subshells so a crash cannot take down the renderer.
CUSTOM_FIELD_TIMEOUT_SECS=${CUSTOM_FIELD_TIMEOUT_SECS:-2}
CUSTOM_FILE="$HOME/.claude/craft-statusline-custom.sh"

run_custom_field() {
  local fn="$1"
  local tmp
  tmp=$(mktemp)
  # Guard against stray tempfiles if the harness interrupts this function
  # before the explicit rm below.
  trap 'rm -f "$tmp"' RETURN
  ( "$fn" >"$tmp" 2>/dev/null ) &
  local pid=$!
  ( sleep "$CUSTOM_FIELD_TIMEOUT_SECS" && kill -9 "$pid" 2>/dev/null ) &
  local killer=$!
  wait "$pid" 2>/dev/null
  kill -9 "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
  cat "$tmp" 2>/dev/null
  rm -f "$tmp"
}

if [[ -f "$CUSTOM_FILE" ]]; then
  # shellcheck source=/dev/null
  . "$CUSTOM_FILE" 2>/dev/null || true
  for fn in ${CUSTOM_FIELDS:-}; do
    if [[ "$fn" =~ ^field_[A-Za-z0-9_]+$ ]] && declare -f "$fn" >/dev/null 2>&1; then
      out=$(run_custom_field "$fn")
      [[ -n "$out" ]] && parts+=("$out")
    fi
  done
fi

# ── Build output ──────────────────────────────────────────────────
output=""
for part in "${parts[@]}"; do
  [[ -n "$output" ]] && output+=" ${sep} "
  output+="$part"
done
printf "%b\n" "$output"
