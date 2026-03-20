#!/usr/bin/env bash
#
# openclaw.sh — bg-dispatch notifier: OpenClaw cron system event
#
# Wakes the OpenClaw main session via `openclaw cron add --system-event`.
# This is the primary notification path for OpenClaw-based setups.
#
# Config keys (in bg-dispatch.json notifiers[].config):
#   session    — OpenClaw session to wake (default: "main")
#
# Required: `openclaw` CLI in PATH
#

notifier_validate() {
  if ! command -v openclaw >/dev/null 2>&1; then
    echo "Warning: openclaw CLI not found — openclaw notifier will be skipped at runtime" >&2
    return 0  # non-fatal: may be available at task completion time
  fi
}

notifier_send() {
  local META_FILE="$1"
  local CONFIG="$2"  # JSON string with notifier config

  if ! command -v openclaw >/dev/null 2>&1; then
    echo "[openclaw-notifier] openclaw CLI not available" >&2
    return 1
  fi

  local SESSION
  SESSION=$(echo "$CONFIG" | jq -r '.session // "main"' 2>/dev/null || echo "main")

  local TASK_NAME
  TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE")
  local ADAPTER
  ADAPTER=$(jq -r '.adapter // "unknown"' "$META_FILE")
  local WORKDIR
  WORKDIR=$(jq -r '.workdir // ""' "$META_FILE")
  local EFFECTIVE_MODEL
  EFFECTIVE_MODEL=$(jq -r '.effective_model // "unknown"' "$META_FILE")
  local STARTED_AT
  STARTED_AT=$(jq -r '.started_at // ""' "$META_FILE")
  local COMPLETED_AT
  COMPLETED_AT=$(jq -r '.completed_at // ""' "$META_FILE")
  local EXIT_CODE
  EXIT_CODE=$(jq -r '.exit_code // "?"' "$META_FILE")
  local STATUS
  STATUS=$(jq -r '.status // "unknown"' "$META_FILE")

  local WAKE_TEXT="🔨 bg-dispatch task done: ${TASK_NAME} (${ADAPTER}). Status: ${STATUS}. Exit: ${EXIT_CODE}. Duration: ${STARTED_AT} → ${COMPLETED_AT}. Workdir: ${WORKDIR}. Model: ${EFFECTIVE_MODEL}. Progress: ${WORKDIR}/.dev-progress/progress.md. Result: ${META_FILE}."

  local FIRE_AT
  FIRE_AT=$(date -u -d '+5 seconds' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

  openclaw cron add \
    --name "bgd-done-${TASK_NAME}" \
    --at "$FIRE_AT" \
    --wake now \
    --session "$SESSION" \
    --delete-after-run \
    --system-event "$WAKE_TEXT" >/dev/null 2>&1

  echo "[openclaw-notifier] Sent to session=$SESSION" >&2
}
