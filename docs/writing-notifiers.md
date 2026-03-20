# Writing Notifiers

bg-dispatch uses a pluggable notifier system. Each notifier is a shell script in `notifiers/` that implements a standard interface.

## Interface

A notifier script must define:

### `notifier_validate()` (required)

Check prerequisites. Return 0 if OK, 1 on failure. Non-fatal failures are OK — the notifier will be skipped at runtime.

```bash
notifier_validate() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl required" >&2
    return 1
  fi
}
```

### `notifier_send()` (required)

Send the notification. Receives:
- `$1` — Path to task `meta.json`
- `$2` — JSON string with notifier config from `bg-dispatch.json`

```bash
notifier_send() {
  local META_FILE="$1"
  local CONFIG="$2"

  local TASK_NAME=$(jq -r '.task_name' "$META_FILE")
  local MY_OPTION=$(echo "$CONFIG" | jq -r '.my_option // "default"')

  # Send notification...
  echo "[my-notifier] Sent for $TASK_NAME" >&2
}
```

## Task Metadata (meta.json)

Available fields in `meta.json`:

```json
{
  "task_id": "auth-api-1710921600",
  "task_name": "auth-api",
  "started_at": "2025-03-20T08:00:00Z",
  "completed_at": "2025-03-20T08:23:41Z",
  "workdir": "/path/to/project",
  "adapter": "claude-code",
  "model": "",
  "effective_model": "claude-opus-4-1-20250805",
  "agent_teams": false,
  "exit_code": 0,
  "status": "done",
  "is_resume": false,
  "completion_trigger": "hook"
}
```

## Configuration

Notifiers are configured in `bg-dispatch.json`:

```json
{
  "notifiers": [
    {
      "type": "my-notifier",
      "config": {
        "my_option": "value",
        "api_key_env": "MY_API_KEY"
      }
    }
  ]
}
```

### Pattern: Env Var References

Use `*_env` config keys to reference environment variables (keeps secrets out of config files):

```bash
# In your notifier:
local API_KEY_ENV=$(echo "$CONFIG" | jq -r '.api_key_env // ""')
local API_KEY="${!API_KEY_ENV:-}"
```

## Complete Example: Email Notifier

```bash
#!/usr/bin/env bash
# notifiers/email.sh

notifier_validate() {
  if ! command -v sendmail >/dev/null 2>&1 && ! command -v mail >/dev/null 2>&1; then
    echo "Warning: no mail command found" >&2
    return 0  # non-fatal
  fi
}

notifier_send() {
  local META_FILE="$1"
  local CONFIG="$2"

  local TO=$(echo "$CONFIG" | jq -r '.to // ""')
  if [[ -z "$TO" ]]; then
    echo "[email-notifier] No 'to' address configured" >&2
    return 1
  fi

  local TASK_NAME=$(jq -r '.task_name' "$META_FILE")
  local STATUS=$(jq -r '.status' "$META_FILE")
  local WORKDIR=$(jq -r '.workdir' "$META_FILE")

  echo "Task $TASK_NAME completed ($STATUS) in $WORKDIR" | \
    mail -s "bg-dispatch: $TASK_NAME $STATUS" "$TO" 2>/dev/null

  echo "[email-notifier] Sent to $TO" >&2
}
```

Config:
```json
{ "type": "email", "config": { "to": "dev@example.com" } }
```

## Multiple Notifiers

You can configure multiple notifiers of the same type (e.g., multiple webhooks):

```json
{
  "notifiers": [
    { "type": "openclaw", "config": {} },
    { "type": "webhook", "config": { "url_env": "SLACK_WEBHOOK_URL", "template": "slack" } },
    { "type": "webhook", "config": { "url_env": "FEISHU_WEBHOOK_URL", "template": "feishu" } },
    { "type": "email", "config": { "to": "alerts@example.com" } }
  ]
}
```

All notifiers fire in order. Failures in one don't block others.
