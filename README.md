# A carefully crafted Claude Code statusline

![Version](https://img.shields.io/badge/version-1.2.0-blue) ![License: MIT](https://img.shields.io/badge/License-MIT-yellow) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey) ![Shell](https://img.shields.io/badge/shell-bash-green) ![Font](https://img.shields.io/badge/fonts-none%20required-brightgreen)

A carefully crafted [Claude Code](https://docs.anthropic.com/en/docs/claude-code) statusline, written in bash, with minimal design and requirements. Shows model, effort-level, git branch and status, session context, rate limits, session cost and activity.

![claude-code-craft-statusline preview](https://github.com/user-attachments/assets/3b23d36a-26ee-482a-8fe5-ff221274f6a6)

No Node, no Python, no Nerd Fonts. Only requires jq (small command-line JSON parser, auto-installed during setup).

Colors shift with how much of the window you've used. Rate limits run green → yellow → orange → red by percentage. The context field uses a traffic light that leans on absolute tokens, not just percent: green while you're safely below the "context rot" zone, yellow with a `⚠` once the session crosses 400k tokens (where model recall measurably degrades on 1M-window models), red with a `⚠` once the window is 85% full and auto-compact is imminent. Session cost is off by default, and stays that way for flat-rate plans where it would be misleading.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main/install.sh | bash
```

The installer:

1. Ensures `jq` is available (PATH → Homebrew → direct static binary to `~/.claude/bin/jq`, no sudo, no PATH edits). The direct-download path pins a specific jq version and verifies it against a SHA256 checksum hardcoded in `install.sh`, not fetched from the same host.
2. Installs `craft-statusline.sh` and `craft-statusline-wizard.sh` to `~/.claude/`.
3. Installs the `craft-statusline` skill to `~/.claude/skills/` and symlinks it as a global slash command.
4. Activates the statusline in `~/.claude/settings.json`, but only if nothing else is set. An existing statusline is reported, never overwritten silently.

Restart Claude Code after install. One command, full feature set.

### Inspected install

If piping into `bash` makes you twitch (reasonable), do it in two steps:

```bash
curl -fsSL -o /tmp/craft-install.sh https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main/install.sh
less /tmp/craft-install.sh   # or $EDITOR, shasum, whatever you want
bash /tmp/craft-install.sh
```

The installer is ~250 lines of commented shell. The jq SHA256 constants, checksum logic, and quarantine handling are all inspectable before anything runs.

### Verifying the install

```bash
bash ~/.claude/craft-statusline.sh --doctor
```

Reports which `jq` was found, whether `settings.json` is wired up, the current refresh interval, and the current `SHOW_*` flags. Useful before opening an issue.

---

## Configure

Three ways. Pick one.

### Inside Claude Code

```
/craft-statusline                        show all fields and current state
/craft-statusline cost activity          toggle those two on/off
/craft-statusline on activity            force enable
/craft-statusline off cost               force disable
/craft-statusline install                (re)install and activate
/craft-statusline install cost activity  install and configure fields in one go
```

Field names: `model`, `effort`, `context`, `rate`, `cost`, `branch`, `activity`.

### Interactive wizard

```bash
bash ~/.claude/craft-statusline-wizard.sh
```

Walks through every field with the current value, shows a preview, applies on confirm.

### Edit the file

```bash
$EDITOR ~/.claude/craft-statusline.sh
```

The `SHOW_*` flags sit at the top. Advanced toggles (`CONTEXT_ALERT_AT`, `ACTIVITY_LIVE_WINDOW_SECS`, `SHOW_UPDATE`, `SHOW_CONTEXT_ALERT`) live there too. Edits take effect on the next statusline refresh.

---

## Fields

| Field | Example | What it tells you |
|-------|---------|-------------------|
| Model + effort | `Sonnet 4.6▸normal` | Which model and effort level you're running on. Useful when you switch between projects and want to confirm you're not burning high-effort tokens on a quick task. |
| Git branch | `main ✔` | Live branch status. Uncommitted changes, staged files, stashes, and remote drift visible without leaving the editor. |
| Context | `ctx▸42% (2h34m)` | Context window usage and session age. Three-stage traffic light: green while tokens < `CONTEXT_DEGRADE_AT_TOKENS` (default 400k); yellow `⚠` once absolute tokens cross that (model recall degrades noticeably on long contexts, regardless of how much headroom the 1M window still has); red `⚠` once percentage ≥ `CONTEXT_ALERT_AT` (default 85%) and auto-compact is imminent. |
| Rate limits | `5h▸12% │ 7d▸8%` | Rolling token usage across the last 5 hours and 7 days. Color shifts from green to yellow to red as you approach limits, before you hit them, not after. |
| Session cost | `cost▸0.43$` | **API billing only.** Session cost in USD at pay-per-token rates. On flat-rate plans (Pro, Team, Max) this is a hypothetical equivalent, not your actual invoice. Off by default. |
| Activity indicator | `● thinking` / `● executing (Bash)` / `● researching` | What Claude is doing right now. Hook-free: driven by the mtime and last tool_use event of the active session transcript. Shows one of three states: generating text (`thinking`), running a concrete tool (`executing (Tool)`), or delegating to a subagent (`researching`). Disappears when the transcript has been idle for 10 seconds. |

### Update checker

An `⬆ v1.2.3` badge appears automatically when a newer release is available on the repo. The check runs in the background at most once per 24 hours, uses a 3-second timeout, and never blocks the render. Disable with `SHOW_UPDATE=false`.

### A note on `cost` and flat-rate plans

If you are on **Pro, Team, or Max** (flat monthly subscription), `cost` is off by default and you should leave it off. It reflects the API-equivalent token cost, not your actual invoice. Your real constraints on those plans are the 5-hour and 7-day rate limits shown in the `rate` field.

### Git branch at a glance

Since v1.1.0 the branch badge is also color-aware: it picks its color from the dominant git signal, so you can read the state of the working tree at a glance without parsing the symbols.

![git state badges](https://github.com/user-attachments/assets/4887886c-609b-4bf0-bcac-d4a31c6bc5ba)

| Symbol | Meaning | Why it matters |
|--------|---------|----------------|
| `✔` | Clean working tree | Nothing uncommitted, safe to switch context or wrap up the session |
| `⇡N` | N commits ahead of remote | Work that hasn't been pushed yet |
| `⇣N` | N commits behind remote | Remote has moved on. Pull before your next push |
| `*N` | N stashed changesets | Shelved work you might have forgotten about |
| `+N` | N staged files | Ready to commit, in case Claude staged something while you were focused elsewhere |
| `!N` | N unstaged modifications | Work in progress, still loose |
| `?N` | N untracked files | New files Claude created that aren't tracked yet |
| `⚠N` | N merge conflicts | Needs attention before anything else |

---

## Manual activation

The installer wires the statusline into `~/.claude/settings.json` automatically. If you want to wire it up by hand (or migrate from another script), add this block:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/craft-statusline.sh",
  "refreshInterval": 5000
}
```

---

## Requirements

| What | Why | Installer behavior |
|------|-----|-------------------|
| **Claude Code** | The statusline reads its JSON input from the harness | Install Claude Code yourself first |
| **bash 3.2+** | Everything here is shell. macOS ships 3.2, Linux has 4+ | Comes with your OS |
| **jq** | Parses Claude Code's JSON input | Installed automatically: Homebrew first, then a pinned static binary to `~/.claude/bin/jq` with SHA256 verification |
| **git** | Only needed if `SHOW_BRANCH=true` | Pre-installed on Linux; on macOS installed on first `git` call (Xcode CLT) |

Nothing else. No Nerd Fonts, no Node, no Python. Windows: use WSL.

---

## Custom fields

Drop a file at `~/.claude/craft-statusline-custom.sh`. The statusline sources it (never eval) and calls the functions you list in `CUSTOM_FIELDS`:

```bash
# ~/.claude/craft-statusline-custom.sh
CUSTOM_FIELDS="field_ticket field_env field_npm"

# Linear / Jira ticket from a local file in the current repo
field_ticket() {
  local t
  t=$(cat .current-ticket 2>/dev/null) || return
  [[ -z "$t" ]] && return
  printf '\033[38;2;200;100;200mticket▸%s\033[0m' "$t"
}

# Deploy environment badge from an env var, colored by severity
field_env() {
  case "${DEPLOY_ENV:-}" in
    prod)  printf '\033[48;2;200;50;50m PROD \033[0m' ;;
    stage) printf '\033[48;2;200;150;50m STAGE \033[0m' ;;
    dev)   printf '\033[38;2;100;200;100m[dev]\033[0m' ;;
  esac
}

# npm version from package.json, if in a Node project
field_npm() {
  [[ -f package.json ]] || return
  local v
  v=$(jq -r '.version // empty' package.json 2>/dev/null) || return
  [[ -n "$v" ]] && printf '\033[2mnpm %s\033[0m' "$v"
}
```

Rules the renderer enforces for safety:

- The file is **sourced**, not eval'd. Write it as real bash.
- Only functions matching `^field_[A-Za-z0-9_]+$` are called. Unknown names in `CUSTOM_FIELDS` are skipped.
- Each function runs in a subshell with a 2-second rendertime cap, so a crash or hang in one custom field cannot take down the renderer or stall the refresh.
- Empty output is treated as "do not render this field this refresh".

Custom fields render after all built-ins. Order within the custom block follows the order of `CUSTOM_FIELDS`.

---

## Companion tool

For deeper token analytics, burn-rate history, and session-level cost breakdowns, [ccusage](https://github.com/ryoppippi/ccusage) parses the same transcript files this statusline reads and produces a rich report. Pairs well.

---

## Troubleshooting

**The statusline is blank.** `jq` is not on the PATH and the fallback at `~/.claude/bin/jq` is missing or broken. Re-run the installer, or `brew install jq`, or download a binary from https://jqlang.github.io/jq/download/.

**Values look stale by a few seconds.** The statusline refreshes every 5 seconds (`refreshInterval: 5000` in `~/.claude/settings.json`). Claude Code debounces updates to ~300ms and only re-invokes the script on new assistant messages, permission mode changes, and vim mode toggles; pure thinking stretches may go longer between refreshes. Each refresh costs roughly 80-150ms on a modern machine.

**Effort is not shown.** The effort field reads `.effortLevel` from `~/.claude/settings.json`. Set it there (for example `"effortLevel": "normal"`) or disable the field with `/craft-statusline off effort`.

**Git branch badge never appears.** The badge only renders in directories that are actually inside a git working tree. If you are in a non-git folder, the branch field is skipped silently.

**Activity indicator does not show.** The activity indicator needs a recent session transcript in `~/.claude/projects/`. It surfaces when the transcript file has been modified in the last 10 seconds (`ACTIVITY_LIVE_WINDOW_SECS`). A brand-new Claude Code session that has not produced a transcript yet, or a long idle moment, hides the indicator.

**Installer reports "another statusline is active".** That is the safety net: an existing `statusLine.command` in `settings.json` is never silently replaced. Run `/craft-statusline install` inside Claude Code to confirm the switch explicitly.

---

## Uninstall

```bash
# 1. Remove the scripts and any timestamped backups the installer left behind
rm -f ~/.claude/craft-statusline.sh ~/.claude/craft-statusline.sh.bak.* \
      ~/.claude/craft-statusline-wizard.sh

# 2. Remove the skill and the global slash-command symlink
rm -rf ~/.claude/skills/craft-statusline
rm -f  ~/.claude/commands/craft-statusline.md

# 3. Unregister from settings.json (leaves the file valid JSON)
tmp=$(mktemp) && jq 'del(.statusLine)' ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json

# 4. Optional: remove the custom fields file, the update-check cache, and the
#    installer-managed jq binary
rm -f ~/.claude/craft-statusline-custom.sh
rm -f ~/.claude/state/version-check
rm -f ~/.claude/bin/jq
```

Restart Claude Code. The statusline is gone.

---

## License

MIT. See [LICENSE](LICENSE).

Author Jochen Meyer (X → [@derjochenmeyer](https://x.com/derjochenmeyer))
