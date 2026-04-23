---
description: Show current craft-statusline configuration and a live render preview.
allowed-tools: Bash, Read
---

# craft-statusline:status

Report the active craft-statusline configuration, then render a live preview.

## Steps

### 1. Read the active configuration

User-config values live in `~/.claude/settings.json` under `pluginConfigs."craft-statusline".options.*`. Defaults from `plugin.json` apply when an option is unset.

```bash
jq -r '.pluginConfigs["craft-statusline"].options // {}' ~/.claude/settings.json 2>/dev/null
```

### 2. Render a tabular summary

For each known option, show whether it is `[x]` (enabled) or `[ ]` (disabled) — falling back to the default when unset:

| Field | Default | Notes |
|---|---|---|
| `show_model` | true | Model + effort badge |
| `show_branch` | true | Git branch with state-aware palette |
| `show_context` | true | Context usage with traffic light |
| `show_context_alert` | true | ⚠ symbol on yellow/red |
| `show_rate_limits` | true | 5h / 7d windows |
| `show_cost` | false | API cost (only meaningful on pay-per-token plans) |
| `show_color` | true | ANSI color globally |

Plus thresholds: `context_alert_at` (red percent), `context_degrade_at_tokens` (yellow tokens).

### 3. Live preview

Run the renderer with a sample payload so the user sees the actual ANSI output. Note that ANSI escapes may not render in this output panel — they will look right in the actual status line at the bottom of Claude Code.

```bash
echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":42,"current_usage":{"input_tokens":1,"cache_creation_input_tokens":1000,"cache_read_input_tokens":150000}},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":30}},"cost":{"total_cost_usd":0.43}}' \
  | bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/craft-statusline-marketplace}/scripts/craft-statusline.sh"
```

The `${CLAUDE_PLUGIN_ROOT:-...}` fallback mirrors the pattern in `commands/install.md` and works around [anthropics/claude-code#52079](https://github.com/anthropics/claude-code/issues/52079). Remove the fallback here once the upstream fix ships.

### 4. Report active settings.json wiring

```bash
jq -r '.statusLine // "not configured"' ~/.claude/settings.json 2>/dev/null
```

If `statusLine.command` does not point at craft-statusline, remind the user to run `/craft-statusline:install`.
