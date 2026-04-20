## What this changes
<!-- One or two sentences. -->

## Why
<!-- What problem does this solve? -->

## Compatibility checklist
- [ ] Works under bash 3.2 (macOS default): no `mapfile`/`readarray`, no `declare -A`, no `${var,,}`
- [ ] Uses the `sed_inplace` wrapper, not raw `sed -i`
- [ ] No new runtime dependencies beyond bash + jq + git
- [ ] `shellcheck` passes (CI runs it; run locally with `shellcheck install.sh craft-statusline.sh craft-statusline-wizard.sh`)
- [ ] Manual test: `echo '<sample json>' | bash craft-statusline.sh` renders as expected

## Docs updated
- [ ] README.md (if behavior or setup changed)
- [ ] skills/craft-statusline/SKILL.md (if the slash command changed)
- [ ] CLAUDE.md (if architecture or conventions changed)
- [ ] CHANGELOG.md (entry under "Unreleased")
- [ ] Version bumped in `craft-statusline.sh`, `install.sh`, SKILL.md frontmatter, and README badge (if release-worthy)
