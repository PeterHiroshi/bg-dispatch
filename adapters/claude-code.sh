#!/usr/bin/env bash
#
# claude-code.sh — bg-dispatch adapter for Claude Code
#
# Adapter interface:
#   build_command()         — Returns the CLI command to launch (printed to stdout)
#   get_env()               — Prints export statements for required env vars
#   adapter_validate()      — Validates prerequisites, exits 1 on failure
#   adapter_effective_model() — Returns the resolved model ID
#

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo /usr/local/bin/claude)}"

# Default allowed tools (includes Skill for Superpowers plugin integration)
DEFAULT_TOOLS='Bash(*),Read,Write,Edit,MultiEdit,Glob,Grep,Skill,TodoRead,TodoWrite,WebFetch,Agent'

adapter_validate() {
  if [[ ! -x "$CLAUDE_BIN" ]]; then
    echo "Error: Claude Code binary not found: $CLAUDE_BIN" >&2
    echo "Install: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
  fi
  if ! command -v script &> /dev/null; then
    echo "Error: 'script' command required (util-linux)" >&2
    exit 1
  fi
}

build_command() {
  local PROMPT="$BG_DISPATCH_PROMPT"
  local MODEL="$BG_DISPATCH_MODEL"
  local TOOLS="${BG_DISPATCH_ALLOWED_TOOLS:-$DEFAULT_TOOLS}"

  # Build command as properly escaped string
  local CMD
  CMD=$(printf '%q -p %q --allowedTools %q' "$CLAUDE_BIN" "$PROMPT" "$TOOLS")

  if [[ -n "$MODEL" ]]; then
    CMD+=$(printf ' --model %q' "$MODEL")
  fi

  # Permission mode from adapter opts
  local PERM="${BG_DISPATCH_OPT_permission_mode:-}"
  if [[ -n "$PERM" ]]; then
    CMD+=$(printf ' --permission-mode %q' "$PERM")
  fi

  echo "$CMD"
}

get_env() {
  # Agent Teams mode
  if [[ "${BG_DISPATCH_AGENT_TEAMS:-}" == "true" ]]; then
    echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1'
  fi
}

adapter_effective_model() {
  local MODEL="$BG_DISPATCH_MODEL"
  if [[ -n "$MODEL" ]]; then
    echo "$MODEL"
    return
  fi

  # Read from Claude Code settings
  local SETTINGS_FILE="$HOME/.claude/settings.json"
  if [[ -f "$SETTINGS_FILE" ]]; then
    local SETTINGS_MODEL
    SETTINGS_MODEL=$(jq -r '.model // ""' "$SETTINGS_FILE" 2>/dev/null || echo "")
    if [[ "$SETTINGS_MODEL" == "opus" ]]; then
      local RESOLVED="${ANTHROPIC_DEFAULT_OPUS_MODEL:-opus}"
      if [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]]; then
        echo "bedrock/${RESOLVED}"
      else
        echo "$RESOLVED"
      fi
    elif [[ -n "$SETTINGS_MODEL" ]]; then
      echo "$SETTINGS_MODEL"
    else
      echo "(default)"
    fi
  else
    echo "(default)"
  fi
}
