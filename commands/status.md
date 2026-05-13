---
description: List Copilot cloud-agent jobs the user has dispatched. Local cached view + link to GitHub web UI for live status.
allowed-tools: Bash, Read
---

# /copilot:status

List jobs from local state and direct the user to GitHub for live status.

## Arguments

`$ARGUMENTS` — optional flags: `--all` (include cancelled/failed), `--json` (machine-readable).

## Behavior

1. Read local state via:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" list $ARGUMENTS
   ```
2. Print the result.
3. Append a footer:
   ```
   For live status, visit: https://github.com/copilot/agents
   ```
4. If `--json` was passed, do NOT add the footer (machine-consumable).

## Why local-only (for now)

Copilot CLI 1.0.47 has no `job status` verb. Live status comes from the GitHub web UI. If GitHub ships a CLI verb in a future release, this command will be updated to refresh statuses inline. Until then, the local TSV reflects jobs as they were dispatched via /copilot:rescue.

## Error handling

- TSV is empty (no jobs ever dispatched): "No jobs tracked yet. Run /copilot:rescue to delegate a task."
