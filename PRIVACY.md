# Privacy Policy

**Last updated: 2026-04-23**

craft-statusline is a local-only Bash renderer. It does not collect, transmit, or share any data.

## What the plugin reads

1. The JSON payload that Claude Code provides on stdin after each assistant message. This contains the active model, context window usage, rate limit percentages, session cost (if the plan exposes it), and the transcript path. The plugin reads it in memory and discards it after rendering one line.
2. `~/.claude/settings.json` for user configuration (field toggles, threshold values, and the active effort level).
3. The active session transcript file in `~/.claude/projects/` for session start time, so the context field can show session duration.
4. The current working directory's git state via the `git` binary, to render the branch badge.

## What the plugin does not do

- No network requests.
- No analytics, telemetry, metrics, crash reporting, or usage tracking.
- No writes outside the user's own `~/.claude/settings.json`, and only through explicit slash commands (`/craft-statusline:install`, `/craft-statusline:uninstall`, `/craft-statusline:on`, `/craft-statusline:off`).
- No data collection of any kind.
- No sharing of data with Anthropic, the author, or any third party.

## Third-party dependencies

The plugin invokes two external binaries as local processes: `jq` (user-installed, parses the stdin JSON) and `git` (user-installed, reads branch state). Neither is controlled by this plugin; their privacy behaviour is governed by their own upstream projects.

## Custom fields

Users may define their own shell functions in `~/.claude/craft-statusline-custom.sh`. The plugin sources this file (never `eval`s it) and runs whitelisted functions under a 2-second timeout. Any data access performed by custom fields is outside the scope of this policy and is the user's own responsibility.

## Contact

Jochen Meyer, [@derjochenmeyer](https://x.com/derjochenmeyer). Issues and questions can also be filed at <https://github.com/derjochenmeyer/claude-code-craft-statusline/issues>.

---

License: MIT. See [LICENSE](LICENSE).
