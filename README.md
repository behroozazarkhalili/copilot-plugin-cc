# copilot-plugin-cc

GitHub Copilot CLI inside Claude Code. Eight slash commands.

| Command | What it does |
|---|---|
| `/copilot:review` | Standard code review on a diff target |
| `/copilot:adversarial-review` | Harsh "assume wrong until proven right" review |
| `/copilot:rubber-duck` | Cross-model critique using Copilot's complementary-model agent |
| `/copilot:rescue` | Delegate a task to GitHub's cloud agent → draft PR |
| `/copilot:status` | List active cloud-agent jobs |
| `/copilot:result <id>` | Fetch result of a finished job |
| `/copilot:cancel <id>` | Cancel an active job |
| `/copilot:setup` | Verify install + auth + agent installation |

## Requirements

- Claude Code (current version)
- GitHub Copilot CLI ≥ 1.0.10 — install via `npm install -g @github/copilot`
- A GitHub Copilot subscription:
  - **Pro** is sufficient for `/copilot:review` and `/copilot:adversarial-review` if you accept the limited model set (typically: gpt-5.2, gpt-5.2-codex, gpt-5-mini, gpt-4.1, claude-haiku-4.5).
  - **Pro+** unlocks Claude Sonnet/Opus, Gemini, and the cloud-agent commands (`/copilot:rescue`, `/copilot:status`, `/copilot:result`, `/copilot:cancel`).
- Optional: `gh` CLI for the `pr <N>` target form
- Optional: `bats-core` for running the test suite

## Quick start

```bash
# 1. Install Copilot CLI
npm install -g @github/copilot

# 2. Authenticate (OAuth device flow — opens browser)
copilot login

# 3. Install the plugin (Claude Code)
/plugin marketplace add ~/Downloads/copilot-plugin-cc

# 4. Verify everything
/copilot:setup

# 5. Run your first review
/copilot:review              # reviews staged + unstaged
/copilot:review --branch     # reviews current branch vs main
/copilot:review pr 42        # reviews PR #42 (gh required)
/copilot:review --model opus # uses Claude Opus 4.7 (Pro+)
```

## Model aliases

The `--model` flag accepts either a full model id or one of these aliases:

| Alias | Resolves to | Pro plan? | Pro+ plan? |
|---|---|---|---|
| `auto` (default omit) | (Copilot picks) | ✓ | ✓ |
| `codex` | `gpt-5.2-codex` | ✓ | ✓ |
| `gpt` | `gpt-5.4` → `gpt-5.2` → `gpt-5.1` | partial | ✓ |
| `gpt-mini` | `gpt-5.4-mini` → `gpt-5-mini` | partial | ✓ |
| `gpt-4` | `gpt-4.1` | ✓ | ✓ |
| `haiku` | `claude-haiku-4.5` | ✓ | ✓ |
| `sonnet` | `claude-sonnet-4.7` → `4.6` → `4.5` | ✗ | ✓ |
| `opus` | `claude-opus-4.7` → `4.6` → `4.5` | ✗ | ✓ |
| `gemini` | `gemini-4` → `gemini-3.1-pro` → `gemini-3-pro-preview` | ✗ | varies (policy) |

The plugin probes each candidate on the user's plan and yields the first available. Non-silent substitution: if `sonnet` lands on `4.6` instead of `4.7`, the command prints the substitution before running.

## Multi-account auth (gh + Copilot can use different GitHub accounts)

`gh` CLI auth and `copilot` CLI auth are independent. You can:
- `gh` authenticated as `accountA` (where your code lives)
- `copilot` authenticated as `accountB` (where your Pro+ subscription lives)

`/copilot:review`, `/copilot:adversarial-review`, `/copilot:rubber-duck` work fully across accounts — `gh` fetches the diff, Copilot reviews the text. `/copilot:rescue` requires the Copilot-authenticated account to have write access on the target repo.

## Adversarial agent customization

After first run of `/copilot:adversarial-review`, edit `~/.copilot/agents/adversarial-review.agent.md` to tune severity, focus axis, or response length. The plugin will not overwrite your edits.

## State store

Cloud-agent job tracking lives at `${XDG_STATE_HOME:-~/.local/state}/copilot-plugin-cc/jobs.tsv`. Format: TSV with columns `job_id`, `created_at`, `prompt_first_line`, `pr_url`, `status`. Inspect with `cat`, manipulate with `scripts/job-state.sh`.

## Cloud-agent management caveat

As of Copilot CLI 1.0.47, there is **no CLI verb for cloud-agent job status, result, or cancel**. The plugin's `/copilot:status`, `/copilot:result`, and `/copilot:cancel` commands maintain a local TSV view and direct you to the GitHub web UI at https://github.com/copilot/agents for live status and server-side cancellation. If GitHub ships CLI verbs in a future release, these commands will be updated to use them — the command surface won't change. See `tests/manual/cloud-agent-research.md` for details.

## Testing

```bash
bats tests/                      # unit tests for shell scripts
cat tests/manual/smoke.md        # manual smoke checklist for command .md files
```

Shellcheck:
```bash
shellcheck scripts/*.sh tests/test_helper.bash
```

## Spec

Full design in `docs/superpowers/specs/2026-05-13-copilot-plugin-cc-design.md`. Implementation plan in `docs/superpowers/plans/2026-05-13-copilot-plugin-cc.md`.

## License

Apache-2.0. See `LICENSE`.

## Acknowledgments

Modeled on `openai/codex-plugin-cc`. The structure (review + adversarial + rescue + status + result + cancel + setup) is intentionally parallel so users familiar with one can use the other. `/copilot:rubber-duck` has no codex analog and is the strongest reason to choose this plugin over codex-plugin-cc for review work.
