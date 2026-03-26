# Changelog

## [0.4.0] — 2026-03-26

### Added
- **Cascading session routing** — `--source-session` flag for targeted notification delivery to originating sessions (#8)
  - Three-level cascade: targeted wake → broadcast system event → heartbeat pending marker
  - Guarantees notification delivery even when target session is temporarily unavailable
- **Idempotent notification tracking** — `notified.*` per-channel fields in meta.json (#8)
  - Prevents duplicate notifications from hook/setsid/watchdog race conditions
  - Per-webhook-template dedup (`notified.webhook_slack`, `notified.webhook_feishu`, etc.)
- **`pending_session_notify`** — Heartbeat recovery for failed real-time notifications (#8)
  - `task-check.mjs` surfaces pending notifications for agent retry
- **Progress monitoring** — Real-time task progress between dispatch and completion (#7)
  - `--progress-interval` flag for periodic `git diff --stat` polling
  - `progress` notification event type (opt-in per notifier via `events` array)
  - File activity signals: watchdog logs changes + updates `last_activity` in meta.json
- **`bgd logs -f`** — Follow output in real-time while task runs (#7)
- **`bgd logs --lines N`** — Control output line count (#7)
- **Real-time output capture** — `script -f` flush for live streaming (#7)

### Changed
- `openclaw` notifier rewritten with cascade + idempotency (was single-shot system event)
- `notify.sh` now checks `notified.*` fields before each notifier dispatch
- `task-check.mjs` reports `source_session`, per-field `notified` status, and `pending_session_notify`

## [0.3.0] — 2026-03-22

### Added
- Centralized progress tracking in `data/tasks/` (outside project workdir)
- Direct system event wake (replaces cron-based wake)
- Legacy `.dev-progress/` auto-migration
- `bgd` CLI monitoring tool (tasks, status, show, logs, progress, cancel, resume, clean)

## [0.2.0] — 2026-03-20

### Added
- Pluggable notification system (openclaw, webhook, command notifiers)
- Adapter pattern (claude-code, aider, codex)
- Watchdog with stall detection + max runtime
- Resume support from centralized task data
- Workdir locking (prevent duplicate agents)

## [0.1.0] — 2026-03-18

### Added
- Initial release: fire-and-forget dispatch with Claude Code adapter
