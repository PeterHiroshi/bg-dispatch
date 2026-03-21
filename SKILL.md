---
name: bg-dispatch
description: Fire-and-forget background dispatch for heavy coding agents (Claude Code, Aider, Codex CLI, etc.) with pluggable notification system. Agent runs in background, main session stays free. Resumable across container resets.
---

# bg-dispatch — OpenClaw Skill

Fire-and-forget background dispatch for heavy coding agents. Launch Claude Code, Aider, Codex CLI — or any long-running coding tool — in the background. Your OpenClaw session stays free with zero token burn. On completion, pluggable notifiers wake your agent and/or notify your team.

## When to Use

**Use bg-dispatch for:**
- Any coding task expected to take more than a few minutes
- Building features, fixing bugs, refactoring, writing tests
- Heavy "vibe coding" sessions that would block your main session
- Tasks where you want your agent available for other conversations

**Handle directly (no dispatch):**
- Pure documentation edits (README, config files)
- Quick one-liner shell commands
- Tasks where you need the result immediately

## Quick Reference

### Dispatch a New Task

```bash
bg-dispatch \
  --adapter claude-code \
  --prompt "Build a REST API with user authentication and rate limiting" \
  --name "user-auth-api" \
  --workdir /path/to/project
```

### Resume After Interruption

```bash
bg-dispatch --adapter claude-code --workdir /path/to/project --resume --force
```

### Check Task Status (Heartbeat)

```bash
node task-check.mjs --data-dir ./data --projects-dir /path/to/projects
```

## Available Adapters

### claude-code (Claude Code)

The primary adapter. Supports Superpowers plugin, Agent Teams, and Bedrock.

```bash
bg-dispatch -a claude-code \
  -p "Implement the payment module with Stripe integration" \
  -n "payment-stripe" \
  -w /path/to/project \
  --model "claude-opus-4-1-20250805" \
  --agent-teams \
  --allowed-tools "Bash(*),Read,Write,Edit,MultiEdit,Glob,Grep,Skill,Agent"
```

**Adapter-specific options:**
- `--opt permission-mode=none` — Claude Code permission mode

**Environment variables:**
- `CLAUDE_BIN` — Path to claude binary (default: auto-detect)
- `CLAUDE_CODE_USE_BEDROCK=1` — Use AWS Bedrock
- `AWS_PROFILE`, `AWS_REGION` — Bedrock auth

### aider (Aider)

```bash
bg-dispatch -a aider \
  -p "Refactor the database layer to use connection pooling" \
  -n "db-pool-refactor" \
  -w /path/to/project \
  --model "claude-sonnet-4-20250514"
```

**Adapter-specific options:**
- `--opt edit-format=diff` — Edit format (whole/diff/udiff)
- `--opt auto-commits=true` — Enable Aider's auto-commits
- `--opt lint-cmd="ruff check"` — Lint after edits
- `--opt test-cmd="pytest"` — Test after edits

### codex (OpenAI Codex CLI)

```bash
bg-dispatch -a codex \
  -p "Add comprehensive test coverage for the auth module" \
  -n "auth-tests" \
  -w /path/to/project
```

**Adapter-specific options:**
- `--opt approval-mode=full-auto` — Approval mode (full-auto/suggest/ask)

## Notification System

bg-dispatch uses a pluggable notifier system. Configure in `bg-dispatch.json`:

```json
{
  "notifiers": [
    {
      "type": "openclaw",
      "config": { "session": "main" }
    },
    {
      "type": "webhook",
      "config": {
        "url_env": "SLACK_WEBHOOK_URL",
        "template": "slack"
      }
    },
    {
      "type": "webhook",
      "config": {
        "url_env": "FEISHU_WEBHOOK_URL",
        "template": "feishu",
        "secret_env": "FEISHU_WEBHOOK_SECRET"
      }
    },
    {
      "type": "command",
      "config": {
        "command": "echo Task $BGD_TASK_NAME completed with status $BGD_STATUS"
      }
    }
  ]
}
```

### Notifier Types

| Type | Description | Use Case |
|------|-------------|----------|
| `openclaw` | Wakes OpenClaw session via direct system event | Primary — agent receives completion event |
| `webhook` | HTTP POST to any webhook URL | Team notifications (Slack, Feishu, Discord) |
| `command` | Execute arbitrary shell command | Custom integrations, scripts, logging |

