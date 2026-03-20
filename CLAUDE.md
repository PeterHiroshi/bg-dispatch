# CLAUDE.md — bg-dispatch

## Tech Stack
- Language: Bash (main scripts), Node.js (task-check.mjs)
- Runtime: Linux (bash 5+, coreutils, jq, util-linux `script`)
- No build step — scripts run directly

## Project Structure
```
bg-dispatch/
├── bg-dispatch              # Main dispatcher script (bash)
├── bgd                      # CLI monitoring tool (bash)
├── watchdog.sh              # Stall detection + max runtime
├── notify.sh                # Notification dispatcher
├── task-check.mjs           # Heartbeat integration (Node.js)
├── install.sh               # Setup script
├── bg-dispatch.json         # Config (notifiers, settings)
├── adapters/                # Agent adapters (one .sh per agent)
├── notifiers/               # Notification plugins (one .sh per type)
├── hooks/                   # Agent completion hooks
├── docs/                    # Documentation
├── SKILL.md                 # OpenClaw Skill definition
└── data/tasks/              # Runtime task data (gitignored)
```

## Coding Standards
- Bash: use `set -euo pipefail` in all scripts
- Bash: use `local` for function variables
- Bash: quote all variable expansions (`"$VAR"` not `$VAR`)
- Bash: use `[[ ]]` not `[ ]` for tests
- Bash: functions use snake_case
- Node.js: ES modules (import/export), no dependencies beyond node built-ins
- jq: required dependency, used for JSON manipulation
- All scripts must be executable (`chmod +x`)
- No external dependencies beyond: bash, jq, coreutils, util-linux, node

## Testing
- Test by running commands against mock data in data/tasks/
- Create test task directories with meta.json files for validation
- Verify output format matches expected (table formatting, status indicators)
- Test edge cases: no tasks, only running tasks, only completed tasks, mixed states

## Git
- Commit format: `type(scope): description`
- One commit per feature/task
- Types: feat, fix, docs, refactor, test, chore
- Feature branches from develop

## Forbidden Patterns
- No npm/pip dependencies — this is a zero-dependency project (except node built-ins for .mjs files)
- No hardcoded paths — use BG_DISPATCH_DIR and BG_DISPATCH_DATA_DIR
- No magic numbers — use named variables with comments
- No `eval` — use arrays and printf %q for command building
