# Manual smoke tests for command .md files

These tests cover the slash commands, which are Claude Code prompts and can't be unit-tested via bats. Run them in a Claude Code session after installing the plugin locally.

## /copilot:review

1. `cd ~/Downloads/copilot-plugin-cc` (or any git repo with uncommitted changes)
2. Make a trivial edit so there's a diff
3. In Claude Code: `/copilot:review`
4. Expected: a markdown code review streams back
5. Then: `/copilot:review --model codex` — should explicitly resolve to gpt-5.2-codex
6. Then in a repo with NO diff: `/copilot:review` — should say "No changes to review"

## /copilot:adversarial-review

1. First-run check: `rm -f ~/.copilot/agents/adversarial-review.agent.md`
2. `/copilot:adversarial-review` in a repo with diff
3. Expected output: "Installed adversarial-review.agent.md to ~/.copilot/agents/" followed by a harsh review
4. Verify the file exists: `ls ~/.copilot/agents/adversarial-review.agent.md`
5. Edit the file (add "extra harsh" to the charter), run again, verify the edit is honored (it was not overwritten)

## /copilot:rubber-duck

1. In any repo with a diff: `/copilot:rubber-duck`
2. Expected: a critique back from the rubber-duck agent
3. Compare to `/copilot:review` output on the same diff — note differences in tone and findings
