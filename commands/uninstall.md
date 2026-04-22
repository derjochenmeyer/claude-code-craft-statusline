---
description: Remove craft-statusline from ~/.claude/settings.json (does not uninstall the plugin itself).
allowed-tools: Bash, Read
---

# craft-statusline:uninstall

Disable the craft-statusline rendering by removing the `statusLine` block from `~/.claude/settings.json`. The plugin itself stays installed; use `/plugin uninstall craft-statusline` if you want it gone entirely.

## Steps

### 1. Confirm what's currently set

```bash
jq -r '.statusLine.command // "NONE"' ~/.claude/settings.json 2>/dev/null
```

If the result does not contain `craft-statusline.sh`, report:

```
craft-statusline is not the active status line. Nothing to remove.
Current value: [whatever was returned]
```

Stop.

### 2. Remove the statusLine block

```bash
tmp=$(mktemp)
jq 'del(.statusLine)' ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json
```

### 3. Report

```
craft-statusline removed from ~/.claude/settings.json.
The plugin is still installed (run `/plugin uninstall craft-statusline` to remove it completely).
Restart Claude Code to drop the status line from the UI.
```
