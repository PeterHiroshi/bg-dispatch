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
| 1 | `bgd` entry point script with subcommand routing | 🟢 | feature/bgd-cli | Parse subcommand, route to handler, --help |
| 2 | `bgd tasks` — list all tasks with status table | 🟢 | feature/bgd-cli | Read data/tasks/*/meta.json, table format: name, status, adapter, duration, model |
| 3 | `bgd status` — quick overview (running/done/failed counts + active task detail) | 🟢 | feature/bgd-cli | Summary line + current running task progress |
| 4 | `bgd show <task>` — detailed view of a specific task | 🟢 | feature/bgd-cli | Full meta.json + progress.md content + recent git log |
| 5 | `bgd logs <task>` — show output/watchdog logs for a task | 🟢 | feature/bgd-cli | Tail output.txt and watchdog.log |
| 6 | `bgd clean` — clean up completed/failed task data | 🟢 | feature/bgd-cli | Remove old task dirs, kill orphan processes, respect running tasks |

### Phase 2 — Enhanced Monitoring

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 7 | `bgd progress <task>` — show .dev-progress/progress.md from workdir | 🟢 | feature/bgd-cli | Read live progress from the actual workdir |
| 8 | `bgd cancel <task>` — cancel a running task | 🟢 | feature/bgd-cli | Kill process tree, update meta, notify |
| 9 | `bgd resume <task>` — resume an interrupted task | 🟢 | feature/bgd-cli | Wrapper around bg-dispatch --resume --force |

### Phase 3 — SKILL.md Integration

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 10 | Update SKILL.md with bgd commands documentation | 🟢 | feature/bgd-cli | Add monitoring section to SKILL.md |
| 11 | Update README.md with bgd CLI docs | 🟢 | feature/bgd-cli | CLI reference, examples |
| 12 | Update install.sh to set up bgd in PATH | 🟢 | feature/bgd-cli | Symlink or PATH setup |
