---
name: craft-statusline
version: 1.1.0
description: Configure the craft status bar. Shows annotated field preview, detects existing setup, and auto-installs or auto-activates if needed, all in one response. Asks only when another statusline script would be replaced (destructive case).
allowed-tools: Read, Write, Bash
---

# craft-statusline

One-shot status bar configurator. Completes in a single response. Auto-installs when nothing is set up; auto-activates when installed-but-inactive. The only case that requires user action is State D (a different statusline is already active), destructive and must be explicit.

IMPORTANT: Checks `jq` availability before install. If `jq` is missing, reports it and stops instead of installing a silently-broken statusline.

## Usage

```
/craft-statusline                        show all fields with explanations and current state
/craft-statusline install                install and activate (also switches from existing scripts)
/craft-statusline install cost activity  install and configure fields in one go
/craft-statusline cost activity          toggle fields on/off
/craft-statusline on activity            enable a specific field
/craft-statusline off cost               disable a specific field
```

Field names: `model`, `effort`, `context`, `rate`, `cost`, `branch`, `activity`

---

## Step 1: Detect current state

First, check jq is available (hard dependency, PATH or `~/.claude/bin/` fallback):

```bash
{ command -v jq >/dev/null 2>&1 || [[ -x "$HOME/.claude/bin/jq" ]]; } || echo "JQ_MISSING"
```

If `JQ_MISSING`: stop with this message and do nothing else:

```
jq is required for craft-statusline (parses Claude Code's JSON input).
Without jq, the statusline produces silent empty output.

Easiest fix: re-run the installer, it installs jq automatically.
  curl -fsSL https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main/install.sh | bash

Or install manually:
  brew install jq                                     # macOS with Homebrew
  See https://jqlang.github.io/jq/download/ for other platforms

Then re-run /craft-statusline.
```

If jq is present, detect state:

```bash
test -f ~/.claude/craft-statusline.sh && echo "CRAFT_INSTALLED" || echo "CRAFT_MISSING"
jq -r '.statusLine.command // "NOT_CONFIGURED"' ~/.claude/settings.json 2>/dev/null
```

Classify into one of four states:

| State | Condition |
|-------|-----------|
| A: Not set up | craft-statusline.sh missing, nothing configured |
| B: Active | craft-statusline.sh installed AND settings.json points to it |
| C: Installed but inactive | craft-statusline.sh installed, settings.json points elsewhere or empty |
| D: Different script active | settings.json points to another script, craft not installed |

---

## Step 2: Execute based on state and args

### No args

First print the structural preview and field table. Be explicit that this preview shows structure only, and that the real statusline (with colors and the git badge block) is rendered at the bottom of the terminal by Claude Code.

```
Structural preview (plain text, actual rendering is colored):
Sonnet 4.6▸normal │ main ✔ │ ctx▸30% │ 5h▸29% │ 7d▸30% │ cost▸0.43$ │ ● thinking
```

| Field | Example | Description |
|-------|---------|-------------|
| model | `Sonnet 4.6` | Current model name (shortened) |
| effort | `▸normal` | Effort level from settings.json, rendered inline after the model |
| branch | `main ✔` | Git branch as a colored badge plus status (✔/⇡N/⇣N/+N/!N/?N/⚠N). On by default |
| context | `ctx▸30%` | Context window used so far in this session. A red `⚠` appears when usage crosses `CONTEXT_ALERT_AT` (default 85%). |
| rate | `5h▸29%` `7d▸30%` | Token usage in the rolling 5h and 7d windows |
| cost | `cost▸0.43$` | **API billing only.** Session cost in USD at pay-per-token rates. On flat-rate plans (Pro/Team/Max) this is a hypothetical number, not your actual invoice. Off by default. |
| activity | `● thinking` / `● executing (Bash)` / `● researching` | Hook-free activity indicator driven by session-transcript mtime. Shows `thinking` (Claude generating text), `executing (tool-name)` (Claude calling a tool), or `researching` (Claude dispatched a subagent). Disappears when the transcript has not been written to in the last 10 seconds. |

An `⬆ vX.Y.Z` badge appears automatically when a newer version of the repo is available (checked at most once per 24h, non-blocking background fetch).

Git branch symbols (appended inside the branch badge):

