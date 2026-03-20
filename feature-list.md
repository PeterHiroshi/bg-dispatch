# Feature List — bg-dispatch CLI Monitoring (bgd)

## Status Legend
- 🔴 Not started
- 🟡 In progress
- 🟢 Complete
- ⚫ Blocked

## Features

### Phase 1 — Core CLI Commands

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 1 | `bgd` entry point script with subcommand routing | 🔴 | — | Parse subcommand, route to handler, --help |
| 2 | `bgd tasks` — list all tasks with status table | 🔴 | — | Read data/tasks/*/meta.json, table format: name, status, adapter, duration, model |
| 3 | `bgd status` — quick overview (running/done/failed counts + active task detail) | 🔴 | — | Summary line + current running task progress |
| 4 | `bgd show <task>` — detailed view of a specific task | 🔴 | — | Full meta.json + progress.md content + recent git log |
| 5 | `bgd logs <task>` — show output/watchdog logs for a task | 🔴 | — | Tail output.txt and watchdog.log |
| 6 | `bgd clean` — clean up completed/failed task data | 🔴 | — | Remove old task dirs, kill orphan processes, respect running tasks |

### Phase 2 — Enhanced Monitoring

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 7 | `bgd progress <task>` — show .dev-progress/progress.md from workdir | 🔴 | — | Read live progress from the actual workdir |
| 8 | `bgd cancel <task>` — cancel a running task | 🔴 | — | Kill process tree, update meta, notify |
| 9 | `bgd resume <task>` — resume an interrupted task | 🔴 | — | Wrapper around bg-dispatch --resume --force |

### Phase 3 — SKILL.md Integration

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 10 | Update SKILL.md with bgd commands documentation | 🔴 | — | Add monitoring section to SKILL.md |
| 11 | Update README.md with bgd CLI docs | 🔴 | — | CLI reference, examples |
| 12 | Update install.sh to set up bgd in PATH | 🔴 | — | Symlink or PATH setup |
