# Security Policy

## Supported versions

The latest tagged release on `main` is the only supported version. Older versions do not receive fixes.

## Reporting a vulnerability

If you find a vulnerability, please report it privately before filing a public issue.

**Preferred**: open a [GitHub Security Advisory](https://github.com/derjochenmeyer/claude-code-craft-statusline/security/advisories/new) so disclosure is coordinated.

**Fallback**: email derjochenmeyer@gmail.com with the subject `[craft-statusline security]`. Include enough detail to reproduce: affected version, platform, and a minimal example if possible.

Please do not file a public issue or PR containing exploit details until a fix has shipped.

## Response expectations

This is a side project maintained by a single author. Realistic expectations:

- **Acknowledgement**: within 7 days.
- **Triage and assessment**: within 14 days.
- **Fix + disclosure**: varies with severity. Critical issues (remote code execution, privilege escalation) are prioritized.

## Scope

In scope:

- `install.sh` (download + install flow, supply chain)
- `craft-statusline.sh` (JSON parsing, ANSI rendering, whitelist validation, activity detection, update checker, custom-field loader)
- `craft-statusline-wizard.sh` (interactive config, file writes)
- `skills/craft-statusline/SKILL.md` (slash-command behavior inside Claude Code)

Out of scope:

- Bugs in `jq` itself (report to [jqlang/jq](https://github.com/jqlang/jq))
- Bugs in Claude Code (report to Anthropic)
- Bugs in GitHub's CDN (report to GitHub)

## What this project does to reduce risk

- jq is pinned to a specific version with SHA256 checksums hardcoded in `install.sh`. The checksum is not fetched from the same host as the binary at runtime, so an attacker compromising the jq release pipeline cannot silently ship a matching manifest.
- Downloaded shell scripts are shebang-validated before being marked executable; markdown payloads are rejected when they start with an HTML tag (catches GitHub 404 pages).
- User-influenced input (model name, effort level, git branch, activity tool name) is whitelist-validated AND length-capped (via `MAX_MODEL_LEN`, `MAX_EFFORT_LEN`, `MAX_BRANCH_LEN`, `MAX_ACTIVITY_LEN`) before reaching `printf %b`, which would otherwise interpret terminal escape sequences.
- Custom fields are **sourced**, never **eval'd**. Function names loaded from `~/.claude/craft-statusline-custom.sh` must match `^field_[A-Za-z0-9_]+$`, and each runs under a hard 2-second rendertime cap so a slow or hanging field cannot block the refresh.
- The update-checker runs a non-blocking background curl with a 3-second timeout and writes its result to a cache file; it never mutates anything else in `~/.claude/`.
- The activity indicator reads the active session transcript and never writes to `~/.claude/settings.json`, never installs hooks, and never runs user-supplied code from the transcript.
- Existing files in `~/.claude/settings.json`, `~/.claude/commands/craft-statusline.md`, and `~/.claude/craft-statusline.sh` are either preserved, backed up, or reported before changes.