| Symbol | Meaning |
|--------|---------|
| `✔`    | Clean working tree |
| `⇡N`   | N commits ahead of remote (unpushed) |
| `⇣N`   | N commits behind remote (remote has moved) |
| `*N`   | N stashed changesets |
| `+N`   | N staged files ready to commit |
| `!N`   | N unstaged modifications |
| `?N`   | N untracked files |
| `⚠N`   | N merge conflicts |

Symbols combine (e.g. `main ⇡2 +1 !3 ?1`). The badge color stays readable on dark and light terminals.

Custom fields from `~/.claude/craft-statusline-custom.sh` render after the built-ins. See the README for the authoring pattern.

Then act based on state:

**State A, nothing configured:** auto-install. Run the `install` flow below. End with:

```
craft-statusline installed and activated. Restart Claude Code to see it.
```

**State B, craft-statusline is active:**

Run `grep "^SHOW_" ~/.claude/craft-statusline.sh` to read actual values. Map `true` → `[x]`, anything else → `[ ]`. List the fields in render order:

```
craft-statusline is active.
Fields: model [?]  effort [?]  branch [?]  context [?]  rate [?]  cost [?]  activity [?]

Toggle fields with: /craft-statusline <field>  (e.g. /craft-statusline cost)
```

**State C, craft-statusline installed but not yet active:** auto-activate.

Update settings.json to point at `~/.claude/craft-statusline.sh`. Report:

```
craft-statusline activated. Restart Claude Code to see it.
```

**State D, a different script is active, craft not installed:**

Do NOT auto-replace, this is destructive. Report:

```
A different statusline script is already active:
  [current command from settings.json]

craft-statusline is not installed. To replace the existing script with
craft-statusline, run: /craft-statusline install
```

The user must explicitly run `install` to confirm the replacement.

---

### `install` arg

1. Copy craft-statusline.sh to ~/.claude/craft-statusline.sh (fetch from https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main/craft-statusline.sh).
2. `chmod +x ~/.claude/craft-statusline.sh`
3. Note existing statusLine.command from settings.json (if any).
4. Update settings.json:

   ```bash
   tmp=$(mktemp) && jq '.statusLine = {"type": "command", "command": "~/.claude/craft-statusline.sh", "refreshInterval": 5000}' \
     ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json
   ```
5. Report accordingly (`Replaced [old]` or `installed and activated`).
6. If field args also provided, apply them.
7. Show current config and live preview.

---

### Field args (no `install` keyword)

Field-to-variable mapping:

| Arg | Variable |
|-----|----------|
| model | SHOW_MODEL |
| effort | SHOW_EFFORT |
| context | SHOW_CONTEXT |
| rate | SHOW_RATE_LIMITS |
| cost | SHOW_COST |
| branch | SHOW_BRANCH |
| activity | SHOW_ACTIVITY |

For each field, read current value and flip it. Use `perl -i -pe` (portable across GNU and BSD sed):

```bash
current=$(grep "^SHOW_MODEL=" ~/.claude/craft-statusline.sh | cut -d= -f2)
new=$([[ "$current" == "true" ]] && echo "false" || echo "true")
perl -i -pe "s/^SHOW_MODEL=.*/SHOW_MODEL=$new/" ~/.claude/craft-statusline.sh
```

If `on` prefix: force to `true`. If `off` prefix: force to `false`.

If craft-statusline.sh is not installed: report it and suggest `/craft-statusline install` first.

---

## Step 3: Config summary and live preview (after any action)

```
craft-statusline: [active | installed but inactive | not installed]
settings.json: [pointing to craft | pointing to other script | not configured]

  [x] model    [x] effort    [x] branch    [x] context    [x] rate    [ ] cost    [x] activity

Preview:
```

Then run:

```bash
echo "{\"model\":{\"display_name\":\"Sonnet 4.6\"},\"context_window\":{\"used_percentage\":42},\"rate_limits\":{\"five_hour\":{\"used_percentage\":15,\"resets_at\":$(( $(date +%s) + 3600 ))},\"seven_day\":{\"used_percentage\":30}},\"cost\":{\"total_cost_usd\":0.85}}" \
  | bash ~/.claude/craft-statusline.sh
```

If cost is disabled, the cost field will not appear. If the script is not installed, skip the preview.
