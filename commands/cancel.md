---
description: Cancel an active Copilot cloud-agent job. Updates the local TSV; canceling on GitHub requires the web UI.
allowed-tools: Bash, Read
---

# /copilot:cancel

Mark a job as cancelled in local state and direct the user to the web UI for the actual server-side cancellation.

## Arguments

`$ARGUMENTS` — required job ID or unique prefix.

## Behavior

1. Resolve prefix to a full ID via the same logic as /copilot:result.
2. Read the current status from TSV:
   ```bash
   current=$("${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" list --all --json | jq -r --arg id "$JOB_ID" '.[] | select(.job_id == $id) | .status')
   ```
3. If status is already terminal (cancelled, failed, completed): "Job $JOB_ID is already $current — nothing to cancel."
4. Otherwise:
   - Update TSV:
     ```bash
     "${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" update "$JOB_ID" cancelled
     ```
   - Print:
     ```
     Marked $JOB_ID as cancelled locally.
     
     ⚠️ Copilot CLI 1.0.47 has no programmatic cancel verb. To stop
     the cloud-side work, visit:
       https://github.com/copilot/agents
     Find session $JOB_ID and click Cancel.
     ```

## Why the local-only update

When GitHub ships a CLI cancel verb, this command will issue the real cancel before updating the TSV. Until then, the local state is optimistic — it reflects user intent, not server state.
