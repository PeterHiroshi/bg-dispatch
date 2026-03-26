#!/usr/bin/env bash
#
# openclaw.sh — bg-dispatch notifier: OpenClaw session wake with cascading routing
#
# Wakes the OpenClaw agent session on task completion. Uses a three-level
# cascade to guarantee delivery even when the target session is unavailable:
#
#   1. Targeted session wake (source_session from meta.json)
#   2. System event broadcast (wakes main session as fallback)
#   3. Heartbeat pending marker (caught by next heartbeat poll)
#
# Idempotent: checks meta.json `notified.openclaw` before sending.
# Safe to call from hook, setsid block, and watchdog concurrently.
#
# Config keys (in bg-dispatch.json notifiers[].config):
#   session    — OpenClaw session to wake (default: "main", used in fallback)
#
# meta.json keys used:
#   source_session — Session key that dispatched the task (targeted routing)
#   notified.openclaw — Whether notification was already sent (idempotency)
#
# Required: `openclaw` CLI in PATH
#

notifier_validate() {
  if ! command -v openclaw >/dev/null 2>&1; then
    echo "Warning: openclaw CLI not found — openclaw notifier will be skipped at runtime" >&2
    return 0  # non-fatal: may be available at task completion time
  fi
}

# Helper: atomically update a notified field in meta.json
_update_notified() {
  local META="$1"
  local FIELD="$2"
  local VALUE="${3:-true}"
  jq --arg f "$FIELD" --argjson v "$VALUE" '
    .notified = (.notified // {}) | .notified[$f] = $v
  ' "$META" > "${META}.openclaw-tmp" 2>/dev/null && \
    mv "${META}.openclaw-tmp" "$META" 2>/dev/null
}

notifier_send() {
  local META_FILE="$1"
  local CONFIG="$2"  # JSON string with notifier config
  local EVENT_TYPE="${3:-complete}"

  if ! command -v openclaw >/dev/null 2>&1; then
    echo "[openclaw-notifier] openclaw CLI not available" >&2
    return 1
  fi

  # --- Idempotency check ---
  local ALREADY_SENT
  ALREADY_SENT=$(jq -r '.notified.openclaw // false' "$META_FILE" 2>/dev/null || echo "false")
  if [[ "$ALREADY_SENT" == "true" ]]; then
    echo "[openclaw-notifier] Already sent (idempotent skip)" >&2
    return 0
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
  local SOURCE_SESSION
  SOURCE_SESSION=$(jq -r '.source_session // ""' "$META_FILE")

  local TASK_DIR
  TASK_DIR="$(dirname "$META_FILE")"

  # --- Progress event: log only, no wake ---
  if [[ "$EVENT_TYPE" == "progress" ]]; then
    echo "[openclaw-notifier] Progress update for ${TASK_NAME} (no wake)" >&2
    return 0
  fi

  # --- Build notification text ---
  local STARTED_AT COMPLETED_AT EXIT_CODE STATUS
  STARTED_AT=$(jq -r '.started_at // ""' "$META_FILE")
  COMPLETED_AT=$(jq -r '.completed_at // ""' "$META_FILE")
  EXIT_CODE=$(jq -r '.exit_code // "?"' "$META_FILE")
  STATUS=$(jq -r '.status // "unknown"' "$META_FILE")

  local WAKE_TEXT="🔨 bg-dispatch task done: ${TASK_NAME} (${ADAPTER}). Status: ${STATUS}. Exit: ${EXIT_CODE}. Duration: ${STARTED_AT} → ${COMPLETED_AT}. Workdir: ${WORKDIR}. Model: ${EFFECTIVE_MODEL}. Progress: ${TASK_DIR}/progress.md. Result: ${META_FILE}."

  # --- Cascade Level 1: Targeted session wake ---
  if [[ -n "$SOURCE_SESSION" ]]; then
    echo "[openclaw-notifier] Cascade L1: targeted wake to source_session=$SOURCE_SESSION" >&2
    if openclaw system event --mode now --session-key "$SOURCE_SESSION" --text "$WAKE_TEXT" >/dev/null 2>&1; then
      _update_notified "$META_FILE" "openclaw"
      echo "[openclaw-notifier] L1 success: targeted session notified" >&2
      return 0
    fi
    echo "[openclaw-notifier] L1 failed, falling through to L2" >&2
  fi

  # --- Cascade Level 2: Broadcast system event (main session) ---
  echo "[openclaw-notifier] Cascade L2: broadcast system event (session=$SESSION)" >&2
  if openclaw system event --mode now --text "$WAKE_TEXT" >/dev/null 2>&1; then
    _update_notified "$META_FILE" "openclaw"
    echo "[openclaw-notifier] L2 success: system event sent" >&2
    return 0
  fi
  echo "[openclaw-notifier] L2 failed, falling through to L3" >&2

  # --- Cascade Level 3: Mark for heartbeat recovery ---
  echo "[openclaw-notifier] Cascade L3: marking pending for heartbeat pickup" >&2
  jq --arg msg "$WAKE_TEXT" --arg src "$SOURCE_SESSION" --arg dir "$TASK_DIR" '
    .pending_session_notify = {
      message: $msg,
      source_session: $src,
      task_dir: $dir,
      marked_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }
  ' "$META_FILE" > "${META_FILE}.pending-tmp" 2>/dev/null && \
    mv "${META_FILE}.pending-tmp" "$META_FILE" 2>/dev/null
  echo "[openclaw-notifier] L3: pending_session_notify written to meta.json" >&2

  # Return 1 so notify.sh knows real-time delivery failed (heartbeat will recover)
  return 1
}
