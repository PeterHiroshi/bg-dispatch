#!/usr/bin/env bash
#
# on-complete.sh — Hook for Claude Code (Stop/SessionEnd)
#
# Installed to ~/.claude/hooks/on-complete.sh
# Fires when Claude Code finishes a generation. Checks if the process
# actually exited, then writes result.json and dispatches notifications.
#

set -uo pipefail

BG_DISPATCH_DIR="${BG_DISPATCH_DIR:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd 2>/dev/null || echo "$HOME/.bg-dispatch")}"
BG_DISPATCH_DATA_DIR="${BG_DISPATCH_DATA_DIR:-$BG_DISPATCH_DIR/data}"
LOG_FILE="$BG_DISPATCH_DATA_DIR/hook.log"
LOCK_AGE_LIMIT=30

mkdir -p "$BG_DISPATCH_DATA_DIR"

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$LOG_FILE"; }

log "=== Hook fired ==="

# Read stdin (Claude Code passes session JSON)
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(timeout 2 cat /dev/stdin 2>/dev/null || true)
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
log "session=$SESSION_ID event=$EVENT"

# Deduplication (Stop + SessionEnd both fire)
LOCK_FILE="$BG_DISPATCH_DATA_DIR/.hook-lock"
if [ -f "$LOCK_FILE" ]; then
  LOCK_TIME=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$(( NOW - LOCK_TIME ))
  if [ "$AGE" -lt "$LOCK_AGE_LIMIT" ]; then
    log "Duplicate hook within ${AGE}s, skipping"
    exit 0
  fi
fi
touch "$LOCK_FILE"

# Find most recent running task
TASKS_DIR="$BG_DISPATCH_DATA_DIR/tasks"
if [ ! -d "$TASKS_DIR" ]; then
  log "No tasks directory"
  exit 0
fi

TASK_DIR=$(find "$TASKS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "$TASK_DIR" ]; then
  log "No task directory found"
  exit 0
fi

META_FILE="$TASK_DIR/meta.json"
OUTPUT_FILE="$TASK_DIR/output.txt"
RESULT_FILE="$TASK_DIR/result.json"
TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")

log "Processing task: $(basename "$TASK_DIR")"

# Check if process actually exited (retry up to 30s)
TASK_PID=""
if [ -f "$TASK_DIR/pid" ]; then
  TASK_PID=$(cat "$TASK_DIR/pid" 2>/dev/null || true)
fi

RETRY_DELAYS="5 10 15"
PROCESS_EXITED=false

for DELAY in $RETRY_DELAYS; do
  if [ -n "$TASK_PID" ] && kill -0 "$TASK_PID" 2>/dev/null; then
    PROC_STATE=$(cat "/proc/$TASK_PID/status" 2>/dev/null | grep "^State:" | awk '{print $2}')
    if [ "$PROC_STATE" != "Z" ]; then
      log "Process still alive (PID $TASK_PID, state=$PROC_STATE), waiting ${DELAY}s..."
      sleep "$DELAY"
      continue
    fi
  fi
  PROCESS_EXITED=true
  break
done

if [ "$PROCESS_EXITED" = "false" ]; then
  log "Process still running after retries — mid-task hook, skipping"
  rm -f "$LOCK_FILE"
  exit 0
fi

log "Process confirmed exited, sending notification"

# Read metadata
STARTED_AT=$(jq -r '.started_at // ""' "$META_FILE" 2>/dev/null || echo "")
WORKDIR=$(jq -r '.workdir // ""' "$META_FILE" 2>/dev/null || echo "")

sleep 2  # wait for output flush

# Capture output summary
OUTPUT_SUMMARY=""
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
  OUTPUT_SUMMARY=$(tail -c 4000 "$OUTPUT_FILE" 2>/dev/null | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r')
fi

# Write result.json
COMPLETED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -n \
  --arg task_name "$TASK_NAME" \
  --arg session_id "$SESSION_ID" \
  --arg completed_at "$COMPLETED_AT" \
  --arg started_at "$STARTED_AT" \
  --arg workdir "$WORKDIR" \
  --arg output_summary "$OUTPUT_SUMMARY" \
  --arg status "done" \
  '{
    task_name: $task_name,
    session_id: $session_id,
    completed_at: $completed_at,
    started_at: $started_at,
    workdir: $workdir,
    output_summary: $output_summary,
    status: $status
  }' > "$RESULT_FILE" 2>/dev/null

# Update meta status
jq --arg ts "$COMPLETED_AT" '. + {completed_at: $ts, status: "done", completion_trigger: "hook"}' \
  "$META_FILE" > "${META_FILE}.tmp" 2>/dev/null && mv "${META_FILE}.tmp" "$META_FILE"

log "Result written: $RESULT_FILE"

# === Dispatch notifications via notifier system ===
NOTIFY_SCRIPT="$BG_DISPATCH_DIR/notify.sh"
if [ -f "$NOTIFY_SCRIPT" ]; then
  bash "$NOTIFY_SCRIPT" "$META_FILE" >> "$LOG_FILE" 2>&1 || true
  log "Notifications dispatched via notify.sh"
else
  # Fallback: direct openclaw system event
  if command -v openclaw >/dev/null 2>&1; then
    EFFECTIVE_MODEL=$(jq -r '.effective_model // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
    WAKE_TEXT="🔨 bg-dispatch task done: ${TASK_NAME}. Workdir: ${WORKDIR}. Model: ${EFFECTIVE_MODEL}. Progress: ${TASK_DIR}/progress.md."
    openclaw system event --mode now --text "$WAKE_TEXT" >/dev/null 2>&1 || true
    log "Fallback: OpenClaw notified directly"
  fi
fi

log "=== Hook completed ==="
exit 0
