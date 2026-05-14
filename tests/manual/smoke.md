# Manual smoke tests for command .md files

These tests cover the slash commands, which are Claude Code prompts and can't be unit-tested via bats. Run them in a Claude Code session after installing the plugin locally.

## /copilot:review

1. `cd ~/Downloads/copilot-plugin-cc` (or any git repo with uncommitted changes)
2. Make a trivial edit so there's a diff
3. In Claude Code: `/copilot:review`
4. Expected: a markdown code review streams back
5. Then: `/copilot:review --model codex` — should explicitly resolve to gpt-5.3-codex (or gpt-5.2-codex on accounts where 5.3 isn't entitled)
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

## /copilot:rescue (Pro+ required for true cloud dispatch)

1. In a repo: `/copilot:rescue add a one-line comment to README`
2. Expected on Pro+: job_id printed, draft PR URL printed, row in jobs.tsv
3. Expected on Pro: response comes back locally with upgrade footer
4. Verify TSV: `cat ~/.local/state/copilot-plugin-cc/jobs.tsv`

## /copilot:status

1. `/copilot:status` — lists tracked jobs + GitHub URL
2. `/copilot:status --all` — also shows cancelled/failed
3. `/copilot:status --json` — JSON array, no web-URL footer

## /copilot:result <id>

1. `/copilot:result <prefix>` — reattaches via copilot --resume, prints PR URL + web URL
2. `/copilot:result <ambiguous>` — should list matches and ask to disambiguate
3. `/copilot:result <nonexistent>` — "No job matches"

## /copilot:cancel <id>

1. Dispatch a job, then `/copilot:cancel <id>`
2. Verify TSV row status is now "cancelled"
3. Verify the printed message includes the GitHub web URL
4. Try `/copilot:cancel <already-completed-id>` → "already $status — nothing to cancel"
