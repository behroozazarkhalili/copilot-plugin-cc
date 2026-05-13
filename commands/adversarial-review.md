---
description: Harsh adversarial code review. Assumes the diff is wrong until proven right. Uses a shipped custom agent profile.
allowed-tools: Bash, Read
---

# /copilot:adversarial-review

Same input grammar as `/copilot:review`, but uses the adversarial agent profile.

## Behavior

1. Parse `$ARGUMENTS` exactly like `/copilot:review`.
2. **Install the custom agent on first run.** Check whether `~/.copilot/agents/adversarial-review.agent.md` exists. If not, copy it from `${CLAUDE_PLUGIN_ROOT}/agents/adversarial-review.agent.md`:
   ```bash
   mkdir -p ~/.copilot/agents
   if [ ! -f ~/.copilot/agents/adversarial-review.agent.md ]; then
     cp "${CLAUDE_PLUGIN_ROOT}/agents/adversarial-review.agent.md" ~/.copilot/agents/
     echo "Installed adversarial-review.agent.md to ~/.copilot/agents/"
   fi
   ```
   Never overwrite an existing file — the user may have edited it.
3. Capture diff via `capture-diff.sh` (same as /copilot:review).
4. Resolve model (same default: codex).
5. Invoke `copilot --agent=adversarial-review --model "$RESOLVED" -p --silent < diff`.
6. Stream output back.

## Why this exists

The built-in `code-review` agent is calibrated to be helpful. Sometimes you want a reviewer that defaults to suspicious. That's this command.

## Tuning

After first run, you can edit `~/.copilot/agents/adversarial-review.agent.md` to adjust:
- Severity gradient (make REJECT cheaper or harder)
- Focus axis (security-only, perf-only, etc.)
- Length budget for the response

The plugin will not overwrite your edits on subsequent runs.
