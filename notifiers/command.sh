#!/usr/bin/env bash
#
# command.sh — bg-dispatch notifier: Run a custom command
#
# Executes an arbitrary command on task completion.
# The command receives task metadata as environment variables.
#
# Config keys (in bg-dispatch.json notifiers[].config):
#   command    — Shell command to execute (required)
#   timeout    — Max execution time in seconds (default: 30)
#
# Available env vars in command context:
#   BGD_TASK_NAME, BGD_STATUS, BGD_EXIT_CODE, BGD_WORKDIR,
#   BGD_MODEL, BGD_ADAPTER, BGD_STARTED_AT, BGD_COMPLETED_AT,
#   BGD_META_FILE, BGD_PROGRESS_FILE
#

notifier_validate() {
  return 0  # command is validated at send time
}

notifier_send() {
  local META_FILE="$1"
  local CONFIG="$2"

  local CMD
  CMD=$(echo "$CONFIG" | jq -r '.command // ""' 2>/dev/null || echo "")
  if [[ -z "$CMD" ]]; then
    echo "[command-notifier] No command configured" >&2
    return 1
  fi

  local TIMEOUT
  TIMEOUT=$(echo "$CONFIG" | jq -r '.timeout // 30' 2>/dev/null || echo "30")

  # Export task metadata as env vars
  export BGD_TASK_NAME=$(jq -r '.task_name // ""' "$META_FILE")
  export BGD_STATUS=$(jq -r '.status // ""' "$META_FILE")
  export BGD_EXIT_CODE=$(jq -r '.exit_code // ""' "$META_FILE")
  export BGD_WORKDIR=$(jq -r '.workdir // ""' "$META_FILE")
  export BGD_MODEL=$(jq -r '.effective_model // .model // ""' "$META_FILE")
  export BGD_ADAPTER=$(jq -r '.adapter // ""' "$META_FILE")
  export BGD_STARTED_AT=$(jq -r '.started_at // ""' "$META_FILE")
  export BGD_COMPLETED_AT=$(jq -r '.completed_at // ""' "$META_FILE")
  export BGD_META_FILE="$META_FILE"
  export BGD_PROGRESS_FILE="$(dirname "$META_FILE")/progress.md"

  timeout "$TIMEOUT" bash -c "$CMD" 2>&1 || {
    echo "[command-notifier] Command failed or timed out (${TIMEOUT}s)" >&2
    return 1
  }

  echo "[command-notifier] Command executed successfully" >&2
}
