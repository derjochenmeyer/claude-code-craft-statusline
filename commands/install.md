---
description: Wire craft-statusline into ~/.claude/settings.json so Claude Code renders it.
allowed-tools: Bash, Read
---

# craft-statusline:install

Install craft-statusline as the active status line.

## Step 1: Check jq

```bash
command -v jq >/dev/null 2>&1 || echo "JQ_MISSING"
```

If `JQ_MISSING`, stop and show:

```
jq is required for craft-statusline (parses Claude Code's JSON input).
Install it:
  macOS:   brew install jq
  Debian:  sudo apt install jq
  Other:   https://jqlang.github.io/jq/download/

Then re-run /craft-statusline:install.
```

Do not proceed.

## Step 2: Inspect existing statusLine

```bash
jq -r '.statusLine.command // "NONE"' ~/.claude/settings.json 2>/dev/null
```

Outcomes:

- `NONE`, file missing, or `statusLine` absent. proceed to Step 3.
- Output mentions `craft-statusline.sh`. already installed, jump to Step 4.
- Anything else. report it and stop, unless `$ARGUMENTS` contains `force`:
  ```
  A different statusline script is already active:
    [current command]

  Run /craft-statusline:install force to replace it.
  ```

## Step 3: Write settings.json

**CRITICAL:** Write the literal string `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/craft-statusline-marketplace}/scripts/craft-statusline.sh` into `settings.json`. Do NOT substitute the variable references with the expanded absolute path you may see in the rendered version of this skill. Both tokens must survive into the JSON verbatim so the line keeps working across plugin updates.

Pattern explained: Claude Code's statusline lives in `settings.json` outside the plugin system, so the statusline subprocess does not receive `${CLAUDE_PLUGIN_ROOT}`. This is expected behaviour, not a bug, and was confirmed by Anthropic in [anthropics/claude-code#52079](https://github.com/anthropics/claude-code/issues/52079) (closed as "expected existing behavior"). The POSIX default-expansion `${CLAUDE_PLUGIN_ROOT:-…}` falls back to the marketplace clone path, which is version-stable. If Anthropic later integrates statusline into the plugin system, the same line will transparently pick up the official plugin root with no further action.

Use this jq invocation. The single-quoted filter prevents shell expansion of `$CLAUDE_PLUGIN_ROOT` and `$HOME`, so both literal tokens survive into the JSON:

```bash
mkdir -p ~/.claude
existing=~/.claude/settings.json
[[ -f "$existing" ]] || echo '{}' > "$existing"
tmp=$(mktemp)
jq '.statusLine = {
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/craft-statusline-marketplace}/scripts/craft-statusline.sh",
  "refreshInterval": 1000
}' "$existing" > "$tmp" && mv "$tmp" "$existing"
```

Verify both literal tokens landed in the file (this catches accidental substitution):

```bash
grep -F '${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/craft-statusline-marketplace}' ~/.claude/settings.json >/dev/null \
  && echo "OK: literal expansion pattern preserved" \
  || echo "FAIL: settings.json contains the expanded path. Re-run install."
```

## Step 4: Report

```
craft-statusline activated.

Restart Claude Code (or open a new session) to see it render at the bottom of the screen.

Toggle fields with:
  /craft-statusline:on cost
  /craft-statusline:off branch
  /craft-statusline:status

Defaults: model + branch + context + rate-limits on, cost off.
```
