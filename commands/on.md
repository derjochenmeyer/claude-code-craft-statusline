---
description: Enable a craft-statusline field. Usage: /craft-statusline:on cost
allowed-tools: Bash, Read
---

# craft-statusline:on

Enable one of the craft-statusline boolean options. The argument is the field name.

## Valid arguments

`model`, `branch`, `context`, `context_alert`, `rate_limits`, `cost`, `color`

## Steps

### 1. Validate the argument

Argument is `$ARGUMENTS`. If empty or not in the list above, report:

```
Usage: /craft-statusline:on <field>
Valid fields: model, branch, context, context_alert, rate_limits, cost, color
```

Stop.

```bash
case "$ARGUMENTS" in
  model|branch|context|context_alert|rate_limits|cost|color) ;;
  *)
    echo "Usage: /craft-statusline:on <field>"
    echo "Valid fields: model, branch, context, context_alert, rate_limits, cost, color"
    exit 1
    ;;
esac
```

### 2. Map to option key

Prepend `show_` (e.g. `cost` → `show_cost`).

### 3. Patch ~/.claude/settings.json

User-config values for plugins live under `pluginConfigs.<plugin-id>.options`.

```bash
key="show_$ARGUMENTS"
existing=~/.claude/settings.json
[[ -f "$existing" ]] || echo '{}' > "$existing"
tmp=$(mktemp)
jq --arg k "$key" '
  .pluginConfigs //= {}
  | .pluginConfigs["craft-statusline"] //= {}
  | .pluginConfigs["craft-statusline"].options //= {}
  | .pluginConfigs["craft-statusline"].options[$k] = true
' "$existing" > "$tmp" && mv "$tmp" "$existing"
```

### 4. Confirm

```
Enabled: show_<field>
The change takes effect on the next status line refresh.
```
