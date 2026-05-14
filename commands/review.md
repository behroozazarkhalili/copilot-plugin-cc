---
description: Review uncommitted changes (or a specified target) with GitHub Copilot CLI's built-in code-review agent. Use --model to override the reviewer LLM.
allowed-tools: Bash, Read
---

# /copilot:review

Run a Copilot code review on a diff target.

## Arguments

`$ARGUMENTS` — optional target plus optional `--model <alias-or-id>`. Examples:
- `` (empty) — review staged + unstaged working dir
- `HEAD~5..HEAD`
- `pr 123`
- `--staged`
- `--branch`
- `--model sonnet`
- `--branch --model codex`

## Behavior

1. Parse `$ARGUMENTS`. Separate target args (everything that isn't `--model X`) from the model alias.
2. Determine the plugin install directory. The scripts live at `${CLAUDE_PLUGIN_ROOT}/scripts/`.
3. Capture the diff:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/capture-diff.sh" <target-args> > /tmp/copilot-review-$$.diff
   ```
   If the script exits with 66 (no changes), tell the user "No changes to review. Stage some changes or pass a target." and stop.
4. Resolve the model. If `--model X` was passed, run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh" X
   ```
   If the script exits 65 (chain exhausted), surface its stderr to the user and stop.
   If no `--model` was passed, default to `codex` (which resolves to `gpt-5.3-codex` on plans with access, falling back to `gpt-5.2-codex` until that model's 2026-06-01 sunset).
5. Build the copilot invocation:
   ```bash
   if [ -n "$RESOLVED_MODEL" ]; then
     copilot -p --silent --agent=code-review --model "$RESOLVED_MODEL" < /tmp/copilot-review-$$.diff
   else
     copilot -p --silent --agent=code-review < /tmp/copilot-review-$$.diff
   fi
   ```
6. Stream the markdown response back into the transcript. Render it as-is — do not summarize.
7. Clean up `/tmp/copilot-review-$$.diff`.

## Error handling

- If `copilot` is not on PATH: tell the user to run `/copilot:setup` first.
- If `copilot` returns an auth error: tell the user to run `copilot login`.
- If `resolve-model.sh` exits 65: print its stderr verbatim and stop.
- If `capture-diff.sh` exits 67 (not a git repo): tell the user to `cd` into a git repo first.
- If the diff is enormous (>500KB): warn the user before sending and offer to narrow the target.
