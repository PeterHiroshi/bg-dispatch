# bg-dispatch

**Fire-and-forget background dispatch for heavy coding agents.**

Launch tools like [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Aider, or any long-running coding CLI in the background. Your [OpenClaw](https://github.com/openclaw/openclaw) session stays free — zero tokens consumed while the agent works. When it's done, a hook callback wakes OpenClaw automatically.

## The Problem

Heavy "vibe coding" tools (Claude Code, Cursor Agent, Aider) can run for minutes to hours. If your AI assistant waits for them to finish, it's blocked — burning tokens on polling or sitting idle. You can't talk to it, and it can't help you with anything else.

## The Solution

```
You (chat) → OpenClaw → bg-dispatch → Claude Code (background)
                ↑                              │
                └──── hook callback ────────────┘
                     (zero wait, zero poll)
```

1. **Dispatch** — `bg-dispatch` launches the coding agent in the background and returns immediately
2. **Work** — The coding agent runs independently, tracking progress in `.dev-progress/`
3. **Callback** — On completion, a hook fires and wakes OpenClaw via `openclaw cron add --system-event`
4. **Resume** — If interrupted (container reset, crash), the agent can resume from `.dev-progress/`

## Features

- 🚀 **Fire-and-forget** — Main session freed instantly, zero token burn while agent works
- 🔔 **Hook callback** — Agent completion wakes OpenClaw via cron system event
- 🔄 **Resumable** — `.dev-progress/` tracks progress; survives crashes and container resets
- 🐕 **Watchdog** — Auto-kills stalled tasks (no file changes) and enforces max runtime
- 🔒 **Workdir locking** — Prevents duplicate agents on the same project
- 🔌 **Adapter pattern** — Ships with Claude Code adapter; extensible to any CLI agent

## Quick Start

### 1. Install

```bash
git clone https://github.com/PeterHiroshi/bg-dispatch.git
cd bg-dispatch
bash install.sh
```

This installs the hook into `~/.claude/hooks/` and configures Claude Code to call back on completion.

### 2. Dispatch a Task

```bash
bg-dispatch \
  --adapter claude-code \
  --prompt "Build a REST API with user auth" \
  --name "user-auth-api" \
  --workdir /path/to/project
```

The script returns immediately. Claude Code runs in the background.

### 3. Get Notified

When the task completes, OpenClaw receives a system event:

```
🔨 Task done: user-auth-api. Duration: 12m34s. Workdir: /path/to/project.
Read .dev-progress/progress.md for details.
```

Your OpenClaw agent can then read the progress, create a PR, notify you — whatever you've configured.

### 4. Resume After Interruption

```bash
bg-dispatch --adapter claude-code --workdir /path/to/project --resume
```

The agent reads `.dev-progress/progress.md` and `git log`, then picks up where it left off.

## Architecture

```
bg-dispatch (orchestrator)
├── adapters/
│   ├── claude-code.sh      # Claude Code adapter (ships built-in)
│   └── (your-adapter.sh)   # Add your own
├── hooks/
│   ├── on-complete.sh      # Fires on task completion → wakes OpenClaw
│   └── settings.json       # Claude Code hook config
├── watchdog.sh              # Monitors for stalls + max runtime
├── task-check.mjs           # Heartbeat integration for OpenClaw agents
└── data/tasks/              # Runtime task metadata (gitignored)

Per-project:
<workdir>/.dev-progress/
├── task-spec.json           # Task definition (for resume)
└── progress.md              # Progress tracker (agent maintains this)
```

### Adapter Pattern

Each coding agent gets an adapter — a shell script that knows how to:
1. **Launch** the agent in background with the right flags
2. **Build** the command from bg-dispatch's generic options
3. **Detect** completion (exit code, output file)

```bash
# adapters/claude-code.sh — simplified
build_command() {
  CMD=("$CLAUDE_BIN" -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS")
  [[ -n "$MODEL" ]] && CMD+=(--model "$MODEL")
  echo "${CMD[@]}"
}
```

To add a new adapter (e.g., for Aider), create `adapters/aider.sh` implementing `build_command()` and `get_env()`. See [Writing Adapters](docs/writing-adapters.md) for the full interface.

### Hook Mechanism

bg-dispatch uses Claude Code's native hook system (`~/.claude/hooks/`). When Claude Code's session ends:

1. **Stop hook** fires → `hooks/on-complete.sh` reads task metadata
2. Hook verifies the process actually exited (retries up to 30s to handle race conditions)
3. Hook writes `result.json` with output summary
4. Hook calls `openclaw cron add --system-event "..."` to wake the main session
5. **Watchdog** provides backup notification if the hook fails

This is a push-based notification — no polling, no token waste.

### Watchdog

A background watchdog process monitors each dispatched task:

- **Stall detection** — If no files change in the workdir for 15 minutes (configurable), the task is killed
- **Max runtime** — Hard limit of 2 hours (configurable) to prevent runaway agents
- **Fallback notification** — If the hook doesn't fire, the watchdog sends the completion notification
- **Exit detection** — Watches for process exit and triggers notification after a grace period

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BG_DISPATCH_DIR` | Script location | Base directory for bg-dispatch |
| `BG_DISPATCH_DATA_DIR` | `$BG_DISPATCH_DIR/data` | Runtime task data |
| `BG_DISPATCH_STALL_TIMEOUT` | `900` (15 min) | Seconds of inactivity before killing |
| `BG_DISPATCH_MAX_RUNTIME` | `7200` (2 hours) | Maximum total runtime in seconds |

### Claude Code Adapter Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_BIN` | `/usr/local/bin/claude` | Path to Claude Code binary |
| `CLAUDE_CODE_USE_BEDROCK` | — | Set to `1` for AWS Bedrock auth |
| `AWS_PROFILE` | — | AWS profile for Bedrock |

## CLI Reference

```
Usage: bg-dispatch [OPTIONS]

Options:
  -a, --adapter NAME         Adapter to use (e.g., claude-code) [required]
  -p, --prompt TEXT          Task prompt [required unless --resume]
  -n, --name NAME            Task name for tracking [default: task-<timestamp>]
  -w, --workdir DIR          Working directory [default: cwd]
  --resume                   Resume interrupted task from .dev-progress/
  --force                    Kill existing task for same workdir
  --model MODEL              Model override (adapter-specific)
  --allowed-tools TOOLS      Allowed tools list (adapter-specific)
  --agent-teams              Enable multi-agent mode (adapter-specific)
  --stall-timeout SECS       Override stall detection timeout
  --max-runtime SECS         Override maximum runtime
  --callback-session KEY     OpenClaw session key to wake on completion
  -h, --help                 Show help
```

## OpenClaw Integration

bg-dispatch is designed as an [OpenClaw Skill](https://docs.openclaw.ai/skills). Your OpenClaw agent can:

1. **Dispatch** tasks when users request development work
2. **Resume** interrupted tasks during heartbeat checks
3. **Monitor** task status via `task-check.mjs`
4. **Notify** users when tasks complete (via any configured channel)

### Heartbeat Integration

```javascript
// In your OpenClaw agent's heartbeat:
// 1. Run task-check.mjs to find completed/interrupted tasks
// 2. Handle results (notify user, create PR, resume interrupted tasks)
```

### As an OpenClaw Skill

Copy or symlink into your OpenClaw workspace skills directory:

```bash
ln -s /path/to/bg-dispatch ~/.openclaw/workspace/skills/bg-dispatch
```

Then reference it in your agent's workflow. See [SKILL.md](SKILL.md) for the full skill definition.

## Writing Adapters

See [docs/writing-adapters.md](docs/writing-adapters.md) for the adapter interface specification. In summary, an adapter script must export two functions:

- `build_command()` — Returns the CLI command array to launch the agent
- `get_env()` — Returns any environment variables the agent needs

## Roadmap

- [x] Claude Code adapter
- [ ] Aider adapter
- [ ] Cursor Agent adapter (when CLI available)
- [ ] Codex CLI adapter
- [ ] Multi-task parallel dispatch
- [ ] Web dashboard for task monitoring
- [ ] OpenClaw Skill marketplace listing

## License

MIT — see [LICENSE](LICENSE).

## Credits

Born from [forge-dispatch](https://github.com/PeterHiroshi/forge-workspace), battle-tested in production with 100+ Claude Code dispatches. Extracted and generalized for the community.
