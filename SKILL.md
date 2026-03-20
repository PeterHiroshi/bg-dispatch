---
name: bg-dispatch
description: Fire-and-forget background dispatch for heavy coding agents (Claude Code, etc.) with hook-based callback. Agent runs in background, main session stays free. Resumable across container resets.
---

# bg-dispatch — OpenClaw Skill

Dispatch heavy coding agents (Claude Code, Aider, etc.) as fire-and-forget background tasks. The main OpenClaw session is freed immediately — zero tokens consumed while the agent works. On completion, a hook callback wakes OpenClaw automatically.

## Quick Usage

```bash
bg-dispatch \
  --adapter claude-code \
  --prompt "Build the REST API" \
  --name "rest-api" \
  --workdir /path/to/project
```

## When to Use

- Any substantial development task (build, fix, refactor, test)
- Tasks expected to take more than a few minutes
- When you want the main session free for other conversations

## When NOT to Use

- Pure documentation edits (handle directly)
- Simple config changes
- Quick shell one-liners

## Files

- `bg-dispatch` — Main dispatcher script
- `watchdog.sh` — Stall detection + max runtime enforcement
- `adapters/claude-code.sh` — Claude Code adapter
- `hooks/on-complete.sh` — Completion hook (wakes OpenClaw)
- `task-check.mjs` — Heartbeat integration (check task status)
- `install.sh` — Setup script

## Task Lifecycle

1. **Dispatch** → `bg-dispatch` launches agent, returns immediately
2. **Running** → Agent works in background, progress in `.dev-progress/`
3. **Complete** → Hook fires → `openclaw cron add --system-event` wakes main session
4. **Notify** → Main session reads progress.md, notifies user
5. **Resume** (if interrupted) → `bg-dispatch --resume` picks up from `.dev-progress/`

## Heartbeat Integration

Run `task-check.mjs` during heartbeats to detect:
- Unnotified completed tasks
- Interrupted tasks (needs resume)
- Stalled tasks
