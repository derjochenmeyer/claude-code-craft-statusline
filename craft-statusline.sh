#!/bin/bash
# craft-statusline
# https://github.com/derjochenmeyer/claude-code-craft-statusline
#
# Configure with /craft-statusline inside a Claude Code session,
# or edit the SHOW_* variables below directly.
#
# Install: run install.sh or copy to ~/.claude/craft-statusline.sh
# Settings: add to ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "~/.claude/craft-statusline.sh", "refreshInterval": 5000 }
#
# Flags:
#   --version   print version and exit
#   --doctor    run environment checks and exit

VERSION="1.1.0"

# ── Configuration ────────────────────────────────────────────────
SHOW_MODEL=true
SHOW_EFFORT=true
SHOW_BRANCH=true         # git branch badge: main ⇡2 +1 !3 ?1
SHOW_CONTEXT=true
SHOW_CONTEXT_ALERT=true  # ⚠ badge when context crosses CONTEXT_ALERT_AT
SHOW_RATE_LIMITS=true
SHOW_COST=false          # API BILLING ONLY. Meaningless on Pro/Team/Max flat-rate plans.
SHOW_ACTIVITY=true       # ● indicator when Claude is actively working (thinking/executing/researching)
SHOW_UPDATE=true         # ⬆ badge when a newer version is available on the repo
SHOW_COLOR=true          # ANSI color on percentages: green < 50%, yellow < 70%, orange < 85%, red ≥ 85%

# ── Thresholds ───────────────────────────────────────────────────
CONTEXT_ALERT_AT=85            # context percent that triggers the ⚠ badge
ACTIVITY_LIVE_WINDOW_SECS=10   # jsonl mtime younger than this means "Claude is active"

# ── Security bounds ──────────────────────────────────────────────
# Hard caps on any user-influenced string we render. Defence-in-depth on
# top of the whitelist regex: even if something gets past the character
# class, the length clamp prevents pathological inputs from reaching
# printf %b.
MAX_MODEL_LEN=64
MAX_EFFORT_LEN=32
MAX_BRANCH_LEN=128
MAX_ACTIVITY_LEN=48

# ── Update check cache ───────────────────────────────────────────
# Background curl writes the latest published version here; the next
# render reads it without blocking. The cache expires after 24h.
VERSION_CHECK_FILE="$HOME/.claude/state/version-check"
VERSION_CHECK_INTERVAL_SECS=86400
VERSION_CHECK_URL="https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main/craft-statusline.sh"
# ─────────────────────────────────────────────────────────────────

# Guard against unset HOME.
: "${HOME:?HOME is not set; cannot locate ~/.claude}"

