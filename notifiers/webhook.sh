#!/usr/bin/env bash
#
# webhook.sh — bg-dispatch notifier: Generic webhook (Slack, Feishu, Discord, etc.)
#
# Sends a POST request with task completion info to any webhook URL.
# Supports custom payload templates for different platforms.
#
# Config keys (in bg-dispatch.json notifiers[].config):
#   url        — Webhook URL (required, or use env var below)
#   url_env    — Environment variable name containing the URL (e.g., "SLACK_WEBHOOK_URL")
#   template   — Payload template: "slack", "feishu", "discord", or "generic" (default)
#   secret     — Signing secret for Feishu webhooks (optional)
#   secret_env — Env var name for signing secret (optional)
#

notifier_validate() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl required for webhook notifier" >&2
    return 1
  fi
}

_resolve_config() {
  local CONFIG="$1"
  local KEY="$2"
  local ENV_KEY="$3"

  local VAL
  VAL=$(echo "$CONFIG" | jq -r ".${KEY} // \"\"" 2>/dev/null || echo "")
  if [[ -z "$VAL" ]] && [[ -n "$ENV_KEY" ]]; then
    local ENV_NAME
    ENV_NAME=$(echo "$CONFIG" | jq -r ".${ENV_KEY} // \"\"" 2>/dev/null || echo "")
    if [[ -n "$ENV_NAME" ]]; then
      VAL="${!ENV_NAME:-}"
    fi
  fi
  echo "$VAL"
}

_build_slack_payload() {
  local TASK_NAME="$1" STATUS="$2" DURATION="$3" WORKDIR="$4" MODEL="$5" EXIT_CODE="$6"

  local EMOJI="✅"
  [[ "$EXIT_CODE" != "0" ]] && EMOJI="❌"
  [[ "$STATUS" == "killed" ]] && EMOJI="🔴"

  cat <<EOF
{
  "blocks": [
    {
      "type": "header",
      "text": {"type": "plain_text", "text": "${EMOJI} bg-dispatch: ${TASK_NAME}"}
    },
    {
      "type": "section",
      "fields": [
        {"type": "mrkdwn", "text": "*Status:* ${STATUS} (exit ${EXIT_CODE})"},
        {"type": "mrkdwn", "text": "*Duration:* ${DURATION}"},
        {"type": "mrkdwn", "text": "*Model:* ${MODEL}"},
        {"type": "mrkdwn", "text": "*Project:* $(basename "$WORKDIR")"}
      ]
    }
  ]
}
EOF
}

_build_feishu_payload() {
  local TASK_NAME="$1" STATUS="$2" DURATION="$3" WORKDIR="$4" MODEL="$5" EXIT_CODE="$6"

  local EMOJI="✅"
  local STATUS_TEXT="成功"
  if [[ "$EXIT_CODE" != "0" ]]; then EMOJI="⚠️"; STATUS_TEXT="完成 (exit $EXIT_CODE)"; fi
  if [[ "$STATUS" == "killed" ]]; then EMOJI="🔴"; STATUS_TEXT="已终止"; fi

  cat <<EOF
{
  "msg_type": "post",
  "content": {
    "post": {
      "zh_cn": {
        "title": "🔨 bg-dispatch 任务${STATUS_TEXT}",
        "content": [[
          {"tag":"text","text":"📋 任务: ${TASK_NAME}\n"},
          {"tag":"text","text":"📊 状态: ${EMOJI} ${STATUS_TEXT}\n"},
          {"tag":"text","text":"⏱️ 耗时: ${DURATION}\n"},
          {"tag":"text","text":"📂 项目: $(basename "$WORKDIR")\n"},
          {"tag":"text","text":"🤖 模型: ${MODEL}\n"}
        ]]
      }
    }
  }
}
EOF
}

_build_discord_payload() {
  local TASK_NAME="$1" STATUS="$2" DURATION="$3" WORKDIR="$4" MODEL="$5" EXIT_CODE="$6"

  local COLOR=3066993  # green
  [[ "$EXIT_CODE" != "0" ]] && COLOR=15158332  # red
  [[ "$STATUS" == "killed" ]] && COLOR=10038562  # dark red

  cat <<EOF
{
  "embeds": [{
    "title": "🔨 bg-dispatch: ${TASK_NAME}",
    "color": ${COLOR},
    "fields": [
      {"name": "Status", "value": "${STATUS} (exit ${EXIT_CODE})", "inline": true},
      {"name": "Duration", "value": "${DURATION}", "inline": true},
      {"name": "Model", "value": "${MODEL}", "inline": true},
      {"name": "Project", "value": "$(basename "$WORKDIR")", "inline": true}
    ]
  }]
}
EOF
}

