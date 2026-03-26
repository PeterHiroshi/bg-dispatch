#!/usr/bin/env bash
#
# notify.sh — bg-dispatch notification dispatcher
#
# Reads notifier config from bg-dispatch.json (or defaults to openclaw notifier),
# then calls each configured notifier in order.
#
# Usage: bash notify.sh <meta.json> [config_file] [event_type]
#
# event_type: "complete" (default) or "progress" (lightweight mid-task update)
#
# Config format (bg-dispatch.json):
# {
#   "notifiers": [
#     { "type": "openclaw", "config": { "session": "main" }, "events": ["complete"] },
#     { "type": "webhook",  "config": { "url_env": "SLACK_WEBHOOK_URL", "template": "slack" }, "events": ["complete", "progress"] },
#     { "type": "command",  "config": { "command": "echo $BGD_TASK_NAME done!" } }
#   ]
# }
#

set -uo pipefail

BG_DISPATCH_DIR="${BG_DISPATCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
NOTIFIERS_DIR="$BG_DISPATCH_DIR/notifiers"

META_FILE="${1:-}"
CONFIG_FILE="${2:-}"
EVENT_TYPE="${3:-complete}"

if [[ -z "$META_FILE" ]]; then
  echo "Usage: notify.sh <meta.json> [config_file] [event_type]" >&2
  exit 1
fi

if [[ ! -f "$META_FILE" ]]; then
  echo "Error: meta.json not found: $META_FILE" >&2
  exit 1
fi

LOG_PREFIX="[bg-dispatch-notify]"

# === Helper: atomically update a notified field in meta.json ===
update_notified() {
  local FIELD="$1"
  local VALUE="${2:-true}"
  jq --arg f "$FIELD" --argjson v "$VALUE" '
    .notified = (.notified // {}) | .notified[$f] = $v
  ' "$META_FILE" > "${META_FILE}.notify-tmp" 2>/dev/null && \
    mv "${META_FILE}.notify-tmp" "$META_FILE" 2>/dev/null
}

# === Find config file ===
if [[ -z "$CONFIG_FILE" ]]; then
  # Search order: workdir, data dir, install dir
  WORKDIR=$(jq -r '.workdir // ""' "$META_FILE" 2>/dev/null || echo "")
  for candidate in \
    "${WORKDIR}/bg-dispatch.json" \
    "${BG_DISPATCH_DATA_DIR:-$BG_DISPATCH_DIR/data}/bg-dispatch.json" \
    "$BG_DISPATCH_DIR/bg-dispatch.json" \
    "$HOME/.bg-dispatch.json" \
  ; do
    if [[ -f "$candidate" ]]; then
      CONFIG_FILE="$candidate"
      break
    fi
  done
fi

# === Read notifiers from config ===
NOTIFIER_COUNT=0
NOTIFIER_JSON='[{"type":"openclaw","config":{}}]'  # default

if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
  CONFIGURED=$(jq -r '.notifiers // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  if [[ -n "$CONFIGURED" ]] && [[ "$CONFIGURED" != "null" ]]; then
    NOTIFIER_JSON="$CONFIGURED"
  fi
fi

NOTIFIER_COUNT=$(echo "$NOTIFIER_JSON" | jq 'length' 2>/dev/null || echo 0)

if [[ "$NOTIFIER_COUNT" -eq 0 ]]; then
  echo "$LOG_PREFIX No notifiers configured, using default (openclaw)" >&2
  NOTIFIER_JSON='[{"type":"openclaw","config":{}}]'
  NOTIFIER_COUNT=1
fi

# === Dispatch to each notifier ===
SUCCESS=0
FAILED=0

for i in $(seq 0 $((NOTIFIER_COUNT - 1))); do
  NTYPE=$(echo "$NOTIFIER_JSON" | jq -r ".[$i].type // \"\"" 2>/dev/null || echo "")
  NCONFIG=$(echo "$NOTIFIER_JSON" | jq -c ".[$i].config // {}" 2>/dev/null || echo "{}")

  if [[ -z "$NTYPE" ]]; then
    echo "$LOG_PREFIX Skipping notifier $i (no type)" >&2
    continue
  fi

  # Check events filter: default is ["complete"] only
  NEVENTS=$(echo "$NOTIFIER_JSON" | jq -r ".[$i].events // [\"complete\"] | .[]" 2>/dev/null || echo "complete")
  if ! echo "$NEVENTS" | grep -qx "$EVENT_TYPE"; then
    echo "$LOG_PREFIX Skipping notifier $NTYPE (event '$EVENT_TYPE' not in events list)" >&2
    continue
  fi

  NOTIFIER_SCRIPT="$NOTIFIERS_DIR/${NTYPE}.sh"
  if [[ ! -f "$NOTIFIER_SCRIPT" ]]; then
    echo "$LOG_PREFIX Unknown notifier type: $NTYPE (no $NOTIFIER_SCRIPT)" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  # Idempotency: check if this notifier type already sent
  # Each notifier manages its own notified.* field in meta.json.
  # openclaw notifier checks internally; webhook notifiers checked here.
  if [[ "$NTYPE" == "webhook" ]]; then
    # Use template name as the notified key (e.g., notified.webhook_slack)
    TEMPLATE_NAME=$(echo "$NCONFIG" | jq -r '.template // "generic"' 2>/dev/null || echo "generic")
    NOTIFIED_KEY="webhook_${TEMPLATE_NAME}"
    ALREADY_SENT=$(jq -r ".notified.${NOTIFIED_KEY} // false" "$META_FILE" 2>/dev/null || echo "false")
    if [[ "$ALREADY_SENT" == "true" ]]; then
      echo "$LOG_PREFIX Skipping $NTYPE ($TEMPLATE_NAME): already sent (idempotent)" >&2
      SUCCESS=$((SUCCESS + 1))
      continue
    fi
  fi

  # Source notifier in a subshell to isolate function definitions
  (
    source "$NOTIFIER_SCRIPT"
    if declare -f notifier_send > /dev/null 2>&1; then
      notifier_send "$META_FILE" "$NCONFIG" "$EVENT_TYPE"
    else
      echo "$LOG_PREFIX Notifier $NTYPE missing notifier_send()" >&2
      exit 1
    fi
  )

  if [[ $? -eq 0 ]]; then
    SUCCESS=$((SUCCESS + 1))
    # Track webhook notifications in meta.json for idempotency
    if [[ "$NTYPE" == "webhook" ]]; then
      TEMPLATE_NAME=$(echo "$NCONFIG" | jq -r '.template // "generic"' 2>/dev/null || echo "generic")
      update_notified "webhook_${TEMPLATE_NAME}"
    fi
  else
    FAILED=$((FAILED + 1))
  fi
done

echo "$LOG_PREFIX Done: $SUCCESS/$NOTIFIER_COUNT succeeded, $FAILED failed" >&2
