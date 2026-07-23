---
description: Cross-model scientific / technical-document review via GitHub Copilot CLI. Checks methodology, math and statistical rigor, citations, and notation. Ships a custom agent profile. Use --model to override the reviewer LLM.
allowed-tools: Bash, Read
---

# /copilot:review-scientific

Run a Copilot scientific / technical-document review on a target file or diff. This is the cross-model counterpart to Claude's own `/review-scientific`: it sends the document to a different model family so blind spots the authoring model shares cannot hide.

## Arguments

`$ARGUMENTS` — optional target plus optional `--model <alias-or-id>`. Examples:
- `` (empty) — review staged + unstaged working dir
- `paper.md`
- `sections/methods.tex`
- `HEAD~3..HEAD`
- `--staged`
- `--model terra`
- `paper.md --model gpt`

## Behavior

1. Parse `$ARGUMENTS`. Separate target args (everything that isn't `--model X`) from the model alias.
2. **Install the custom agent on first run.** Check whether `~/.copilot/agents/scientific-review.agent.md` exists. If not, copy it from `${CLAUDE_PLUGIN_ROOT}/agents/scientific-review.agent.md`:
   ```bash
   mkdir -p ~/.copilot/agents
   if [ ! -f ~/.copilot/agents/scientific-review.agent.md ]; then
     cp "${CLAUDE_PLUGIN_ROOT}/agents/scientific-review.agent.md" ~/.copilot/agents/
     echo "Installed scientific-review.agent.md to ~/.copilot/agents/"
   fi
   ```
   Never overwrite an existing file — the user may have edited it.
3. Capture the content to review:
   - If the target names one or more files that exist, send those files.
   - Otherwise capture a diff via `capture-diff.sh` (same targets as `/copilot:review`). If it exits 66 (no changes), tell the user "No document changes to review. Pass a file path or stage some changes." and stop.
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/capture-diff.sh" <target-args> > /tmp/copilot-scireview-$$.diff
   ```
4. Resolve the model. If `--model X` was passed, run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh" X
   ```
   If the script exits 65 (chain exhausted), surface its stderr to the user and stop.
   If no `--model` was passed, default to `terra` (which resolves to `gpt-5.6-terra`, the scientific-review model).
5. Build the copilot invocation:
   ```bash
   if [ -n "$RESOLVED_MODEL" ]; then
     copilot -p --silent --agent=scientific-review --model "$RESOLVED_MODEL" < /tmp/copilot-scireview-$$.diff
   else
     copilot -p --silent --agent=scientific-review < /tmp/copilot-scireview-$$.diff
   fi
   ```
6. Stream the markdown response back into the transcript. Render it as-is — do not summarize.
7. Clean up `/tmp/copilot-scireview-$$.diff`.

## Why this exists

`/review-scientific` runs in the current Claude session. This command runs the same class of review on a different model family (default `gpt-5.6-terra`), so methodology, math, and citation errors that a single model's priors would wave through get a second, independent pass.

## Error handling

- If `copilot` is not on PATH: tell the user to run `/copilot:setup` first.
- If `copilot` returns an auth error: tell the user to run `copilot login`.
- If `resolve-model.sh` exits 65: print its stderr verbatim and stop.
- If `capture-diff.sh` exits 67 (not a git repo) and no file target was given: tell the user to pass a file path or `cd` into a git repo.
- If the input is enormous (>500KB): warn the user before sending and offer to narrow the target.

## Tuning

After first run, you can edit `~/.copilot/agents/scientific-review.agent.md` to adjust the review axes (statistics-only, citations-only, notation-only) or the length budget. The plugin will not overwrite your edits on subsequent runs.
