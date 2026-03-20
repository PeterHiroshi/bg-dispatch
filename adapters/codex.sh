#!/usr/bin/env bash
#
# codex.sh — bg-dispatch adapter for OpenAI Codex CLI
#
# Adapter interface:
#   build_command()            — Returns the CLI command to launch
#   get_env()                  — Prints export statements for env vars
#   adapter_validate()         — Validates prerequisites
#   adapter_effective_model()  — Returns resolved model ID
#
# Adapter-specific options (via --opt key=value):
#   approval-mode  — full-auto, suggest, or ask (default: full-auto)
#

CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || echo codex)}"

adapter_validate() {
  if ! command -v "$CODEX_BIN" &>/dev/null; then
    echo "Error: codex CLI not found. Install: npm install -g @openai/codex" >&2
    exit 1
  fi
}

build_command() {
  local PROMPT="$BG_DISPATCH_PROMPT"
  local MODEL="$BG_DISPATCH_MODEL"

  local APPROVAL="${BG_DISPATCH_OPT_approval_mode:-full-auto}"

  local CMD
  CMD=$(printf '%q -q --approval-mode %q' "$CODEX_BIN" "$APPROVAL")

  if [[ -n "$MODEL" ]]; then
    CMD+=$(printf ' --model %q' "$MODEL")
  fi

  CMD+=$(printf ' %q' "$PROMPT")

  echo "$CMD"
}

get_env() {
  : # OPENAI_API_KEY should be in environment already
}

adapter_effective_model() {
  if [[ -n "$BG_DISPATCH_MODEL" ]]; then
    echo "$BG_DISPATCH_MODEL"
  else
    echo "o4-mini"  # codex default
  fi
}
