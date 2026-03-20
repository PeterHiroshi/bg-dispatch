#!/usr/bin/env bash
#
# notify.sh — bg-dispatch notification dispatcher
#
# Reads notifier config from bg-dispatch.json (or defaults to openclaw notifier),
# then calls each configured notifier in order.
#
# Usage: bash notify.sh <meta.json> [config_file]
#
# Config format (bg-dispatch.json):
# {
#   "notifiers": [
#     { "type": "openclaw", "config": { "session": "main" } },
#     { "type": "webhook",  "config": { "url_env": "SLACK_WEBHOOK_URL", "template": "slack" } },
#     { "type": "webhook",  "config": { "url_env": "FEISHU_WEBHOOK_URL", "template": "feishu" } },
#     { "type": "command",  "config": { "command": "echo $BGD_TASK_NAME done!" } }
#   ]
# }
#

set -uo pipefail

BG_DISPATCH_DIR="${BG_DISPATCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
NOTIFIERS_DIR="$BG_DISPATCH_DIR/notifiers"

META_FILE="${1:-}"
CONFIG_FILE="${2:-}"

if [[ -z "$META_FILE" ]]; then
  echo "Usage: notify.sh <meta.json> [config_file]" >&2
  exit 1
fi

if [[ ! -f "$META_FILE" ]]; then
  echo "Error: meta.json not found: $META_FILE" >&2
  exit 1
fi

LOG_PREFIX="[bg-dispatch-notify]"

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

  NOTIFIER_SCRIPT="$NOTIFIERS_DIR/${NTYPE}.sh"
  if [[ ! -f "$NOTIFIER_SCRIPT" ]]; then
    echo "$LOG_PREFIX Unknown notifier type: $NTYPE (no $NOTIFIER_SCRIPT)" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  # Source notifier in a subshell to isolate function definitions
  (
    source "$NOTIFIER_SCRIPT"
    if declare -f notifier_send > /dev/null 2>&1; then
      notifier_send "$META_FILE" "$NCONFIG"
    else
      echo "$LOG_PREFIX Notifier $NTYPE missing notifier_send()" >&2
      exit 1
    fi
  )

  if [[ $? -eq 0 ]]; then
    SUCCESS=$((SUCCESS + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done

echo "$LOG_PREFIX Done: $SUCCESS/$NOTIFIER_COUNT succeeded, $FAILED failed" >&2
