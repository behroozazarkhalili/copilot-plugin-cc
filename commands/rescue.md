---
description: Delegate a task to GitHub Copilot's cloud agent. On plans with cloud-agent entitlement (Pro+, Business, Enterprise), this creates a branch, opens a draft PR, and runs in the background. On plans without (e.g. Pro), Copilot CLI runs the task locally instead.
allowed-tools: Bash, Read
---

# /copilot:rescue

Push a task to Copilot's cloud agent via the `&` prefix.

## Arguments

`$ARGUMENTS` — required free-form prompt describing the task. Examples:
- `/copilot:rescue add unit tests for src/parser.ts`
- `/copilot:rescue refactor the auth flow to use JWT`
- `/copilot:rescue fix the failing CI on main`

## Behavior

1. Parse `$ARGUMENTS` as the prompt. If empty, error: "Usage: /copilot:rescue <prompt>"
2. Invoke Copilot with the `&` delegation prefix:
   ```bash
   copilot -p "&${PROMPT}" --silent 2>&1
   ```
3. Capture the response and parse:
   - A session ID (look for `session_[a-z0-9]+` pattern in output)
   - A draft PR URL (look for `https://github.com/[^ ]+/pull/[0-9]+` pattern)
4. If a PR URL was found → cloud-agent delegation succeeded:
   - Append to local state:
     ```bash
     "${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" append \
       "$JOB_ID" "${PROMPT:0:80}" "$PR_URL" "running"
     ```
   - Print to user: "Cloud agent dispatched. Job: $JOB_ID  PR: $PR_URL"
5. If no PR URL but a response came back → degraded to local mode (Pro plan):
   - Print Copilot's response (it ran the task locally instead of dispatching).
   - Add a footer: "Note: this ran locally because your plan does not include cloud-agent delegation. Upgrade to Pro+ at https://github.com/settings/copilot to dispatch to cloud."

## Error handling

- `copilot` not on PATH → "Run /copilot:setup first."
- Auth error → "Run `copilot login`."
- Empty prompt → usage error.
