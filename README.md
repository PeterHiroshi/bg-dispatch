# bg-dispatch

**Fire-and-forget background dispatch for heavy coding agents.**

Launch tools like [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Aider](https://aider.chat), [Codex CLI](https://github.com/openai/codex), or any long-running coding CLI in the background. Your [OpenClaw](https://github.com/openclaw/openclaw) session stays free — zero tokens consumed while the agent works. When it's done, pluggable notifiers wake your agent and alert your team.

## The Problem

Heavy "vibe coding" tools can run for minutes to hours. If your AI assistant waits for them to finish, it's blocked — burning tokens on polling or sitting idle. You can't talk to it, and it can't help you with anything else.

## The Solution

```
You (chat) → OpenClaw → bg-dispatch → Coding Agent (background)
                ↑                              │
                └──── pluggable notifiers ──────┘
                     (zero wait, zero poll)
```

1. **Dispatch** — `bg-dispatch` launches the coding agent in the background and returns immediately
2. **Work** — The agent runs independently, tracking progress in `data/tasks/<task-id>/`
3. **Notify** — On completion, pluggable notifiers wake OpenClaw + alert your team (Slack, Feishu, Discord, etc.)
4. **Resume** — If interrupted (container reset, crash), the agent resumes from centralized task data

## Features

- 🚀 **Fire-and-forget** — Main session freed instantly, zero token burn
- 🔔 **Pluggable notifications** — OpenClaw wake, Slack, Feishu, Discord, custom commands
- 🔌 **Adapter pattern** — Claude Code, Aider, Codex CLI built-in; add your own easily
- 🔄 **Resumable** — Centralized task data survives crashes and container resets
- 🐕 **Watchdog** — Auto-kills stalled tasks, enforces max runtime
- 🔒 **Workdir locking** — Prevents duplicate agents on the same project

## Quick Start

### 1. Install

```bash
git clone https://github.com/PeterHiroshi/bg-dispatch.git
cd bg-dispatch
bash install.sh
export PATH="$(pwd):$PATH"
```

### 2. Configure Notifications

Create `bg-dispatch.json`:

```json
{
  "notifiers": [
    { "type": "openclaw", "config": { "session": "main" } },
    { "type": "webhook",  "config": { "url_env": "SLACK_WEBHOOK_URL", "template": "slack" } }
  ]
}
```

### 3. Dispatch a Task

```bash
bg-dispatch \
  --adapter claude-code \
  --prompt "Build a REST API with user auth and rate limiting" \
  --name "user-auth-api" \
  --workdir /path/to/project
```

Returns immediately. Your session is free.

### 4. Get Notified

When complete, OpenClaw receives a system event and Slack gets a rich notification:

```
✅ bg-dispatch: user-auth-api
Status: done (exit 0)  |  Duration: 23m41s
Model: claude-opus-4-1  |  Project: my-api
```

### 5. Resume After Interruption

```bash
bg-dispatch --adapter claude-code --workdir /path/to/project --resume --force
```

## Adapters

| Adapter | Tool | Status |
|---------|------|--------|
| `claude-code` | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | ✅ Built-in |
| `aider` | [Aider](https://aider.chat) | ✅ Built-in |
| `codex` | [Codex CLI](https://github.com/openai/codex) | ✅ Built-in |
| Custom | Your tool | 📝 [Write an adapter](docs/writing-adapters.md) |

### Claude Code

```bash
bg-dispatch -a claude-code \
  -p "Implement Stripe payment module" \
  -n "payments" -w ./project \
  --agent-teams --model "claude-opus-4-1-20250805"
```

### Aider

```bash
bg-dispatch -a aider \
  -p "Refactor DB layer for connection pooling" \
  -n "db-refactor" -w ./project \
  --opt test-cmd="pytest" --opt lint-cmd="ruff check"
```

### Codex CLI

```bash
bg-dispatch -a codex \
  -p "Add test coverage for auth module" \
  -n "auth-tests" -w ./project
```

## CLI Monitoring (bgd)

The `bgd` CLI tool provides interactive monitoring for background tasks.

```bash
bgd tasks                         # List all tasks with status table
bgd tasks --status running        # Filter by status
bgd status                        # Quick overview with counts + active details
bgd show <task>                   # Detailed view (partial name match OK)
bgd logs <task>                   # Last 50 lines of output (ANSI stripped)
bgd logs <task> -f                # Follow output in real-time
bgd progress <task>               # Show progress.md from task data
bgd cancel <task>                 # Cancel a running task
bgd resume <task>                 # Resume interrupted task
bgd clean                         # Remove done/killed tasks older than 24h
bgd clean --all --dry-run         # Preview full cleanup
```

Status icons: 🏃 running, ✅ done (exit 0), ⚠️ done (exit != 0), ❌ killed, ⏸️ cancelled

## Notification System

### Built-in Notifiers

| Notifier | Description | Config |
|----------|-------------|--------|
| `openclaw` | Wake OpenClaw session via system event | `session` |
| `webhook` | POST to Slack/Feishu/Discord/any URL | `url` or `url_env`, `template` |
| `command` | Run any shell command | `command`, `timeout` |

### Webhook Templates

```json
{ "type": "webhook", "config": { "url_env": "SLACK_WEBHOOK_URL", "template": "slack" } }
{ "type": "webhook", "config": { "url_env": "FEISHU_WEBHOOK_URL", "template": "feishu" } }
{ "type": "webhook", "config": { "url_env": "DISCORD_WEBHOOK_URL", "template": "discord" } }
{ "type": "webhook", "config": { "url": "https://example.com/hook", "template": "generic" } }
```

### Custom Command Notifier

```json
{
  "type": "command",
  "config": {
    "command": "curl -X POST https://my-api.com/tasks -d '{\"task\": \"'$BGD_TASK_NAME'\", \"status\": \"'$BGD_STATUS'\"}'",
    "timeout": 30
  }
}
```

Environment variables available in commands:
`BGD_TASK_NAME`, `BGD_STATUS`, `BGD_EXIT_CODE`, `BGD_WORKDIR`, `BGD_MODEL`, `BGD_ADAPTER`, `BGD_STARTED_AT`, `BGD_COMPLETED_AT`, `BGD_META_FILE`, `BGD_PROGRESS_FILE`

### Writing Custom Notifiers

Create a script in `notifiers/` with two functions:

```bash
# notifiers/my-notifier.sh
notifier_validate() { ... }
notifier_send() {
  local META_FILE="$1" CONFIG="$2"
  # Read task info from META_FILE, send notification
}
```

Then add to `bg-dispatch.json`:
```json
{ "type": "my-notifier", "config": { ... } }
```

### Config File Locations

Searched in order (first found wins):
1. `<workdir>/bg-dispatch.json` — per-project
2. `<data-dir>/bg-dispatch.json` — instance
3. `<install-dir>/bg-dispatch.json` — global
4. `~/.bg-dispatch.json` — user home

## Architecture

```
bg-dispatch (orchestrator)
├── adapters/          # Agent launchers
│   ├── claude-code.sh
│   ├── aider.sh
│   └── codex.sh
├── notifiers/         # Pluggable notifications
│   ├── openclaw.sh    # Wake OpenClaw session (direct system event)
│   ├── webhook.sh     # Slack/Feishu/Discord/generic
│   └── command.sh     # Custom commands
├── hooks/
│   └── on-complete.sh # Claude Code Stop hook → notify.sh
├── notify.sh          # Notification dispatcher
├── watchdog.sh        # Stall detection + max runtime
└── task-check.mjs     # Heartbeat integration
```

### Notification Flow (Three-Layer Guarantee)

```
Agent completes
  ├─→ Hook fires (primary) ──→ notify.sh ──→ [openclaw, webhook, command, ...]
  ├─→ Process fallback ─────→ notify.sh
  └─→ Watchdog (safety net) → notify.sh  (if hook + fallback both miss)
```

### Progress Tracking

All task data is centralized in `data/tasks/<task-id>/` — outside the project workdir to avoid polluting repos (especially open-source):

```
data/tasks/<task-id>/
├── meta.json        # Task definition (prompt, adapter, config, status)
├── progress.md      # Living progress doc (agent updates this)
├── output.txt       # Agent output log
└── watchdog.log     # Watchdog monitoring log
```

This enables **resumability**: if the container resets, `--resume` searches task data by workdir match and the agent picks up where it left off. Legacy `.dev-progress/` directories are auto-migrated.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BG_DISPATCH_DIR` | Script location | Base directory |
| `BG_DISPATCH_DATA_DIR` | `$BG_DISPATCH_DIR/data` | Runtime data |
| `BG_DISPATCH_STALL_TIMEOUT` | `900` (15 min) | Inactivity kill threshold |
| `BG_DISPATCH_MAX_RUNTIME` | `7200` (2 hours) | Maximum total runtime |

### CLI Reference

```
bg-dispatch [OPTIONS]

Required:
  -a, --adapter NAME         Adapter (claude-code, aider, codex)
  -p, --prompt TEXT          Task prompt (unless --resume)

Options:
  -n, --name NAME            Task name [default: task-<timestamp>]
  -w, --workdir DIR          Working directory [default: cwd]
  --resume                   Resume from data/tasks/
  --force                    Kill existing task for workdir
  --model MODEL              Model override
  --allowed-tools TOOLS      Allowed tools (adapter-specific)
  --agent-teams              Enable multi-agent mode
  --stall-timeout SECS       Stall timeout [default: 900]
  --max-runtime SECS         Max runtime [default: 7200]
  --callback-session KEY     OpenClaw session key
  --opt KEY=VALUE            Adapter-specific option (repeatable)
```

## OpenClaw Skill Integration

bg-dispatch works as a standalone tool or as an [OpenClaw Skill](https://docs.openclaw.ai/skills):

```bash
# Symlink into your workspace
ln -s /path/to/bg-dispatch ~/.openclaw/workspace/skills/bg-dispatch
```

See [SKILL.md](SKILL.md) for the full skill definition with agent-oriented instructions.

## Roadmap

- [x] Core dispatcher with adapter pattern
- [x] Claude Code adapter
- [x] Aider adapter
- [x] Codex CLI adapter
- [x] Pluggable notification system (OpenClaw, Slack, Feishu, Discord, custom)
- [x] Watchdog with three-layer notification guarantee
- [x] Resume support via centralized task data
- [ ] Cursor Agent adapter (when headless CLI available)
- [ ] Web dashboard for task monitoring
- [ ] OpenClaw Skill marketplace listing (ClawhHub)
- [ ] Multi-task parallel dispatch orchestration

## License

MIT — see [LICENSE](LICENSE).

## Credits

Born from [forge-dispatch](https://github.com/PeterHiroshi/forge-workspace), battle-tested in production with 100+ Claude Code dispatches. Extracted and generalized for the community.
