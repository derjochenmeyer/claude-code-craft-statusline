# Claude Code statusline

[![Anthropic](https://img.shields.io/badge/Anthropic-Claude_Code-D97757?logo=anthropic&logoColor=white)](https://claude.com/claude-code) [![Plugin](https://img.shields.io/badge/Claude_Code-Plugin-8B5CF6)](https://docs.claude.com/en/docs/claude-code/plugins)

![Version](https://img.shields.io/badge/version-3.0.0-blue) ![License: MIT](https://img.shields.io/badge/License-MIT-yellow) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey) ![Shell](https://img.shields.io/badge/shell-bash-green) ![Font](https://img.shields.io/badge/fonts-none%20required-brightgreen)

A carefully crafted [Claude Code](https://docs.anthropic.com/en/docs/claude-code) statusline written in bash, distributed as an official Claude Code plugin. Shows model, effort level, git branch and status, session context, rate limits, and session cost.

![claude-code-craft-statusline preview](https://github.com/user-attachments/assets/3b23d36a-26ee-482a-8fe5-ff221274f6a6)

No Node, no Python, no Nerd Fonts. Only requires `jq` (small command-line JSON parser).

The context field uses a traffic light that leans on absolute tokens, not percent: green while you're below the "context rot" zone, yellow with a `⚠` once the session crosses 400k tokens (where model recall measurably degrades on 1M-window models), red with a `⚠` once the window is 85% full and auto-compact is imminent. Rate limits run green → yellow → orange → red by percentage. Session cost is off by default and stays that way for flat-rate plans where it would be misleading.

---

## Install

```
/plugin marketplace add derjochenmeyer/claude-code-craft-statusline
/plugin install craft-statusline
/reload-plugins
/craft-statusline:install
```

Restart Claude Code (or open a new session) to see the statusline render at the bottom of the screen.

### What each step does

1. **`/plugin marketplace add …`** registers this repo's marketplace with Claude Code so it knows where to fetch the plugin from.
2. **`/plugin install craft-statusline`** downloads the plugin into Claude Code's local plugin directory and enables it.
3. **`/reload-plugins`** picks up the plugin's slash commands without a full restart. Without this step, `/craft-statusline:install` is not yet discoverable in the current session.
4. **`/craft-statusline:install`** writes a `statusLine` block into `~/.claude/settings.json` pointing at the plugin's renderer. The slash command checks `jq` is on PATH first and refuses to overwrite an existing different statusLine without `force`.

> **Why the `command` line looks the way it does (`${CLAUDE_PLUGIN_ROOT:-…}`)**
>
> Claude Code currently does not populate `${CLAUDE_PLUGIN_ROOT}` for the statusline subprocess (it does for hooks, MCP, LSP, and monitors). Reported upstream as [anthropics/claude-code#52079](https://github.com/anthropics/claude-code/issues/52079). Until it's fixed, `/craft-statusline:install` writes a POSIX default-expansion that falls back to the version-stable marketplace clone path. Once the upstream bug is fixed, the same line transparently uses the official plugin root with no further action.

### Requirements

| What | Why |
|------|-----|
| **Claude Code** | The statusline reads its JSON input from the harness |
| **bash 3.2+** | Everything here is shell. macOS ships 3.2, Linux has 4+ |
| **jq** | Parses Claude Code's JSON input. Install with `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu). The `:install` command checks for it. |
| **git** | Only needed if `show_branch` is on (default) |

Windows: use WSL.

---

## Configure

All configuration runs through slash commands. Fields are toggled on or off; numeric thresholds (red percent, yellow token count) live in `~/.claude/settings.json` under `pluginConfigs.craft-statusline.options.*` and can be edited there directly.

```
/craft-statusline:status              show current configuration and a live preview
/craft-statusline:on cost             enable a field
/craft-statusline:off branch          disable a field
/craft-statusline:install             (re-)wire into settings.json
/craft-statusline:uninstall           remove from settings.json
```

Field names: `model`, `branch`, `context`, `context_alert`, `rate_limits`, `cost`, `color`.

Defaults: `model + branch + context + context_alert + rate_limits + color` on, `cost` off.

---

## Fields

| Field | Example | What it tells you |
|-------|---------|-------------------|
| Model + effort | `Sonnet 4.6▸normal` | Which model and effort level you're running on. Useful when you switch between projects and want to confirm you're not burning high-effort tokens on a quick task. |
| Git branch | `main ✔` | Live branch status with a state-aware colored badge. Uncommitted changes, staged files, stashes, and remote drift visible without leaving the editor. |
| Context | `ctx▸42% (2h34m)` | Context window usage and session age. Three-stage traffic light: green while tokens < `context_degrade_at_tokens` (default 400k); yellow `⚠` once absolute tokens cross that (model recall degrades noticeably on long contexts, regardless of how much headroom the 1M window still has); red `⚠` once percentage ≥ `context_alert_at` (default 85%) and auto-compact is imminent. |
| Rate limits | `5h▸12% │ 7d▸8%` | Rolling token usage across the last 5 hours and 7 days. Color shifts from green to yellow to red as you approach limits, before you hit them, not after. |
| Session cost | `cost▸0.43$` | **API billing only.** Session cost in USD at pay-per-token rates. On flat-rate plans (Pro, Team, Max) this is a hypothetical equivalent, not your actual invoice. Off by default. |

### A note on `cost` and flat-rate plans

If you are on **Pro, Team, or Max** (flat monthly subscription), `cost` is off by default and you should leave it off. It reflects the API-equivalent token cost, not your actual invoice. Your real constraints on those plans are the 5-hour and 7-day rate limits shown in the rate field.

### Git branch at a glance

Since v1.1.0 the branch badge is also color-aware: it picks its color from the dominant git signal, so you can read the state of the working tree at a glance without parsing the symbols.

![git state badges](https://github.com/user-attachments/assets/4887886c-609b-4bf0-bcac-d4a31c6bc5ba)

| Symbol | Meaning | Why it matters |
|--------|---------|----------------|
| `✔` | Clean working tree | Nothing uncommitted, safe to switch context or wrap up the session |
| `⇡N` | N commits ahead of remote | Work that hasn't been pushed yet |
| `⇣N` | N commits behind remote | Remote has moved on. Pull before your next push |
| `*N` | N stashed changesets | Shelved work you might have forgotten about |
| `+N` | N staged files | Ready to commit, in case Claude staged something while you were focused elsewhere |
| `!N` | N unstaged modifications | Work in progress, still loose |
| `?N` | N untracked files | New files Claude created that aren't tracked yet |
| `⚠N` | N merge conflicts | Needs attention before anything else |

---

## Recommended workflow

Running Claude Code across multiple projects in parallel benefits from a multi-session terminal.

- **macOS**: [cmux](https://github.com/manaflow-ai/cmux). Two features make it the pick for Claude Code. A built-in browser pane lets you research, test, and verify changes without switching windows. Context-aware tabs light up when an agent needs your input, so you never miss a session that is waiting on you.
- **macOS / Linux / Windows**: [Warp](https://www.warp.dev/). A solid cross-platform alternative with tabs and a session sidebar. No browser pane and no per-tab attention signals, but it handles parallel Claude Code sessions cleanly.

craft-statusline runs inside any shell that supports bash and jq.

---

## Diagnostics

```bash
bash <plugin-dir>/scripts/craft-statusline.sh --doctor
```

Reports bash version, jq presence, git, the resolved configuration (from `CLAUDE_PLUGIN_OPTION_*` env or defaults), and the active settings.json wiring. Useful before opening an issue.

You can also run `/craft-statusline:status` from inside Claude Code to see the same configuration plus a live render.

---

## Custom fields

The renderer optionally sources `~/.claude/craft-statusline-custom.sh` if it exists. That file lives in your home directory (not in the plugin), so plugin updates do not touch it.

```bash
# ~/.claude/craft-statusline-custom.sh
field_aws_profile() {
  printf '%s' "${AWS_PROFILE:-default}"
}
field_kube_context() {
  kubectl config current-context 2>/dev/null
}

# Set CUSTOM_FIELDS in this file to control order and which fields render.
CUSTOM_FIELDS="aws_profile kube_context"
```

Function names must match `^field_[A-Za-z0-9_]+$`. The renderer sources the file (never `eval`s) and each call runs under a 2-second timeout.

---

## Update

```
/plugin update craft-statusline
```

The plugin manager handles version checks and updates. No background curl, no embedded version checker.

---

## Uninstall

```
/craft-statusline:uninstall    # remove statusLine from settings.json (keeps plugin installed)
/plugin uninstall craft-statusline   # remove the plugin entirely
```

Custom fields file `~/.claude/craft-statusline-custom.sh` is untouched in either case. delete by hand if you want it gone.

---

## License

MIT. See [LICENSE](LICENSE).

Author Jochen Meyer (X → [@derjochenmeyer](https://x.com/derjochenmeyer))
