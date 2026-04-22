# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A bash statusline for Claude Code, shipped as an **official Claude Code plugin**. Zero Node, zero Python, no Nerd Fonts. The only hard runtime dependency is `jq`. Installation flows entirely through the plugin manager (`/plugin marketplace add …`, `/plugin install craft-statusline`). The renderer itself is a single bash script that consumes Claude Code's statusline JSON on stdin and prints an ANSI-colored line.

## Commands

```bash
# Install the plugin locally for development (from a clone of this repo)
claude --plugin-dir ./

# Manual render test. Pipe fake Claude Code JSON into the renderer
echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":42,"current_usage":{"input_tokens":1,"cache_creation_input_tokens":1000,"cache_read_input_tokens":150000}},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":30}},"cost":{"total_cost_usd":0.85}}' \
  | bash scripts/craft-statusline.sh

# Environment diagnostic
bash scripts/craft-statusline.sh --doctor

# Version check
bash scripts/craft-statusline.sh --version

# Run the test suite (requires bats-core)
bats tests/

# Run shellcheck (CI runs this on every push + PR)
shellcheck scripts/craft-statusline.sh
```

## Architecture

Plugin-shaped repository. Three functional areas:

- **`.claude-plugin/plugin.json`**: the manifest. Declares the plugin name, version, author, repository URL, and a `userConfig` block that enumerates every tunable (SHOW_* booleans, thresholds). Values entered by the user are exported to the renderer as `CLAUDE_PLUGIN_OPTION_<KEY>` environment variables and persisted in `~/.claude/settings.json` under `pluginConfigs."craft-statusline".options.*`.

- **`.claude-plugin/marketplace.json`**: the repo's own plugin marketplace. Users install via `/plugin marketplace add derjochenmeyer/claude-code-craft-statusline` and then `/plugin install craft-statusline`. No Anthropic approval required for this flow.

- **`scripts/craft-statusline.sh`**: the renderer. Reads a single JSON blob on stdin (provided by Claude Code's harness after each assistant message or permission/vim mode change, debounced to 300ms), extracts model / context / rate limits / cost via `jq`, adds git info via `git`, reads the session transcript mtime for the activity indicator, prints one ANSI-colored line. Configuration comes from `CLAUDE_PLUGIN_OPTION_*` env with defaults baked in. User-influenced values (model, effort, branch name, activity tool name) are whitelist-validated and length-capped before they reach `printf %b`.

- **`commands/`**: five slash commands that Claude Code surfaces as `/craft-statusline:install`, `/craft-statusline:uninstall`, `/craft-statusline:status`, `/craft-statusline:on <field>`, `/craft-statusline:off <field>`. They each describe what to do in natural language plus fenced bash blocks; Claude Code executes them via its skill runtime.

User-home layout after plugin install:
```
~/.claude/settings.json
  └─ statusLine.command = "${CLAUDE_PLUGIN_ROOT}/scripts/craft-statusline.sh"
  └─ pluginConfigs."craft-statusline".options.* (SHOW_* + thresholds)
~/.claude/craft-statusline-custom.sh   # optional, user-authored custom fields
```

Plugin files live wherever Claude Code's plugin manager unpacks them. the user never edits them directly, which is why all configuration runs through the slash commands.

## Conventions that matter

- **bash 3.2 compatibility**. macOS still ships 3.2 as `/bin/bash`. Do not use `mapfile`, `readarray`, `declare -A`, `${var,,}`, or `shopt -s globstar`. Use `tr '[:upper:]' '[:lower:]'` for case folding and `awk`/`while read` loops for array building.

- **jq is a hard requirement.** The `/craft-statusline:install` command verifies it up front and points the user at `brew install jq` / `apt install jq` if missing. The renderer itself simply exits cleanly when `jq` is not on PATH. garbled output is worse than no output.

- **Activity is hook-free.** The indicator reads the mtime of the active session transcript in `~/.claude/projects/` and, if fresh, walks the last 100 lines to find the most recent `assistant` event, then reads `stop_reason` and the last content block to decide between thinking / executing / researching / (done → no indicator). No `PreToolUse`/`PostToolUse` hooks, no helper scripts, no writes to `settings.json`.

- **Cost is API-billing only.** On Pro/Team/Max flat-rate plans, `cost` and any derived metrics are hypothetical pay-per-token equivalents, not real invoices. Cost stays off by default. README and command descriptions make this explicit so users do not misread the number.

- **Context traffic light leans on absolute tokens, not percent.** On a 1M-window model, 85% fill is already past the zone where recall measurably degrades. Yellow fires at `current_usage.{input_tokens + cache_creation_input_tokens + cache_read_input_tokens} >= CONTEXT_DEGRADE_AT_TOKENS` (default 400k). Red still fires at `used_percentage >= CONTEXT_ALERT_AT` (default 85%) because auto-compact is a separate concern.

- **Version lives in four places.** `scripts/craft-statusline.sh` (VERSION=), `.claude-plugin/plugin.json` (version), `.claude-plugin/marketplace.json` (plugins[0].version), README badge. When bumping, update all four and add a CHANGELOG entry. Tests assert the first three match.

## Testing

`bats tests/` runs the full suite locally (requires bats-core: `brew install bats-core` on macOS, `apt-get install bats` on Ubuntu). GitHub Actions runs it on both `ubuntu-latest` and `macos-latest` via `.github/workflows/tests.yml`. Shellcheck runs separately via `.github/workflows/shellcheck.yml`. Both gate `main`.

The suite is black-box: no function sourcing, no mock, no harness. Tests pipe sample JSON into the real script and grep the output (stripped of ANSI). That keeps tests honest at the cost of being slow to inspect individual code paths.
