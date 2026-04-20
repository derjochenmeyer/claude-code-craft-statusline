#!/bin/bash
# claude-code-craft-statusline installer
# https://github.com/derjochenmeyer/claude-code-craft-statusline

VERSION="1.1.0"
GITHUB_REPO="derjochenmeyer/claude-code-craft-statusline"
GITHUB_RAW="https://raw.githubusercontent.com/$GITHUB_REPO/main"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"
BIN_DIR="$HOME/.claude/bin"

# jq is pinned to a specific version with hardcoded SHA256 checksums per
# platform, not fetched as `latest`. This closes the bootstrap tautology
# where checksum and binary share a trust root: an attacker who pushes
# a malicious release would also control the manifest. By pinning the
# hash in this installer, verification is independent of the release
# channel at runtime.
#
# To bump: fetch the new sha256sum.txt, update JQ_VERSION and the four
# SHA256 constants below, test on macOS arm64 at minimum, tag a release.
JQ_VERSION="1.8.1"
JQ_SHA256_MACOS_ARM64="a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603"
JQ_SHA256_MACOS_AMD64="e80dbe0d2a2597e3c11c404f03337b981d74b4a8504b70586c354b7697a7c27f"
JQ_SHA256_LINUX_AMD64="020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d"
JQ_SHA256_LINUX_ARM64="6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4"

LOCAL=false
SHOW_VERSION=false
for arg in "$@"; do
  case "$arg" in
    --local)   LOCAL=true ;;
    --version) SHOW_VERSION=true ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if $SHOW_VERSION; then
  echo "claude-code-craft-statusline installer $VERSION (bundles jq $JQ_VERSION)"
  exit 0
fi

echo "claude-code-craft-statusline v$VERSION"
echo "======================================="
echo ""

# --- Helpers -----------------------------------------------------------------

compute_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    return 1
  fi
}

# Atomic download via tmpfile. Optionally verify SHA256.
download_file() {
  local url="$1" dest="$2" expected_sha="${3:-}"
  local tmp="${dest}.tmp.$$"

  if ! curl -fL --show-error "$url" -o "$tmp" 2>&1; then
    rm -f "$tmp"
    return 1
  fi

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    echo "  download returned empty file: $url"
    return 1
  fi

  if [[ -n "$expected_sha" ]]; then
    local actual_sha
    actual_sha=$(compute_sha256 "$tmp") || {
      rm -f "$tmp"
      echo "  cannot compute checksum (no shasum or sha256sum on PATH)"
      return 1
    }
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      rm -f "$tmp"
      echo "  SHA256 mismatch for $url"
      echo "    expected: $expected_sha"
      echo "    actual:   $actual_sha"
      return 1
    fi
  fi

  mv "$tmp" "$dest"
  return 0
}

# --- jq dependency -----------------------------------------------------------

ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$BIN_DIR/jq" ]] && "$BIN_DIR/jq" --version >/dev/null 2>&1; then
    echo "  jq found at $BIN_DIR/jq"
    return 0
  fi

  echo ""
  echo "  [dependency] jq is required, the statusline parses Claude Code's JSON input"

  if command -v brew >/dev/null 2>&1; then
    echo "  Installing jq via Homebrew..."
    if brew install jq; then
      echo "  jq installed via Homebrew"
      return 0
    fi
    echo "  brew install jq failed, falling back to direct download"
  fi

  local os arch jq_asset expected_sha
  os=$(uname -s)
  arch=$(uname -m)
  case "${os}-${arch}" in
    Darwin-arm64)                jq_asset="jq-macos-arm64";  expected_sha="$JQ_SHA256_MACOS_ARM64" ;;
    Darwin-x86_64)               jq_asset="jq-macos-amd64";  expected_sha="$JQ_SHA256_MACOS_AMD64" ;;
    Linux-x86_64)                jq_asset="jq-linux-amd64";  expected_sha="$JQ_SHA256_LINUX_AMD64" ;;
    Linux-aarch64|Linux-arm64)   jq_asset="jq-linux-arm64";  expected_sha="$JQ_SHA256_LINUX_ARM64" ;;
    *)
      echo "  unsupported platform: ${os}-${arch}"
      echo "  install jq manually: https://jqlang.github.io/jq/download/"
      return 1
      ;;
  esac

  if ! mkdir -p "$BIN_DIR" 2>/dev/null; then
    echo "  cannot create $BIN_DIR (check permissions)"
    return 1
  fi

  local jq_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/$jq_asset"
  echo "  Downloading jq $JQ_VERSION ($jq_asset) to $BIN_DIR/..."
  echo "  Expected SHA256: $expected_sha"
  if ! download_file "$jq_url" "$BIN_DIR/jq" "$expected_sha"; then
    echo "  failed to install jq automatically"
    echo "  manual install: https://jqlang.github.io/jq/download/"
    return 1
  fi
  chmod +x "$BIN_DIR/jq"

  if [[ "$os" == "Darwin" ]] && command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$BIN_DIR/jq" 2>/dev/null || true
  fi

  if ! "$BIN_DIR/jq" --version >/dev/null 2>&1; then
    echo "  downloaded jq binary did not run, removing"
    rm -f "$BIN_DIR/jq"
    return 1
  fi

  echo "  jq installed to $BIN_DIR/jq (the statusline finds it automatically)"
  return 0
}

SKIP_INSTALL=false
ensure_jq || SKIP_INSTALL=true

if $SKIP_INSTALL; then
  echo ""
  echo "jq not available, aborting statusline install."
  echo "Install jq manually, then re-run this installer."
  exit 1
fi