_build_generic_payload() {
  local TASK_NAME="$1" STATUS="$2" DURATION="$3" WORKDIR="$4" MODEL="$5" EXIT_CODE="$6"

  cat <<EOF
{
  "event": "task_complete",
  "task_name": "${TASK_NAME}",
  "status": "${STATUS}",
  "exit_code": ${EXIT_CODE},
  "duration": "${DURATION}",
  "workdir": "${WORKDIR}",
  "model": "${MODEL}"
}
EOF
}

_calc_duration() {
  local STARTED="$1" COMPLETED="$2"
  local START_EPOCH END_EPOCH DIFF HOURS MINS SECS
  START_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)
  END_EPOCH=$(date -d "$COMPLETED" +%s 2>/dev/null || echo 0)
  if [[ "$START_EPOCH" -gt 0 ]] && [[ "$END_EPOCH" -gt 0 ]]; then
    DIFF=$((END_EPOCH - START_EPOCH))
    HOURS=$((DIFF / 3600))
    MINS=$(( (DIFF % 3600) / 60 ))
    SECS=$((DIFF % 60))
    if [[ "$HOURS" -gt 0 ]]; then echo "${HOURS}h${MINS}m${SECS}s"
    elif [[ "$MINS" -gt 0 ]]; then echo "${MINS}m${SECS}s"
    else echo "${SECS}s"
    fi
  else
    echo "unknown"
  fi
}

notifier_send() {
  local META_FILE="$1"
  local CONFIG="$2"

  local URL
  URL=$(_resolve_config "$CONFIG" "url" "url_env")
  if [[ -z "$URL" ]]; then
    echo "[webhook-notifier] No URL configured" >&2
    return 1
  fi

  local TEMPLATE
  TEMPLATE=$(echo "$CONFIG" | jq -r '.template // "generic"' 2>/dev/null || echo "generic")

  # Read task metadata
  local TASK_NAME STATUS WORKDIR MODEL EXIT_CODE STARTED_AT COMPLETED_AT
  TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE")
  STATUS=$(jq -r '.status // "unknown"' "$META_FILE")
  WORKDIR=$(jq -r '.workdir // ""' "$META_FILE")
  MODEL=$(jq -r '.effective_model // .model // "unknown"' "$META_FILE")
  EXIT_CODE=$(jq -r '.exit_code // "?"' "$META_FILE")
  STARTED_AT=$(jq -r '.started_at // ""' "$META_FILE")
  COMPLETED_AT=$(jq -r '.completed_at // ""' "$META_FILE")

  local DURATION
  DURATION=$(_calc_duration "$STARTED_AT" "$COMPLETED_AT")

  # Build payload
  local PAYLOAD
  case "$TEMPLATE" in
    slack)   PAYLOAD=$(_build_slack_payload "$TASK_NAME" "$STATUS" "$DURATION" "$WORKDIR" "$MODEL" "$EXIT_CODE") ;;
    feishu)  PAYLOAD=$(_build_feishu_payload "$TASK_NAME" "$STATUS" "$DURATION" "$WORKDIR" "$MODEL" "$EXIT_CODE") ;;
    discord) PAYLOAD=$(_build_discord_payload "$TASK_NAME" "$STATUS" "$DURATION" "$WORKDIR" "$MODEL" "$EXIT_CODE") ;;
    *)       PAYLOAD=$(_build_generic_payload "$TASK_NAME" "$STATUS" "$DURATION" "$WORKDIR" "$MODEL" "$EXIT_CODE") ;;
  esac

  # Feishu signing
  local SECRET
  SECRET=$(_resolve_config "$CONFIG" "secret" "secret_env")
  if [[ -n "$SECRET" ]] && [[ "$TEMPLATE" == "feishu" ]]; then
    local TS SIGN
    TS=$(date +%s)
    SIGN=$(printf '%b' "${TS}\n${SECRET}" | openssl dgst -sha256 -hmac "$SECRET" -binary | openssl base64 2>/dev/null)
    PAYLOAD=$(echo "$PAYLOAD" | jq --arg ts "$TS" --arg sign "$SIGN" '. + {timestamp: $ts, sign: $sign}')
  fi

  # Send
  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null)

  if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "204" ]]; then
    echo "[webhook-notifier] Sent OK ($TEMPLATE → $HTTP_CODE)" >&2
  else
    echo "[webhook-notifier] Failed ($TEMPLATE → HTTP $HTTP_CODE)" >&2
    return 1
  fi
}
