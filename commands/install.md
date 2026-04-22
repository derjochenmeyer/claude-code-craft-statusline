---
description: Wire craft-statusline into ~/.claude/settings.json so Claude Code renders it.
allowed-tools: Bash, Read
---

# craft-statusline:install

Install craft-statusline as the active status line.

## What this does

1. Verifies `jq` is on PATH (hard requirement). If missing, stops and shows the install command for the user's platform.
2. Checks `~/.claude/settings.json` for an existing `statusLine` entry. If a *different* script is already wired up, reports it and stops — the user must run `/craft-statusline:install force` to overwrite, since this is destructive.
3. Writes a `statusLine` block pointing at `${CLAUDE_PLUGIN_ROOT}/scripts/craft-statusline.sh` with `refreshInterval: 1000`.
4. Confirms with the rendered statusline preview.

## Steps

### 1. Check jq

```bash
command -v jq >/dev/null 2>&1 || echo "JQ_MISSING"
```

If `JQ_MISSING`:

```
jq is required for craft-statusline (parses Claude Code's JSON input).
Install it:
  macOS:   brew install jq
  Debian:  sudo apt install jq
  Other:   https://jqlang.github.io/jq/download/

Then re-run /craft-statusline:install.
```

Stop here.

### 2. Inspect existing statusLine

```bash
jq -r '.statusLine.command // "NONE"' ~/.claude/settings.json 2>/dev/null
```

Possible outcomes:

- `NONE`, the file does not exist, or the `statusLine` field is absent → proceed to step 3.
- Output contains `craft-statusline.sh` → already installed, jump to step 4 (reconfirm + show preview).
- Anything else (different script): report it and stop, unless `$ARGUMENTS` contains `force`:

```
A different statusline script is already active:
  [current command]

Run /craft-statusline:install force to replace it.
```

### 3. Write settings.json

The statusLine command must reference `${CLAUDE_PLUGIN_ROOT}` so the path resolves to wherever the plugin manager unpacked craft-statusline.

```bash
mkdir -p ~/.claude
tmp=$(mktemp)
existing=~/.claude/settings.json
[[ -f "$existing" ]] || echo '{}' > "$existing"
jq '.statusLine = {
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/craft-statusline.sh",
  "refreshInterval": 1000
}' "$existing" > "$tmp" && mv "$tmp" "$existing"
```

### 4. Report and preview

Tell the user:

```
craft-statusline activated.

Restart Claude Code (or open a new session) to see it render at the bottom of the screen.

Toggle fields with:
  /craft-statusline:on cost
  /craft-statusline:off branch
  /craft-statusline:status

Defaults: model + branch + context + rate-limits + activity on, cost off.
```
