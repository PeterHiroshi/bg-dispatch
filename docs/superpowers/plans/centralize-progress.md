# Plan: Centralize Progress Tracking + Direct System Event

## Change 1: Centralize Progress Tracking
Move from `.dev-progress/` in workdir to `data/tasks/<task-id>/` (progress.md + meta.json).

### Files to modify:
1. **bg-dispatch** — PROGRESS_DIR → TASK_DIR, write progress.md/meta.json there, update prompt instructions, resume from data/tasks/, backward compat migration, rename task-spec.json → meta.json in progress context
2. **watchdog.sh** — Read progress from TASK_DIR instead of workdir/.dev-progress/
3. **hooks/on-complete.sh** — Update fallback wake text (remove .dev-progress reference)
4. **notifiers/openclaw.sh** — Update wake text (remove .dev-progress reference)
5. **bgd** — All commands read progress from data/tasks/<task-id>/ not .dev-progress/
6. **task-check.mjs** — Scan data/tasks/*/meta.json for interrupted tasks instead of projectsDir/.dev-progress/
7. **notify.sh** — No changes needed (already reads from META_FILE)

## Change 2: Direct System Event
Replace `openclaw cron add` with `openclaw system event --mode now --text`.

### Files to modify:
1. **notifiers/openclaw.sh** — Replace cron add with system event
2. **bg-dispatch** — Inline fallback notification
3. **watchdog.sh** — Fallback notification
4. **hooks/on-complete.sh** — Fallback notification

## Change 3: Documentation
Update SKILL.md, README.md, CLAUDE.md to reflect new architecture.

## Change 4: Feature List
Update feature-list.md status indicators.