### Webhook Templates

- **`slack`** — Slack Block Kit message with status, duration, model info
- **`feishu`** — Feishu rich-text post with emoji status indicators
- **`discord`** — Discord embed with color-coded status
- **`generic`** — Simple JSON payload (works with any webhook receiver)

### Config File Search Order

1. `<workdir>/bg-dispatch.json` — per-project config
2. `<data-dir>/bg-dispatch.json` — instance config
3. `<install-dir>/bg-dispatch.json` — global config
4. `~/.bg-dispatch.json` — user config

If no config file found, defaults to `openclaw` notifier.

### Writing Custom Notifiers

Create a script in `notifiers/` implementing:

```bash
notifier_validate() {
  # Check prerequisites, return 1 on failure
}

notifier_send() {
  local META_FILE="$1"  # Path to task meta.json
  local CONFIG="$2"     # JSON string with notifier config
  # Send notification, return 0 on success
}
```

The `command` notifier exposes these env vars in the command context:
- `BGD_TASK_NAME`, `BGD_STATUS`, `BGD_EXIT_CODE`
- `BGD_WORKDIR`, `BGD_MODEL`, `BGD_ADAPTER`
- `BGD_STARTED_AT`, `BGD_COMPLETED_AT`
- `BGD_META_FILE`, `BGD_PROGRESS_FILE`

## How It Works

### Architecture

```
Your Agent (OpenClaw session)
  │
  ├─ Receives coding task
  ├─ Runs: bg-dispatch --adapter <name> --prompt <task> --workdir <dir>
  │   ├─ Creates progress.md + meta.json in data/tasks/<task-id>/
  │   ├─ Launches coding agent in background (setsid + PTY)
  │   ├─ Starts watchdog (stall detection + max runtime)
  │   └─ Returns immediately ← your agent is FREE
  │
  ... zero token consumption while agent works ...
  │
  ├─ On completion:
  │   ├─ Hook fires → notify.sh → all configured notifiers
  │   ├─ Watchdog provides fallback if hook fails
  │   └─ OpenClaw notifier wakes your agent session (instant, no cron delay)
  │
  ├─ Your agent reads data/tasks/<task-id>/progress.md
  └─ Sends summary to user, creates PR, etc.
```

### Three-Layer Notification Guarantee

1. **Hook** (primary) — Claude Code's Stop hook fires → `on-complete.sh` → `notify.sh`
2. **Process fallback** — Inline completion handler in the background process
3. **Watchdog** (safety net) — Detects process exit, waits 35s for hook, sends if missed

### Watchdog Behavior

- **Stall detection** — No file changes for 15 min (configurable) → kill + notify
- **Max runtime** — Hard 2-hour limit (configurable) → kill + notify
- **Progress.md check** — If `## Status: COMPLETE` appears → clean shutdown + notify
- **Exit detection** — When process exits, waits for hook, sends fallback if needed

### Resume Protocol

Progress is centralized in `data/tasks/<task-id>/` — outside the project workdir to avoid polluting repos:

```
data/tasks/<task-id>/
├── meta.json          # Full task definition (prompt, adapter, config, status)
├── progress.md        # What's done, in progress, remaining
├── output.txt         # Agent output log
└── watchdog.log       # Watchdog monitoring log
```

On resume, bg-dispatch searches `data/tasks/` for a task matching the workdir and rebuilds the prompt from `meta.json`. The agent reads `progress.md` + `git log` and continues from the last checkpoint. Legacy `.dev-progress/` in the workdir is auto-migrated if found.

## CLI Reference

```
Usage: bg-dispatch [OPTIONS]

Required:
  -a, --adapter NAME         Adapter name (claude-code, aider, codex)
  -p, --prompt TEXT          Task prompt (required unless --resume)

Options:
  -n, --name NAME            Task name (default: task-<timestamp>)
  -w, --workdir DIR          Working directory (default: cwd)
  --resume                   Resume from data/tasks/
  --force                    Kill existing task for same workdir
  --model MODEL              Model override
  --allowed-tools TOOLS      Allowed tools (adapter-specific)
  --agent-teams              Enable multi-agent mode
  --stall-timeout SECS       Stall timeout (default: 900)
  --max-runtime SECS         Max runtime (default: 7200)
  --callback-session KEY     OpenClaw session key
  --opt KEY=VALUE            Adapter-specific option (repeatable)
  -h, --help                 Show help
```

