# Contributing

Thanks for considering a contribution. This is a small, opinionated tool, so a quick read here saves time on both sides.

## Scope

The statusline has one job: render a single line for Claude Code's `statusLine` harness. Changes that stay inside that job are welcome. Changes that turn it into something bigger (plugin system, config DSL, TUI) are probably a fork waiting to happen, and that's fine too.

## Ground rules

**Bash 3.2 compatibility.** macOS still ships bash 3.2 as `/bin/bash`. Everything here must run there. No `mapfile`, no `readarray`, no `declare -A`, no `${var,,}`, no `shopt -s globstar`. Use `tr '[:upper:]' '[:lower:]'` for case folding and `while read` loops for array building.

**Only two runtime dependencies.** `bash` and `jq`. `git` is optional (only needed for the branch field). Anything else, even if convenient, is out.

**Portable `sed`.** GNU and BSD `sed` take different arguments for in-place editing. Use the `sed_inplace` wrapper in `craft-statusline-wizard.sh`, or use `perl -i -pe` which is identical across platforms. Never call raw `sed -i` or `sed -i ''`.

**Never silently replace user config.** `~/.claude/settings.json` is shared with other tools. The installer reports existing state and refuses to overwrite without explicit action.

**Validate inputs.** Anything that ends up inside `printf "%b"` has to be whitelist-validated first. The statusline input comes from Claude Code's JSON, but the relevant fields (model, effort, branch name, activity tool name) can be user-influenced and must not carry escape sequences into the terminal. Also check against the `MAX_*_LEN` constants for length caps.

**Source, never eval.** The custom-fields loader in `craft-statusline.sh` sources `~/.claude/craft-statusline-custom.sh` and gates function names with a whitelist regex. If you touch this path, preserve the source-not-eval invariant.

**No hooks in `settings.json`.** The activity indicator is intentionally hook-free (driven by session transcript mtime). If a feature proposal requires writing hooks to the user's `settings.json`, discuss first. We found that path to be unreliable and noisy in practice.

## File layout

- `craft-statusline.sh` is the renderer (reads JSON stdin, writes ANSI to stdout).
- `craft-statusline-wizard.sh` is the 7-field interactive configurator.
- `install.sh` is the installer.
- `skills/craft-statusline/SKILL.md` is the `/craft-statusline` slash command.
- `tests/*.bats` are the black-box tests.

## Before you open a PR

1. Run `shellcheck install.sh craft-statusline.sh craft-statusline-wizard.sh`. CI will anyway; save a round-trip.
2. Run the renderer once:

   ```bash
   echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":30}},"cost":{"total_cost_usd":0.85}}' | bash craft-statusline.sh
   ```
3. Run the test suite: `bats tests/` (install bats-core via `brew install bats-core` on macOS or `apt-get install bats` on Linux).
4. If you added or changed user-facing behavior, update README.md. If you changed the slash command, also update `skills/craft-statusline/SKILL.md`. If you changed architecture, update CLAUDE.md.
5. Add a CHANGELOG entry.

## Releases

Version lives in five places: `craft-statusline.sh`, `craft-statusline-wizard.sh`, `install.sh` (each `VERSION="X.Y.Z"` near the top), `skills/craft-statusline/SKILL.md` frontmatter, and the README badge. Bump all five and add a CHANGELOG entry.

## Feedback

Open an issue first for anything larger than a one-file fix. Saves duplicate work on both sides.
