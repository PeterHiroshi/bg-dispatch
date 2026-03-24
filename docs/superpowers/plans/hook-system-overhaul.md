# Implementation Plan: Hook System Overhaul (Issue #6)

## Overview
Add intermediate progress reporting to bg-dispatch: periodic polling, real-time output capture, watchdog file-change events, and bgd logs -f follow mode.

## Task Order
Features are ordered by dependency: output capture first (no deps), then notifier events (needed by watchdog), then watchdog features, then CLI, then docs.

---

## Task 1: Fix output.txt Real-Time Capture (Feature 21)
**Time: 3-5 min | Files: bg-dispatch**

### Changes
- [x] In the setsid background block of `bg-dispatch`, replace:
  ```bash
  script -q -c "bash $LAUNCHER" /dev/null > "$OUTPUT_FILE" 2>&1
  ```
  with:
  ```bash
  script -q -f "$OUTPUT_FILE" -c "bash $LAUNCHER" /dev/null 2>&1
  ```
  The `-f` flag flushes output after each write, enabling real-time `tail -f`.
  Redirect /dev/null for the typescript file (or use $OUTPUT_FILE as the typescript target).

### Verification
- Create a test task dir with a simple script, verify `tail -f output.txt` shows output in real-time
- Verify existing completion behavior still works (exit code captured, meta.json updated)

---

## Task 2: New Notifier Event Type: progress (Feature 20)
**Time: 5-8 min | Files: notify.sh, notifiers/openclaw.sh, notifiers/webhook.sh, notifiers/command.sh, bg-dispatch.example.json**

### Changes
- [x] `notify.sh`: Accept optional 3rd argument `event_type` (default: "complete")
  - Pass event_type to notifier_send as 3rd argument
  - Check per-notifier `events` config array; skip if event not in list (default: ["complete"])
- [x] `notifiers/openclaw.sh`: Handle event_type parameter
  - "progress": lighter message (no wake, just log to stderr)
  - "complete": same as current behavior
- [x] `notifiers/webhook.sh`: Handle event_type parameter
  - "progress": compact payload with `event: "progress"` and git diff summary
  - "complete": same as current
- [x] `notifiers/command.sh`: Handle event_type parameter
  - Set `BGD_EVENT` env var (progress/complete)
- [x] `bg-dispatch.example.json`: Add `events` field example

### Verification
- Run `bash notify.sh <test-meta.json>` (backward compat — should default to "complete")
- Run `bash notify.sh <test-meta.json> <config> progress` — should respect events filter

---

## Task 3: Periodic Progress Polling in Watchdog (Feature 19)
**Time: 5-8 min | Files: bg-dispatch, watchdog.sh**

### Changes
- [x] `bg-dispatch`: Add `--progress-interval SECS` flag (default: disabled/0)
  - Store in PROGRESS_INTERVAL variable
  - Pass as 6th argument to watchdog.sh
  - Store in meta.json as `progress_interval`
- [x] `watchdog.sh`: Accept 6th argument for progress_interval
  - Track LAST_PROGRESS_CHECK timestamp
  - In main loop, every progress_interval seconds:
    - Run `git diff --stat HEAD` in WORKDIR
    - Run `git status --porcelain | wc -l` for modified/untracked count
    - Append timestamped entry to TASK_DIR/progress.md
    - Call notify.sh with "progress" event type

### Verification
- Run watchdog.sh with a test task dir and a git repo workdir, verify progress.md gets entries
- Verify it works when progress_interval is 0 (disabled — no progress checks)

---

## Task 4: Expose Watchdog File-Change Events as Progress (Feature 22)
**Time: 3-5 min | Files: watchdog.sh**

### Changes
- [x] When file activity IS detected (the existing RECENT check that resets stall timer):
  - Count changed files: `find "$WORKDIR" -not -path "*/.git/*" -newer "$TASK_DIR/pid" -type f 2>/dev/null | wc -l`
  - Log to watchdog.log: `[timestamp] File activity detected: N files changed`
  - Update meta.json with `last_activity` ISO timestamp field
- [x] This is always-on (not gated by progress_interval)

### Verification
- Touch files in a test workdir, verify watchdog.log shows file activity entries
- Verify meta.json gets last_activity field updated

---

## Task 5: bgd logs -f Follow Mode Enhancements (Feature 23)
**Time: 3-5 min | Files: bgd**

### Changes
- [x] In cmd_logs, enhance the -f/--follow behavior:
  - Check task status from meta.json
  - If running: `tail -f` (existing behavior already works)
  - If not running: print last N lines with message "Task not running, showing last N lines"
  - Add `--lines N` / `-n N` flag alias (already exists as -n)
- [x] Update help text to document --follow and --lines

### Verification
- Run `bgd logs <task> -f` on a non-running task — should show last lines + info message
- Run `bgd logs <task> --lines 20` — should show 20 lines

---

## Task 6: Documentation Updates (Feature 24)
**Time: 5-8 min | Files: SKILL.md, README.md**

### Changes
- [x] SKILL.md: Add --progress-interval to CLI reference, document events config, document bgd logs -f
- [x] README.md: Add progress monitoring section, update CLI reference with new flags

### Verification
- Review docs for accuracy against implemented features
- Ensure backward-compatible examples still work

---

## Task 7: Update feature-list.md + Final Commit
**Time: 2 min | Files: feature-list.md**

### Changes
- [x] Mark features 19-24 as complete in feature-list.md
- [x] Final push to remote

### Verification
- `git log --oneline` shows one commit per feature
- All features marked complete in feature-list.md
