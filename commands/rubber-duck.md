---
description: Cross-model critique. Uses Copilot's built-in rubber-duck agent which deliberately picks a complementary model from your main session for blind-spot detection.
allowed-tools: Bash, Read
---

# /copilot:rubber-duck

Run Copilot's rubber-duck agent on a diff. The rubber-duck agent is designed to pick a *complementary* model — meaning if your main Claude Code session is on an Anthropic model, the rubber-duck will pick an OpenAI or Google model (when available on your plan) to surface cross-vendor blind spots.

## Arguments

`$ARGUMENTS` — same grammar as /copilot:review.

## Behavior

1. Parse `$ARGUMENTS`.
2. Capture diff via `capture-diff.sh`.
3. Model resolution: if user passed `--model`, resolve via `resolve-model.sh`. Otherwise omit `--model` and let the rubber-duck agent pick its complementary model.
4. Invoke:
   ```bash
   if [ -n "$RESOLVED_MODEL" ]; then
     copilot -p --silent --agent=rubber-duck --model "$RESOLVED_MODEL" < diff
   else
     copilot -p --silent --agent=rubber-duck < diff
   fi
   ```
5. Stream output.

## When to use

After running `/copilot:review` or `/copilot:adversarial-review`, run `/copilot:rubber-duck` to get a second opinion from a different model family. If both reviewers flag the same issue, it's almost certainly real. If only one does, it's worth investigating which is right.

## Plan notes

On the author's Pro plan with limited model coverage, rubber-duck still works but the "complementary model" pool is small. Pro+ users get the full benefit because the model pool spans Anthropic, OpenAI, and (when enabled) Google.
