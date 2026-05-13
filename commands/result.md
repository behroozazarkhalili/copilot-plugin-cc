---
description: Fetch or reattach to a Copilot cloud-agent job session.
allowed-tools: Bash, Read
---

# /copilot:result

Reattach to a job session locally, or point to the web UI for full output.

## Arguments

`$ARGUMENTS` — required job ID or unique prefix.

## Behavior

1. Parse the ID/prefix from $ARGUMENTS.
2. Resolve prefix → full ID by reading job-state.sh:
   ```bash
   matches=$("${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" list --all --json | jq -r --arg p "$PREFIX" '.[] | select(.job_id | startswith($p)) | .job_id')
   ```
   - 0 matches → "No job matches '$PREFIX'. Run /copilot:status."
   - >1 matches → "Ambiguous prefix. Matches: ... Disambiguate."
   - 1 match → continue.
3. Look up the PR URL from the TSV row.
4. Attempt to reattach locally:
   ```bash
   copilot --resume="$JOB_ID" --silent
   ```
   If it succeeds, it'll print the session state.
5. Whether or not the local reattach worked, print:
   ```
   Job:    $JOB_ID
   PR:     $PR_URL
   Web:    https://github.com/copilot/agents  (full transcript + status)
   ```

## Why both local + web

Local `--resume` shows the conversation context but may not reflect the latest cloud-agent activity. The web UI is authoritative.
