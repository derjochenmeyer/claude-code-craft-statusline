---
name: Bug report
about: Something in the statusline, wizard, or installer isn't working
title: ''
labels: bug
assignees: ''
---

**What happened**
A short description. What did you do, what did you expect, what did you see?

**Environment**
- OS: (e.g. macOS 14.6, Ubuntu 24.04, Windows 11 + WSL2 Ubuntu 24.04)
- Shell: (output of `echo $BASH_VERSION`)
- jq: (output of `jq --version` or `~/.claude/bin/jq --version`)
- Claude Code version: (check in Claude Code itself)
- Installed via: `install.sh` / `/craft-statusline install` / manual

**craft-statusline.sh config**
Paste the top of `~/.claude/craft-statusline.sh` (the `SHOW_*` lines):

```
SHOW_MODEL=?
SHOW_EFFORT=?
...
```

**Rendered output**
Run this to capture what the statusline actually produces:

```bash
echo '{"model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":30}},"cost":{"total_cost_usd":0.85}}' | bash ~/.claude/craft-statusline.sh
```

Paste the output.

**Additional context**
Error messages, screenshots, anything else relevant.