## Integration Guide for Agent Developers

### Step 1: Install

```bash
git clone https://github.com/PeterHiroshi/bg-dispatch.git
cd bg-dispatch && bash install.sh
export PATH="$(pwd):$PATH"
export BG_DISPATCH_DIR="$(pwd)"
```

### Step 2: Configure Notifications

Create `bg-dispatch.json` with your preferred notifiers. At minimum, use `openclaw` to wake your agent:

```json
{
  "notifiers": [
    { "type": "openclaw", "config": { "session": "main" } }
  ]
}
```

### Step 3: Dispatch from Your Agent

Your OpenClaw agent dispatches tasks like this:

```bash
bg-dispatch \
  -a claude-code \
  -p "$(cat <<'EOF'
Build a user authentication system with:
- JWT tokens with refresh
- Rate limiting per IP
- Password hashing with bcrypt
- Integration tests
EOF
)" \
  -n "auth-system" \
  -w /path/to/project
```

### Step 4: Handle Completion

When the task completes, your agent receives a system event. Read the progress from the centralized task directory (path is included in the system event message):

```bash
cat /path/to/bg-dispatch/data/tasks/<task-id>/progress.md
```

Then take action: create a PR, notify the user, dispatch the next task.

### Step 5: Heartbeat Integration

In your agent's heartbeat, check for completed/interrupted tasks:

```bash
node bg-dispatch/task-check.mjs \
  --data-dir bg-dispatch/data \
  --projects-dir /path/to/projects
```

The output JSON tells you what needs attention:
- `unnotified` — Completed tasks the user hasn't been told about
- `interrupted` — Tasks that need resuming
- `stalled` — Tasks that may be stuck

## Monitoring Commands (bgd CLI)

The `bgd` CLI provides interactive task monitoring. Use it to check on background tasks, view logs, and manage task lifecycle.

### List Tasks

```bash
bgd tasks                         # All tasks
bgd tasks --status running        # Only running tasks
bgd tasks --status done           # Only completed tasks
bgd tasks --limit 5               # Limit output
```

### Quick Status Overview

```bash
bgd status                        # Summary counts + active task details
```

### Show Task Details

```bash
bgd show auth-api                 # Full metadata + progress + git log
bgd show db                       # Partial name match OK
```

### View Logs

```bash
bgd logs auth-api                 # Last 50 lines of output (ANSI stripped)
bgd logs auth-api -n 100          # Last 100 lines
bgd logs auth-api -f              # Follow in real-time
bgd logs auth-api --watchdog      # Watchdog log instead
```

### View Progress

```bash
bgd progress auth-api             # Show progress.md from task data
```

### Cancel a Task

```bash
bgd cancel auth-api               # Kill process tree, update meta, notify
```

### Resume a Task

```bash
bgd resume auth-api               # Resume interrupted/killed task
```

### Clean Up

```bash
bgd clean                         # Remove done/killed tasks older than 24h
bgd clean --all                   # Remove all done/killed tasks
bgd clean --dry-run               # Preview what would be removed
```

## File Layout

```
bg-dispatch/
├── bg-dispatch              # Main dispatcher
├── watchdog.sh              # Stall detection + max runtime
├── notify.sh                # Notification dispatcher
├── task-check.mjs           # Heartbeat integration
├── install.sh               # Setup script
├── bg-dispatch.example.json # Example config
├── SKILL.md                 # This file (OpenClaw Skill)
├── adapters/
│   ├── claude-code.sh       # Claude Code adapter
│   ├── aider.sh             # Aider adapter
│   └── codex.sh             # Codex CLI adapter
├── notifiers/
│   ├── openclaw.sh          # OpenClaw system event notifier
│   ├── webhook.sh           # Generic webhook (Slack/Feishu/Discord)
│   └── command.sh           # Custom command notifier
├── hooks/
│   ├── on-complete.sh       # Claude Code Stop hook
│   └── settings.json        # Hook config
├── docs/
│   └── writing-adapters.md  # Adapter development guide
└── data/tasks/              # Runtime data (gitignored)
```
