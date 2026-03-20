# Writing Adapters

bg-dispatch uses an adapter pattern to support different coding agents. Each adapter is a shell script in `adapters/` that implements a standard interface.

## Interface

An adapter script must define these functions:

### `adapter_validate()` (required)

Check prerequisites and exit 1 if something is missing.

```bash
adapter_validate() {
  if [[ ! -x "/usr/bin/my-agent" ]]; then
    echo "Error: my-agent not found" >&2
    exit 1
  fi
}
```

### `build_command()` (required)

Print the command to launch the agent to stdout. Executed inside `script -q -c "..." /dev/null` for PTY.

Available environment variables:
- `$BG_DISPATCH_PROMPT` — Task prompt
- `$BG_DISPATCH_MODEL` — Model override (may be empty)
- `$BG_DISPATCH_ALLOWED_TOOLS` — Allowed tools (may be empty)
- `$BG_DISPATCH_AGENT_TEAMS` — "true" if teams mode requested
- `$BG_DISPATCH_WORKDIR` — Working directory
- `$BG_DISPATCH_OPT_*` — Adapter-specific options from `--opt key=value`

```bash
build_command() {
  local CMD
  CMD=$(printf '%q -p %q' "/usr/bin/my-agent" "$BG_DISPATCH_PROMPT")
  [[ -n "$BG_DISPATCH_MODEL" ]] && CMD+=$(printf ' --model %q' "$BG_DISPATCH_MODEL")
  echo "$CMD"
}
```

### `get_env()` (optional)

Print `export VAR=VALUE` statements for the launcher script.

```bash
get_env() {
  if [[ "${BG_DISPATCH_AGENT_TEAMS:-}" == "true" ]]; then
    echo 'export MY_AGENT_PARALLEL=1'
  fi
}
```

### `adapter_effective_model()` (optional)

Print the resolved model ID. Used for reporting.

```bash
adapter_effective_model() {
  echo "${BG_DISPATCH_MODEL:-gpt-4o}"
}
```

## Complete Example: Custom Agent

```bash
#!/usr/bin/env bash
# adapters/my-agent.sh

MY_AGENT_BIN="${MY_AGENT_BIN:-$(command -v my-agent 2>/dev/null || echo my-agent)}"

adapter_validate() {
  if ! command -v "$MY_AGENT_BIN" &>/dev/null; then
    echo "Error: my-agent not found" >&2
    exit 1
  fi
}

build_command() {
  local CMD
  CMD=$(printf '%q --task %q --non-interactive' "$MY_AGENT_BIN" "$BG_DISPATCH_PROMPT")
  [[ -n "$BG_DISPATCH_MODEL" ]] && CMD+=$(printf ' --model %q' "$BG_DISPATCH_MODEL")

  # Adapter-specific option
  local MAX_STEPS="${BG_DISPATCH_OPT_max_steps:-100}"
  CMD+=$(printf ' --max-steps %q' "$MAX_STEPS")

  echo "$CMD"
}

get_env() {
  echo 'export MY_AGENT_NO_INTERACTIVE=1'
}

adapter_effective_model() {
  echo "${BG_DISPATCH_MODEL:-default-model}"
}
```

Usage:
```bash
bg-dispatch -a my-agent -p "Fix the login bug" -w ./project --opt max-steps=50
```

## Hook Integration

If your agent supports hooks/callbacks on completion, extend `hooks/on-complete.sh` or create an agent-specific hook. The key requirement:

1. Update `data/tasks/<task-id>/meta.json` with `status: "done"`
2. Call `notify.sh` to dispatch all configured notifiers

If the agent doesn't support hooks, the watchdog detects process exit and handles notification.

## Notification System

Adapters don't need to worry about notifications — that's handled by the notifier system (`notify.sh` + `notifiers/`). When a task completes:

1. Hook (or watchdog) calls `notify.sh` with the task's `meta.json`
2. `notify.sh` reads `bg-dispatch.json` for configured notifiers
3. Each notifier is called in sequence (OpenClaw, webhooks, commands, etc.)

See [README.md](../README.md#notification-system) for notifier configuration.

## Testing Your Adapter

```bash
# 1. Validate
source adapters/my-agent.sh
adapter_validate

# 2. Check command output
export BG_DISPATCH_PROMPT="Hello world"
export BG_DISPATCH_MODEL=""
export BG_DISPATCH_WORKDIR="/tmp/test"
build_command
# → /usr/bin/my-agent --task 'Hello world' --non-interactive

# 3. Dry run
bg-dispatch -a my-agent -p "Test task" -w /tmp/test-project
```
