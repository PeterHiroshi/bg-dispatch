#!/usr/bin/env bash
#
# watchdog.sh — Background watchdog for bg-dispatch tasks.
#
# Monitors task for:
#   - Stall detection (no file changes in workdir)
#   - Max runtime enforcement
#   - Process exit detection + fallback notification
#
# Usage: watchdog.sh <task_dir> <bg_pid> <workdir> [stall_timeout] [max_runtime]
#

set -uo pipefail

TASK_DIR="$1"
BG_PID="$2"
WORKDIR="$3"
STALL_TIMEOUT="${4:-900}"
MAX_RUNTIME="${5:-7200}"

META_FILE="$TASK_DIR/meta.json"
TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
# Progress is centralized in the task directory (not workdir/.dev-progress/)
PROGRESS_DIR="$TASK_DIR"
LOG_FILE="$TASK_DIR/watchdog.log"
BG_DISPATCH_DIR="${BG_DISPATCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Find lock file
LOCK_DIR="$(dirname "$TASK_DIR")/../locks"
LOCK_FILE=""
if [ -d "$LOCK_DIR" ]; then
  for lf in "$LOCK_DIR"/*.lock; do
    [ -f "$lf" ] || continue
    LOCK_FILE="$lf"
    break
  done
fi

wlog() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$LOG_FILE"
}

wlog "Watchdog started. PID=$BG_PID WORKDIR=$WORKDIR STALL=$STALL_TIMEOUT MAX=$MAX_RUNTIME"

# === Notification helper ===
trigger_notify() {
  local REASON="$1"
  local COMPLETED_AT
  COMPLETED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update meta if still running
  local CURRENT_STATUS
  CURRENT_STATUS=$(jq -r '.status // ""' "$META_FILE" 2>/dev/null || echo "")
  if [ "$CURRENT_STATUS" = "running" ]; then
    jq --arg ts "$COMPLETED_AT" --arg reason "$REASON" \
      '. + {completed_at: $ts, status: "done", completion_trigger: $reason}' \
      "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
  fi

  sleep 3

  # Dispatch via notifier system
  NOTIFY_SCRIPT="$BG_DISPATCH_DIR/notify.sh"
  if [ -f "$NOTIFY_SCRIPT" ]; then
    bash "$NOTIFY_SCRIPT" "$META_FILE" >> "$LOG_FILE" 2>&1 || true
    wlog "Notifications dispatched ($REASON)"
  else
    # Fallback: direct openclaw cron
    if command -v openclaw >/dev/null 2>&1; then
      local EFFECTIVE_MODEL STARTED_AT_VAL WAKE_TEXT FIRE_AT
      EFFECTIVE_MODEL=$(jq -r '.effective_model // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
      STARTED_AT_VAL=$(jq -r '.started_at // ""' "$META_FILE" 2>/dev/null || echo "")
      WAKE_TEXT="🔨 bg-dispatch task done: ${TASK_NAME}. Duration: ${STARTED_AT_VAL} → ${COMPLETED_AT}. Workdir: ${WORKDIR}. Model: ${EFFECTIVE_MODEL}. Progress: ${TASK_DIR}/progress.md."
      openclaw system event --mode now --text "$WAKE_TEXT" >/dev/null 2>&1 || true
      wlog "Fallback: OpenClaw notified directly ($REASON)"
    fi
  fi

  [ -n "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
}

# === Main loop ===
START_TIME=$(date +%s)
LAST_ACTIVITY=$(date +%s)

while true; do
  sleep 15

  # Process exited?
  if ! kill -0 $BG_PID 2>/dev/null; then
    wlog "Process $BG_PID exited. Waiting for hook..."
    sleep 35  # Give hook time to fire

    CURRENT_STATUS=$(jq -r '.status // ""' "$META_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_STATUS" = "running" ]; then
      wlog "Hook didn't fire. Sending fallback notification."
      trigger_notify "watchdog_fallback"
    else
      COMPLETION_TRIGGER=$(jq -r '.completion_trigger // ""' "$META_FILE" 2>/dev/null || echo "")
      if [ -z "$COMPLETION_TRIGGER" ]; then
        wlog "Hook set status but may not have sent notification. Safety net."
        trigger_notify "watchdog_safety_net"
      else
        wlog "Hook handled notification."
      fi
    fi
    break
  fi

  NOW=$(date +%s)

  # Max runtime check
  ELAPSED=$((NOW - START_TIME))
  if [ "$ELAPSED" -ge "$MAX_RUNTIME" ]; then
    wlog "Max runtime (${MAX_RUNTIME}s) exceeded. Killing."
    kill -TERM $BG_PID 2>/dev/null || true
    jq --arg reason "max_runtime_exceeded" '. + {status: "killed", kill_reason: $reason}' \
      "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
    trigger_notify "max_runtime_exceeded"
    break
  fi

  # Activity check
  RECENT=$(find "$WORKDIR" -not -path "*/.git/*" -newer "$TASK_DIR/pid" -type f 2>/dev/null | head -1)
  if [ -n "$RECENT" ]; then
    LAST_ACTIVITY=$NOW
    touch "$TASK_DIR/pid"
  fi

  # Progress.md completion check
  PROGRESS_FILE="$PROGRESS_DIR/progress.md"
  if [ -f "$PROGRESS_FILE" ]; then
    PROGRESS_STATUS=$(grep -m1 '^## Status:' "$PROGRESS_FILE" 2>/dev/null | sed 's/^## Status: *//' | tr '[:lower:]' '[:upper:]' || echo "")
    if [ "$PROGRESS_STATUS" = "COMPLETE" ] || [ "$PROGRESS_STATUS" = "DONE" ]; then
      wlog "Task marked COMPLETE in progress.md."
      kill -TERM $BG_PID 2>/dev/null || true
      trigger_notify "progress_complete"
      break
    fi
  fi

  # Stall check
  IDLE=$((NOW - LAST_ACTIVITY))
  if [ "$IDLE" -ge "$STALL_TIMEOUT" ]; then
    wlog "Stalled for ${IDLE}s (limit: ${STALL_TIMEOUT}s). Killing."
    kill -TERM $BG_PID 2>/dev/null || true
    jq --arg reason "stall_detected" --arg idle "$IDLE" \
      '. + {status: "killed", kill_reason: $reason, idle_seconds: ($idle | tonumber)}' \
      "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
    # Update meta.json with stall info (centralized in task dir)
    if [ -f "$TASK_DIR/meta.json" ]; then
      jq '. + {needs_review: true}' \
        "$TASK_DIR/meta.json" > "$TASK_DIR/meta.json.stall.tmp" \
        && mv "$TASK_DIR/meta.json.stall.tmp" "$TASK_DIR/meta.json"
    fi
    trigger_notify "stall_detected"
    break
  fi
done

wlog "Watchdog exiting."