find_jq() {
  if command -v jq >/dev/null 2>&1; then
    echo "jq"
  elif [[ -x "$HOME/.claude/bin/jq" ]]; then
    echo "$HOME/.claude/bin/jq"
  else
    echo ""
  fi
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

    printf '  %-24s ' "installed renderer:"
    if [[ -x "$HOME/.claude/craft-statusline.sh" ]]; then
      echo "$HOME/.claude/craft-statusline.sh"
    else
      echo "not installed at ~/.claude/"
    fi

    printf '  %-24s ' "skill:"
    if [[ -f "$HOME/.claude/skills/craft-statusline/SKILL.md" ]]; then
      echo "installed"
    else
      echo "not installed"
    fi

    printf '  %-24s ' "commands symlink:"
    if [[ -L "$HOME/.claude/commands/craft-statusline.md" ]]; then
      echo "-> $(readlink "$HOME/.claude/commands/craft-statusline.md")"
    elif [[ -e "$HOME/.claude/commands/craft-statusline.md" ]]; then
      echo "file present but not a symlink"
    else
      echo "not present"
    fi

    printf '  %-24s ' "custom fields file:"
    if [[ -f "$HOME/.claude/craft-statusline-custom.sh" ]]; then
      echo "$HOME/.claude/craft-statusline-custom.sh"
    else
      echo "not present (optional)"
    fi

    printf '  %-24s ' "update check:"
    if [[ -f "$VERSION_CHECK_FILE" ]]; then
      latest=$(head -1 "$VERSION_CHECK_FILE" 2>/dev/null || echo "?")
      last_check=$(stat -c %Y "$VERSION_CHECK_FILE" 2>/dev/null || stat -f %m "$VERSION_CHECK_FILE" 2>/dev/null || echo 0)
      age_hours=$(( ($(date +%s) - last_check) / 3600 ))
      echo "latest seen: $latest (checked ${age_hours}h ago)"
    else
      echo "no check yet (will run in background on next render)"
    fi

    echo ""
    echo "  SHOW_* flags (from this script):"
    grep '^SHOW_' "$0" | sed 's/^/    /'
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
activity_exec='\033[38;2;130;200;120m'
activity_think='\033[2;38;2;150;150;150m'
activity_research='\033[38;2;180;140;255m'

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
# Both the context field (for session duration) and the activity field
# (for mtime-based "is Claude active" detection) need the path to the
# most recently modified .jsonl transcript. Resolve it once here.
session_file=""
if [[ -d "$HOME/.claude/projects" ]]; then
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
    c=$(color_for_pct "$ctx")
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
    # Context alert: append ⚠ in red when we cross CONTEXT_ALERT_AT,
    # so a full-context session is visually obvious before auto-compact.
    alert=""
    if [[ "$SHOW_CONTEXT_ALERT" == "true" ]]; then
      ctx_int=${ctx%%.*}
      if [[ "$ctx_int" =~ ^[0-9]+$ ]] && (( ctx_int >= CONTEXT_ALERT_AT )); then
        alert=" ${red}⚠${rst}"
      fi
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

# ── Activity indicator (hook-free, driven by session.jsonl mtime) ─
# Claude Code appends to the active session transcript every time it
# emits text, calls a tool, or receives a tool result. If the file was
# written in the last ACTIVITY_LIVE_WINDOW_SECS seconds, Claude is
# currently active. The last tool_use event in the transcript tells us
# whether that activity is executing a tool, researching via a subagent
# (Task), or pure thinking (no recent tool). No hooks, no settings.json
# writes, no helper script.
if [[ "$SHOW_ACTIVITY" == "true" && -n "${session_file:-}" ]]; then
  act_mtime=$(stat -c %Y "$session_file" 2>/dev/null || stat -f %m "$session_file" 2>/dev/null || echo 0)
  act_idle=$(( $(date +%s) - act_mtime ))
  if (( act_idle >= 0 && act_idle < ACTIVITY_LIVE_WINDOW_SECS )); then
    # A fresh mtime alone is not enough — Claude Code also writes
    # transcript events (attachment, file-history-snapshot, custom-title)
    # after an assistant turn ends. So the absolute last line is often
    # metadata, not an assistant message. Walk back to the most recent
    # assistant event and inspect its stop_reason:
    #   stop_reason in {end_turn,max_tokens,...}  -> done, no indicator
    #   stop_reason == "tool_use"                 -> executing (tool)
    #   no stop_reason yet                        -> streaming, thinking
    last_tool=$(tail -100 "$session_file" 2>/dev/null | "$JQ" -s -r '
      map(select(.type == "assistant")) | .[-1] as $a
      | if $a == null then ""
        else
          ($a.message.stop_reason // null) as $sr
          | if $sr != null and $sr != "tool_use" then "DONE"
            elif ($a.message.content | type) == "array" and ($a.message.content | length) > 0 then
              $a.message.content[-1] as $last
              | if ($last.type // empty) == "tool_use" and ($last.name | type) == "string" then $last.name
                else "" end
            else "" end
        end
    ' 2>/dev/null)
    # Whitelist the tool name so a pathological entry cannot reach printf %b
    if [[ "$last_tool" != "DONE" ]] && [[ ${#last_tool} -gt $MAX_ACTIVITY_LEN || ! "$last_tool" =~ ^[A-Za-z0-9_.-]*$ ]]; then
      last_tool=""
    fi
    # Dot + state label share the activity color; the tool name in
    # parens stays dim as a secondary detail.
    case "${last_tool:-}" in
      DONE)
        ;;
      "")
        parts+=("${activity_think}● thinking${rst}")
        ;;
      Task)
        parts+=("${activity_research}● researching${rst}")
        ;;
      mcp__*)
        short_tool="${last_tool##*__}"
        parts+=("${activity_exec}● executing${rst} ${dim}(${short_tool})${rst}")
        ;;
      *)
        parts+=("${activity_exec}● executing${rst} ${dim}(${last_tool})${rst}")
        ;;
    esac
  fi
fi

# ── Update check (non-blocking) ──────────────────────────────────
# Fire-and-forget background curl refreshes the cached latest-version
# file at most once per 24h. The current render reads whatever is
# already in the cache; a new version discovered this run surfaces
# on the next render.
if [[ "$SHOW_UPDATE" == "true" ]]; then
  need_check=false
  if [[ ! -f "$VERSION_CHECK_FILE" ]]; then
    need_check=true
  else
    last_check=$(stat -c %Y "$VERSION_CHECK_FILE" 2>/dev/null || stat -f %m "$VERSION_CHECK_FILE" 2>/dev/null || echo 0)
    if (( $(date +%s) - last_check > VERSION_CHECK_INTERVAL_SECS )); then
      need_check=true
    fi
  fi
  if $need_check; then
    mkdir -p "$HOME/.claude/state" 2>/dev/null
    (
      latest=$(curl -fsSL -m 3 "$VERSION_CHECK_URL" 2>/dev/null \
               | grep -m1 '^VERSION=' \
               | cut -d'"' -f2)
      if [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s\n' "$latest" > "$VERSION_CHECK_FILE"
      else
        # Touch the file anyway to prevent retry storms on repeated failures.
        touch "$VERSION_CHECK_FILE"
      fi
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi

  if [[ -s "$VERSION_CHECK_FILE" ]]; then
    latest_version=$(head -1 "$VERSION_CHECK_FILE" 2>/dev/null || echo "")
    if [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$latest_version" != "$VERSION" ]]; then
      highest=$(printf '%s\n%s\n' "$VERSION" "$latest_version" | sort -V | tail -1)
      if [[ "$highest" == "$latest_version" ]]; then
        parts+=("${yellow}⬆ v${latest_version}${rst}")
      fi
    fi
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
