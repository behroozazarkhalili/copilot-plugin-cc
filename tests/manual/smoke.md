# Manual smoke tests for command .md files

These tests cover the slash commands, which are Claude Code prompts and can't be unit-tested via bats. Run them in a Claude Code session after installing the plugin locally.

## /copilot:review

1. `cd ~/Downloads/copilot-plugin-cc` (or any git repo with uncommitted changes)
2. Make a trivial edit so there's a diff
3. In Claude Code: `/copilot:review`
4. Expected: a markdown code review streams back
5. Then: `/copilot:review --model codex` — should explicitly resolve to gpt-5.2-codex
6. Then in a repo with NO diff: `/copilot:review` — should say "No changes to review"