# --- Install scripts ---------------------------------------------------------

mkdir -p "$SKILLS_DIR/craft-statusline"
mkdir -p "$COMMANDS_DIR"

STATUSLINE_TARGET="$HOME/.claude/craft-statusline.sh"
WIZARD_TARGET="$HOME/.claude/craft-statusline-wizard.sh"
SKILL_TARGET="$SKILLS_DIR/craft-statusline/SKILL.md"

if $LOCAL; then
  STATUSLINE_SOURCE="$SCRIPT_DIR/craft-statusline.sh"
  WIZARD_SOURCE="$SCRIPT_DIR/craft-statusline-wizard.sh"
  SKILL_SOURCE="$SCRIPT_DIR/skills/craft-statusline/SKILL.md"
else
  STATUSLINE_SOURCE="$GITHUB_RAW/craft-statusline.sh"
  WIZARD_SOURCE="$GITHUB_RAW/craft-statusline-wizard.sh"
  SKILL_SOURCE="$GITHUB_RAW/skills/craft-statusline/SKILL.md"
fi

echo ""
echo "  [scripts]"

backup_if_present() {
  local target="$1" label="$2"
  if [[ -f "$target" ]]; then
    local backup
    backup="${target}.bak.$(date +%s)"
    cp "$target" "$backup" && echo "  backed up existing $label to $backup"
  fi
}

install_file() {
  local source="$1" target="$2" label="$3" executable="$4" kind="$5"

  local tmp="${target}.tmp.$$"

  if $LOCAL; then
    cp "$source" "$tmp" || { rm -f "$tmp"; echo "  failed to copy $label from $source"; return 1; }
  else
    if ! curl -fL --show-error "$source" -o "$tmp" 2>&1; then
      rm -f "$tmp"
      echo "  failed to download $label from $source"
      return 1
    fi
  fi

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    echo "  $label download produced an empty file"
    return 1
  fi

  case "$kind" in
    script)
      if ! head -1 "$tmp" | grep -q "^#!"; then
        rm -f "$tmp"
        echo "  $label does not look like a shell script (missing shebang)"
        return 1
      fi
      ;;
    doc)
      if head -c 1 "$tmp" | grep -q "<"; then
        rm -f "$tmp"
        echo "  $label looks like HTML, not the expected markdown"
        return 1
      fi
      ;;
  esac

  mv "$tmp" "$target"
  [[ "$executable" == "yes" ]] && chmod +x "$target"
  echo "  [done]    $label -> $target"
  return 0
}

backup_if_present "$STATUSLINE_TARGET" "craft-statusline.sh"
install_file "$STATUSLINE_SOURCE" "$STATUSLINE_TARGET" "craft-statusline.sh" "yes" "script" || exit 1
install_file "$WIZARD_SOURCE"     "$WIZARD_TARGET"    "craft-statusline-wizard.sh" "yes" "script" || exit 1
install_file "$SKILL_SOURCE"      "$SKILL_TARGET"     "skills/craft-statusline" "no" "doc" || exit 1

# Symlink skill into ~/.claude/commands/ for global slash-command discovery.
# Guard against overwriting a user-customized file at the symlink path.
link_target="$COMMANDS_DIR/craft-statusline.md"
if [[ -e "$link_target" && ! -L "$link_target" ]]; then
  echo "  $link_target exists and is not a symlink, leaving it alone"
  echo "  (rename or remove it if you want the installer's shortcut)"
elif [[ -L "$link_target" ]]; then
  existing=$(readlink "$link_target")
  if [[ "$existing" != "$SKILL_TARGET" ]]; then
    ln -sf "$SKILL_TARGET" "$link_target"
    echo "  updated symlink $link_target -> $SKILL_TARGET"
  fi
else
  ln -s "$SKILL_TARGET" "$link_target"
fi

# --- Activate in settings.json (only if nothing is set) ----------------------

SETTINGS="$HOME/.claude/settings.json"
echo ""
echo "  [settings.json]"

if [[ ! -f "$SETTINGS" ]]; then
  echo "  $SETTINGS does not exist, skipping activation"
  echo "  Run /craft-statusline install inside Claude Code to activate."
else
  if ! jq empty "$SETTINGS" 2>/dev/null; then
    echo "  $SETTINGS is not valid JSON, skipping activation"
    echo "  Fix the file, then run /craft-statusline install inside Claude Code."
  else
    CURRENT=$(jq -r '.statusLine.command // "NOT_CONFIGURED"' "$SETTINGS")
    case "$CURRENT" in
      *craft-statusline*)
        echo "  already active (points to craft-statusline.sh)"
        ;;
      NOT_CONFIGURED)
        tmp=$(mktemp)
        if jq '.statusLine = {"type": "command", "command": "~/.claude/craft-statusline.sh", "refreshInterval": 5000}' \
             "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"; then
          echo "  activated, statusLine now points to ~/.claude/craft-statusline.sh"
        else
          rm -f "$tmp"
          echo "  failed to update $SETTINGS"
        fi
        ;;
      *)
        echo "  another statusline is active: $CURRENT"
        echo "  not replacing automatically. Run /craft-statusline install inside Claude Code to switch."
        ;;
    esac
  fi
fi

echo ""
echo "======================================="
echo "Done."
echo ""
echo "Configure interactively:"
echo "  bash ~/.claude/craft-statusline-wizard.sh"
echo ""
echo "Or from inside Claude Code:"
echo "  /craft-statusline              show fields and current state"
echo "  /craft-statusline cost branch  toggle fields on/off"
echo ""
echo "Restart Claude Code for the skill to appear."
