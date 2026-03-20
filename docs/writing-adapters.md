# Writing Adapters

bg-dispatch uses an adapter pattern to support different coding agents. Each adapter is a shell script in `adapters/` that implements a standard interface.

## Interface

An adapter script must define these functions:

### `adapter_validate()`

**Required.** Check prerequisites and exit 1 if something is missing.

```bash
adapter_validate() {
  if [[ ! -x "/usr/bin/my-agent" ]]; then
    echo "Error: my-agent not found" >&2
    exit 1
  fi
}
```

### `build_command()`

**Required.** Print the command to launch the agent to stdout. The command will be executed inside a `script -q -c "..." /dev/null` wrapper for PTY.

Available environment variables:
- `$BG_DISPATCH_PROMPT` — The task prompt
- `$BG_DISPATCH_MODEL` — Model override (may be empty)
- `$BG_DISPATCH_ALLOWED_TOOLS` — Allowed tools (may be empty)
- `$BG_DISPATCH_AGENT_TEAMS` — "true" if teams mode requested
- `$BG_DISPATCH_WORKDIR` — Working directory
- `$BG_DISPATCH_OPT_*` — Adapter-specific options (from `--opt key=value`)

```bash
build_command() {
  local CMD
  CMD=$(printf '%q -p %q' "/usr/bin/my-agent" "$BG_DISPATCH_PROMPT")
  [[ -n "$BG_DISPATCH_MODEL" ]] && CMD+=$(printf ' --model %q' "$BG_DISPATCH_MODEL")
  echo "$CMD"
}
```

### `get_env()`

**Optional.** Print `export VAR=VALUE` statements for environment variables the agent needs. These are written into the launcher script.

```bash
get_env() {
  if [[ "${BG_DISPATCH_AGENT_TEAMS:-}" == "true" ]]; then
    echo 'export MY_AGENT_PARALLEL=1'
  fi
}
```

### `adapter_effective_model()`

**Optional.** Print the resolved model ID to stdout. Used for reporting. If not defined, falls back to `$BG_DISPATCH_MODEL` or `(default)`.

```bash
adapter_effective_model() {
  if [[ -n "$BG_DISPATCH_MODEL" ]]; then
    echo "$BG_DISPATCH_MODEL"
  else
    echo "gpt-4o"  # my-agent's default
  fi
}
```

## Example: Aider Adapter

```bash
#!/usr/bin/env bash
# adapters/aider.sh

AIDER_BIN="${AIDER_BIN:-$(command -v aider 2>/dev/null || echo aider)}"

adapter_validate() {
  if ! command -v "$AIDER_BIN" &>/dev/null; then
    echo "Error: aider not found. Install: pip install aider-chat" >&2
    exit 1
  fi
}

build_command() {
  local CMD
  CMD=$(printf '%q --message %q --yes-always --no-auto-commits' "$AIDER_BIN" "$BG_DISPATCH_PROMPT")
  [[ -n "$BG_DISPATCH_MODEL" ]] && CMD+=$(printf ' --model %q' "$BG_DISPATCH_MODEL")
  echo "$CMD"
}

adapter_effective_model() {
  echo "${BG_DISPATCH_MODEL:-claude-3.5-sonnet}"
}
```

## Hook Integration

If your agent supports hooks or callbacks, you can extend `hooks/on-complete.sh` or create an agent-specific hook. The key requirement is that on completion, the hook should:

1. Update `data/tasks/<task-id>/meta.json` with `status: "done"`
2. Wake OpenClaw via `openclaw cron add --system-event "..."`

If the agent doesn't support hooks, the watchdog will detect process exit and handle notification as a fallback.

## Testing Your Adapter

```bash
# Validate
source adapters/my-agent.sh
adapter_validate

# Check command
export BG_DISPATCH_PROMPT="Hello world"
export BG_DISPATCH_MODEL=""
export BG_DISPATCH_WORKDIR="/tmp/test"
build_command
# Should print: /usr/bin/my-agent -p 'Hello world' ...

# Dry run
bg-dispatch -a my-agent -p "Test task" -w /tmp/test-project
```
