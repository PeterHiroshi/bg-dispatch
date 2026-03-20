#!/usr/bin/env bash
#
# aider.sh — bg-dispatch adapter for Aider (https://aider.chat)
#
# Adapter interface:
#   build_command()            — Returns the CLI command to launch
#   get_env()                  — Prints export statements for env vars
#   adapter_validate()         — Validates prerequisites
#   adapter_effective_model()  — Returns resolved model ID
#
# Adapter-specific options (via --opt key=value):
#   edit-format    — Edit format: whole, diff, udiff (default: auto)
#   auto-commits   — Enable auto-commits (default: no-auto-commits)
#   lint-cmd       — Lint command to run after edits
#   test-cmd       — Test command to run after edits
#

AIDER_BIN="${AIDER_BIN:-$(command -v aider 2>/dev/null || echo aider)}"

adapter_validate() {
  if ! command -v "$AIDER_BIN" &>/dev/null; then
    echo "Error: aider not found. Install: pip install aider-chat" >&2
    exit 1
  fi
}

build_command() {
  local PROMPT="$BG_DISPATCH_PROMPT"
  local MODEL="$BG_DISPATCH_MODEL"

  local CMD
  CMD=$(printf '%q --message %q --yes-always' "$AIDER_BIN" "$PROMPT")

  # Model
  if [[ -n "$MODEL" ]]; then
    CMD+=$(printf ' --model %q' "$MODEL")
  fi

  # No auto-commits by default (bg-dispatch manages git)
  local AUTO_COMMITS="${BG_DISPATCH_OPT_auto_commits:-}"
  if [[ "$AUTO_COMMITS" != "true" ]]; then
    CMD+=" --no-auto-commits"
  fi

  # Edit format
  local EDIT_FORMAT="${BG_DISPATCH_OPT_edit_format:-}"
  if [[ -n "$EDIT_FORMAT" ]]; then
    CMD+=$(printf ' --edit-format %q' "$EDIT_FORMAT")
  fi

  # Lint command
  local LINT_CMD="${BG_DISPATCH_OPT_lint_cmd:-}"
  if [[ -n "$LINT_CMD" ]]; then
    CMD+=$(printf ' --lint-cmd %q' "$LINT_CMD")
  fi

  # Test command
  local TEST_CMD="${BG_DISPATCH_OPT_test_cmd:-}"
  if [[ -n "$TEST_CMD" ]]; then
    CMD+=$(printf ' --test-cmd %q' "$TEST_CMD")
  fi

  echo "$CMD"
}

get_env() {
  : # No special env vars needed
}

adapter_effective_model() {
  if [[ -n "$BG_DISPATCH_MODEL" ]]; then
    echo "$BG_DISPATCH_MODEL"
  else
    echo "claude-sonnet-4-20250514"  # aider default
  fi
}
