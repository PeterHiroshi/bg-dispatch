#!/usr/bin/env bash
#
# install.sh — Install bg-dispatch hooks and configure Claude Code
#
# Usage: bash install.sh [--adapter claude-code]
#

set -euo pipefail

BG_DISPATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER="${1:-claude-code}"

echo "=== bg-dispatch Installation ==="
echo ""

# Check dependencies
echo "Checking dependencies..."

if ! command -v jq &> /dev/null; then
  echo "❌ jq is required but not installed" >&2
  exit 1
fi
echo "✓ jq"

if ! command -v script &> /dev/null; then
  echo "❌ 'script' command required (util-linux)" >&2
  exit 1
fi
echo "✓ script (util-linux)"

# Adapter-specific checks
if [[ "$ADAPTER" == "claude-code" ]]; then
  CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo /usr/local/bin/claude)}"
  if [[ ! -x "$CLAUDE_BIN" ]]; then
    echo "❌ Claude Code not found: $CLAUDE_BIN" >&2
    echo "   Install: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
  fi
  echo "✓ Claude Code: $CLAUDE_BIN ($(${CLAUDE_BIN} --version 2>/dev/null || echo 'unknown version'))"

  # Install hook
  HOOKS_DIR="$HOME/.claude/hooks"
  mkdir -p "$HOOKS_DIR"
  cp "$BG_DISPATCH_DIR/hooks/on-complete.sh" "$HOOKS_DIR/on-complete.sh"
  chmod +x "$HOOKS_DIR/on-complete.sh"
  echo "✓ Hook installed: $HOOKS_DIR/on-complete.sh"

  # Merge settings
  SETTINGS="$HOME/.claude/settings.json"
  if [[ ! -f "$SETTINGS" ]]; then
    echo "{}" > "$SETTINGS"
  fi
  cp "$SETTINGS" "$SETTINGS.backup.$(date +%s)"

  NEW_HOOKS=$(cat "$BG_DISPATCH_DIR/hooks/settings.json" | jq -r '.hooks')
  jq --argjson new_hooks "$NEW_HOOKS" '
    .hooks = (.hooks // {}) |
    .hooks.Stop = ($new_hooks.Stop // .hooks.Stop)
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "✓ Settings merged: $SETTINGS"
fi

# Create data directory
mkdir -p "$BG_DISPATCH_DIR/data/tasks"
echo "✓ Data directory: $BG_DISPATCH_DIR/data/"

# Make scripts executable
chmod +x "$BG_DISPATCH_DIR/bg-dispatch"
chmod +x "$BG_DISPATCH_DIR/bgd"
chmod +x "$BG_DISPATCH_DIR/watchdog.sh"
echo "✓ Scripts executable"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Usage:"
echo "  $BG_DISPATCH_DIR/bg-dispatch \\"
echo "    --adapter claude-code \\"
echo "    --prompt 'Your task here' \\"
echo "    --name 'task-name' \\"
echo "    --workdir /path/to/project"
echo ""
echo "💡 Add to your PATH (enables both bg-dispatch and bgd commands):"
echo "  export PATH=\"$BG_DISPATCH_DIR:\$PATH\""
echo "  export BG_DISPATCH_DIR=\"$BG_DISPATCH_DIR\""
echo ""
echo "Monitor tasks:"
echo "  bgd tasks        # List all tasks"
echo "  bgd status       # Quick overview"
echo "  bgd help         # All commands"
echo ""
