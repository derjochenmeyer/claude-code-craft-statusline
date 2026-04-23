---
description: Disable a craft-statusline field. Usage: /craft-statusline:off branch
allowed-tools: Bash, Read
---

# craft-statusline:off

Disable one of the craft-statusline boolean options. The argument is the field name.

## Valid arguments

`model`, `branch`, `context`, `context_alert`, `rate_limits`, `cost`, `color`

## Steps

### 1. Validate the argument

Argument is `$ARGUMENTS`. If empty or not in the list above:

```
Usage: /craft-statusline:off <field>
Valid fields: model, branch, context, context_alert, rate_limits, cost, color
```

Stop.

```bash
case "$ARGUMENTS" in
  model|branch|context|context_alert|rate_limits|cost|color) ;;
  *)
    echo "Usage: /craft-statusline:off <field>"
    echo "Valid fields: model, branch, context, context_alert, rate_limits, cost, color"
    exit 1
    ;;
esac
```

### 2. Patch ~/.claude/settings.json

```bash
key="show_$ARGUMENTS"
existing=~/.claude/settings.json
[[ -f "$existing" ]] || echo '{}' > "$existing"
tmp=$(mktemp)
jq --arg k "$key" '
  .pluginConfigs //= {}
  | .pluginConfigs["craft-statusline"] //= {}
  | .pluginConfigs["craft-statusline"].options //= {}
  | .pluginConfigs["craft-statusline"].options[$k] = false
' "$existing" > "$tmp" && mv "$tmp" "$existing"
```

### 3. Confirm

```
Disabled: show_<field>
The change takes effect on the next status line refresh.
```
