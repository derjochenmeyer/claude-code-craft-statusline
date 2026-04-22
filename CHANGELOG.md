# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

## What's listed here

Only user-facing code and feature changes are tracked: new fields, new flags, behavioural changes, bug fixes, removals, security fixes. README copy, screenshots, badges, internal refactors, and CI tweaks are intentionally left out, since git history covers them. If a change wouldn't show up in `--doctor` or in the rendered output, it doesn't belong here.

## [1.2.0] -- 2026-04-21

### Added
- **Context field is now an absolute-token traffic light.** Green while `current_usage` tokens stay below `CONTEXT_DEGRADE_AT_TOKENS` (default 400,000); yellow `⚠` once the session crosses that threshold, which is the zone where model recall measurably degrades on 1M-window models even though there's still headroom; red `⚠` once `used_percentage >= CONTEXT_ALERT_AT` (default 85%) and auto-compact is near. The `⚠` shares the field color (not hard-coded red).
- `CONTEXT_DEGRADE_AT_TOKENS=400000` threshold, documented with a reminder to re-validate as new model generations ship.

### Changed
- **Context field stops using the percent-only gradient** (green < 50, yellow < 70, orange < 85, red ≥ 85). That scheme is kept only for the rate-limit fields, where percent-of-window is the right axis.
- Absolute token count is derived from `.context_window.current_usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens}` per Anthropic's documented statusline schema. `total_input_tokens` / `total_output_tokens` are cumulative session totals and deliberately avoided.

## [1.1.0] -- 2026-04-20

### Added
- **State-aware branch badge palette.** The branch field now colors itself by the dominant git signal instead of a single blue. Priority (blocking first): conflict (red) > diverged (coral) > behind (azure) > combined (coral) > ahead (amber) > unstaged (amber) > staged (green) > untracked (slate) > stashed (violet) > clean (green).

### Fixed
- **Activity indicator no longer sticks on `thinking` after turn-end.** The decoder now reads `stop_reason` on the most recent assistant event in the transcript (walking back past Claude Code's post-turn metadata like `attachment`, `file-history-snapshot`, `custom-title`), so `end_turn`, `max_tokens`, and friends correctly suppress the indicator. The earlier "read last line only" fix missed because the last line is usually metadata, not the assistant message.
- **`stat` flag ordering** on Linux-first detection for the version-check cache (GNU `stat -f` silently returned a mount-point string that parsed as invalid number).

### Changed
- **Removed the `SHOW_EMOJI` flag.** `ctx▸` has been the default since v1.0.0 and aligned with `5h▸`/`7d▸`/`cost▸`; the legacy `✍️` opt-in path is gone. One fewer knob, one fewer edge case.

## [1.0.0] -- 2026-04-20

Initial release. A bash statusline for Claude Code with minimal dependencies (bash + jq), delivered via a pipeable installer with SHA256-verified binaries and an opt-out flag for anyone who prefers manual inspection.

### Fields

- **Model + effort**: current model (shortened, parenthesized variants stripped) with inline effort badge read from `~/.claude/settings.json`.
- **Git branch**: badge with branch name and status symbols for ahead/behind, staged, unstaged, untracked, stashed, conflicts.
- **Context**: percentage used plus session duration, colored by threshold, with a red `⚠` badge when usage crosses `CONTEXT_ALERT_AT` (default 85%).
- **Rate limits**: rolling 5-hour and 7-day token windows, colored by threshold.
- **Session cost** (off by default): running total in USD. Explicit "API billing only" framing since the number is meaningless on flat-rate plans (Pro, Team, Max).
- **Activity indicator**: hook-free, driven by the active session transcript. Shows `● thinking` while Claude is generating text, `● executing (Tool)` while a concrete tool is running, or `● researching` when a subagent has been dispatched. Disappears when the transcript has been idle for 10 seconds. No hooks written to `settings.json`, no helper script, no state file outside the transcript itself.
- **Update checker**: `⬆ vX.Y.Z` badge appears when a newer release is published. Non-blocking background fetch, at most once per 24 hours, 3-second timeout.
- **Custom fields** via `~/.claude/craft-statusline-custom.sh`: user-authored shell functions whose output is appended after the built-ins. The file is sourced (never eval'd), function names are whitelisted to `^field_[A-Za-z0-9_]+$`, and each call runs under a 2-second timeout.

### Security

- jq pinned to a specific version with SHA256 checksums hardcoded in `install.sh`, not fetched from the same host as the binary. Closes the bootstrap tautology where a compromised release channel would publish both the malicious binary and a matching manifest.
- Downloaded binaries go through an atomic tmpfile + verify + mv pattern.
- Downloaded shell scripts are shebang-validated; markdown payloads are rejected when they look like an HTML error page.
- `com.apple.quarantine` stripped from the jq binary on macOS so Gatekeeper does not silently block it.
- Whitelist validation plus explicit length caps on every user-influenced value that reaches `printf %b`, closing an ANSI/escape-injection vector via manipulated JSON.
- Explicit jq type-checks when extracting strings so nested objects cannot propagate through the rendering pipeline.

### Robustness

- Wizard applies `SHOW_*` edits to a tmp copy, validates with `bash -n`, then atomically swaps via `mv`. A failing sed cannot leave the live script half-rewritten.
- Installer backs up any existing `~/.claude/craft-statusline.sh` before overwriting and refuses to replace a user-customized (non-symlink) file at `~/.claude/commands/craft-statusline.md`.
- Session duration falls back to mtime when birthtime is not tracked by the filesystem (ext4).
- Invalid JSON in `~/.claude/settings.json` is reported explicitly instead of silently falling through.

### Tooling and docs

- `--version` on renderer, wizard, and installer.
- `--doctor` diagnostic reports bash, jq, git, settings.json state (including `refreshInterval`), install locations, custom fields file presence, and the update check cache age.
- bats-core test suite covering render output, color thresholds, injection defense, activity detection, custom-field isolation, rendertime caps, update-check behavior, and install-flag consistency.
- GitHub Actions: shellcheck on the three shell scripts, bats on Ubuntu and macOS.
- `SECURITY.md`, `CONTRIBUTING.md`, bug report template.
