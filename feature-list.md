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
| 7 | `bgd progress <task>` — show progress.md from task data directory | 🟢 | feature/bgd-cli | Read live progress from centralized data/tasks/ |
| 8 | `bgd cancel <task>` — cancel a running task | 🟢 | feature/bgd-cli | Kill process tree, update meta, notify |
| 9 | `bgd resume <task>` — resume an interrupted task | 🟢 | feature/bgd-cli | Wrapper around bg-dispatch --resume --force |

### Phase 3 — Architecture Improvements

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 13 | Centralize progress tracking — move from .dev-progress/ in workdir to data/tasks/<task-id>/ | 🟢 | feature/centralize-progress | Avoids polluting project repos (especially open-source). Progress.md + meta.json all in data/tasks/ |
| 14 | Replace cron-based wake with direct system event — `openclaw system event --mode now` | 🟢 | feature/centralize-progress | Instant wake, no unnecessary cron job creation, removes 5s delay |
| 15 | Update bgd CLI to read progress from data/tasks/ instead of .dev-progress/ | 🟢 | feature/centralize-progress | bgd progress, bgd show must use new centralized paths |
| 16 | Update SKILL.md, README.md, CLAUDE.md to reflect new architecture | 🟢 | feature/centralize-progress | All docs must describe centralized progress + direct system event |
| 17 | Update task-check.mjs for centralized progress paths | 🟢 | feature/centralize-progress | Heartbeat integration uses data/tasks/ |
| 18 | Backward compatibility — detect and migrate legacy .dev-progress/ | 🟢 | feature/centralize-progress | Resume mode should check both locations |

### Phase 4 — SKILL.md Integration (completed)

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 10 | Update SKILL.md with bgd commands documentation | 🟢 | feature/bgd-cli | Add monitoring section to SKILL.md |
| 11 | Update README.md with bgd CLI docs | 🟢 | feature/bgd-cli | CLI reference, examples |
| 12 | Update install.sh to set up bgd in PATH | 🟢 | feature/bgd-cli | Symlink or PATH setup |

### Phase 5 — Hook System Overhaul (Issue #6)

| # | Feature | Status | Branch | Notes |
|---|---------|--------|--------|-------|
| 19 | Periodic progress polling in watchdog — `--progress-interval <seconds>` flag | 🔴 | feature/hook-system-overhaul | Watchdog runs `git diff --stat` every N seconds, appends to progress.md |
| 20 | New notifier event type: `progress` — lightweight mid-task notifications | 🔴 | feature/hook-system-overhaul | notify.sh handles `progress` event distinct from `complete` |
| 21 | Fix `output.txt` real-time capture — replace `script -q` redirect with tee/pipe | 🔴 | feature/hook-system-overhaul | `bgd logs -f` must work during execution |
| 22 | Expose watchdog file-change events as progress signals | 🔴 | feature/hook-system-overhaul | Watchdog already detects changes for stall; emit as progress events |
| 23 | `bgd logs -f <task>` — follow mode for live output tailing | 🔴 | feature/hook-system-overhaul | tail -f on output.txt when task is running |
| 24 | Update SKILL.md + README.md with progress hook documentation | 🔴 | feature/hook-system-overhaul | Document --progress-interval, new event types, bgd logs -f |
