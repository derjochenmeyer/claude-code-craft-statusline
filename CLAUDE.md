# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A bash statusline for Claude Code. Zero Node, zero Python, no Nerd Fonts. The only hard runtime dependency is `jq`. Ships three user-facing scripts (renderer, wizard, installer) plus a slash-command skill. Nothing is compiled, nothing is packaged.

## Commands

```bash
# Install from a local checkout (skips the GitHub curl path)
bash install.sh --local

# Install from GitHub (what end users run)
curl -fsSL https://raw.githubusercontent.com/derjochenmeyer/claude-code-craft-statusline/main/install.sh | bash

# Interactive configurator. Edits SHOW_* flags in ~/.claude/craft-statusline.sh
bash craft-statusline-wizard.sh

# Manual render test. Pipe fake Claude Code JSON into the renderer
echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":30}},"cost":{"total_cost_usd":0.85}}' \
  | bash craft-statusline.sh

# Environment diagnostic
bash craft-statusline.sh --doctor

# Version check
bash craft-statusline.sh --version
bash craft-statusline-wizard.sh --version
bash install.sh --version

# Run the test suite (requires bats-core: `brew install bats-core` on macOS)
bats tests/

# Run shellcheck (CI runs this on every push + PR)
shellcheck install.sh craft-statusline.sh craft-statusline-wizard.sh
```

## Architecture

Four files, each with one job:

- **`craft-statusline.sh`**: the renderer. Reads a single JSON blob on stdin (provided by Claude Code's harness after each assistant message or permission/vim mode change, debounced to 300ms), extracts model / context / rate limits / cost via `jq`, adds git info via `git`, reads the session transcript mtime for the activity indicator, prints one ANSI-colored line. The `SHOW_*` flags at the top of the file are the single source of truth for which fields appear. User-influenced values (model, effort, branch name, activity tool name) are whitelist-validated and length-capped before they reach `printf %b`.

- **`craft-statusline-wizard.sh`**: interactive TTY configurator for the 7 semantic fields (model, effort, context, rate, cost, branch, activity). Reads current `SHOW_*` values, asks 1/0 per field, renders a preview by editing a `mktemp` copy (not the real file), validates with `bash -n`, and applies atomically via `mv`.

- **`skills/craft-statusline/SKILL.md`**: the `/craft-statusline` slash command. Detects one of four states (A: not set up, B: active, C: installed-but-inactive, D: different script active), then acts in a single response: auto-install in state A, show fields in B, auto-activate in C, ask-before-replace in D. Field args toggle `SHOW_*` via `perl -i -pe` (portable across GNU and BSD `sed`).

- **`install.sh`**: installer. Most of its size is `ensure_jq()`: tries `PATH`, then `brew install jq`, then downloads the platform-matching static binary from a pinned jq release into `~/.claude/bin/jq`. The direct-download path verifies SHA256 against **hardcoded constants in this installer** (not a remote manifest, to avoid the bootstrap tautology), uses an atomic tmpfile pattern, and strips `com.apple.quarantine` on macOS so Gatekeeper does not silently block the binary.

Home-dir layout after install:
```
~/.claude/craft-statusline.sh           # renderer
~/.claude/craft-statusline-wizard.sh    # wizard
~/.claude/bin/jq                        # only if PATH/Homebrew both missed
~/.claude/skills/craft-statusline/SKILL.md
~/.claude/commands/craft-statusline.md  # symlink → SKILL.md
~/.claude/settings.json                 # statusLine entry points at craft-statusline.sh
~/.claude/state/version-check           # update-check cache (daily)
~/.claude/craft-statusline-custom.sh    # optional, user-authored custom fields
```

## Conventions that matter

- **bash 3.2 compatibility**. macOS still ships 3.2 as `/bin/bash`. Do not use `mapfile`, `readarray`, `declare -A`, `${var,,}`, or `shopt -s globstar`. Use `tr '[:upper:]' '[:lower:]'` for case folding and `awk`/`while read` loops for array building.

- **Portable `sed -i`**. GNU sed uses `sed -i`; BSD sed (macOS default) requires `sed -i ''`. The wizard defines a `sed_inplace` wrapper that detects GNU vs BSD. In SKILL.md we use `perl -i -pe` instead because its syntax is identical everywhere, and the slash command runs on whichever machine the user is on. Never call raw `sed -i` or `sed -i ''` directly.

- **`jq` lookup is three-tier**. Every script that needs jq does: `command -v jq` → `~/.claude/bin/jq` → give up gracefully (renderer exits 0 with empty output; wizard prints a warning and skips settings.json integration). Preserve this pattern; silent failure is the correct behavior for a statusline because garbled output is worse than no output.

- **Never silently replace an existing statusline.** `install.sh` and the SKILL's State D both *report* an existing `statusLine.command` in `settings.json` and require an explicit action to overwrite.

- **Activity is hook-free.** The indicator reads the mtime of the active session transcript in `~/.claude/projects/` and, if fresh, tails the last 30 lines to find the most recent `tool_use` event. No `PreToolUse`/`PostToolUse` hooks, no helper scripts, no writes to `settings.json`.

- **Cost is API-billing only.** On Pro/Team/Max flat-rate plans, `cost` and any derived metrics are hypothetical pay-per-token equivalents, not real invoices. Cost stays off by default. README, SKILL.md, and wizard make this explicit so users do not misread the number.

- **`SHOW_COLOR`, `SHOW_CONTEXT_ALERT`, `SHOW_UPDATE` are intentionally not in the wizard.** They are edited by hand in the `.sh` file. The wizard only flips the seven semantic fields.

- **Version lives in five places.** `craft-statusline.sh`, `craft-statusline-wizard.sh`, and `install.sh` each have a `VERSION="X.Y.Z"` near the top. `skills/craft-statusline/SKILL.md` has `version:` in its frontmatter. The README badge is the fifth. When bumping, update all five and add a CHANGELOG entry.

## Testing

`bats tests/` runs the full suite locally (requires bats-core: `brew install bats-core` on macOS, `apt-get install bats` on Ubuntu). GitHub Actions runs it on both `ubuntu-latest` and `macos-latest` via `.github/workflows/tests.yml`. Shellcheck runs separately via `.github/workflows/shellcheck.yml`. Both gate `main`.

The suite is black-box: no function sourcing, no mock, no harness. Tests pipe sample JSON into the real script and grep the output (stripped of ANSI). That keeps tests honest at the cost of being slow to inspect individual code paths.
