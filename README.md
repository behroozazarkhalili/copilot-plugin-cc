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

## Installation & first run

### 1. Install the GitHub Copilot CLI

The plugin shells out to the official `copilot` binary, so you need it on your PATH.

```bash
# Requires Node.js ≥ 18 already installed on your system
npm install -g @github/copilot

# Verify
copilot --version
# → GitHub Copilot CLI 1.0.47 (or newer)
```

Platform notes:
- **Linux**: tested on Ubuntu 22.04 with Node 22 (nvm). Works on any distro with Node ≥ 18.
- **macOS**: works the same way. If `npm install -g` complains about permissions, prefer `nvm` over a system-wide install.
- **Windows**: works via WSL2 or native Windows + Node.js. Claude Code's plugin loader is path-agnostic.

If `npm` warns about the package not being found, ensure your registry is `https://registry.npmjs.org` and you're not behind an internal proxy.

### 2. Authenticate Copilot (OAuth device flow)

```bash
copilot login
```

This opens a browser to `github.com/login/device`. You'll see a code in the terminal — paste it into the browser, approve, and the CLI confirms.

Verify auth landed:

```bash
copilot -p "say hi" --silent
# → returns a one-line greeting (any error here = auth incomplete)
```

**Multi-account note:** `gh` CLI and `copilot` CLI authenticate independently. You can leave `gh` logged in as your work account and authenticate `copilot` with the account that holds your Copilot subscription. The plugin does the right thing across the seam — see [Multi-account auth](#multi-account-auth-gh--copilot-can-use-different-github-accounts) below.

### 3. Install the plugin into Claude Code

Clone or download this repo to `~/Downloads/copilot-plugin-cc` (or anywhere). Then from inside a Claude Code session:

```
/plugin marketplace add ~/Downloads/copilot-plugin-cc
/plugin install copilot
/reload-plugins
```

All eight `/copilot:*` commands should now appear when you start typing `/copilot:` in the prompt.

### 4. Verify the install

```
/copilot:setup
```

This is idempotent — safe to run any time. It checks:
- `copilot` binary on PATH and version
- Copilot is authenticated (`-p "ok" --silent` returns without an auth error)
- `~/.copilot/agents/adversarial-review.agent.md` is present (auto-installs on first run if missing)
- Probes which model aliases are entitled on your plan and prints a per-alias availability table
- The XDG state directory for cloud-agent job tracking
- `gh` CLI presence (optional; enables the `pr <N>` target form)

Sample output on a Pro plan:

```
✓ copilot binary: GitHub Copilot CLI 1.0.47
✓ authenticated
✓ adversarial-review agent installed
Available models per alias:
  sonnet     → UNAVAILABLE (Pro+ required)
  opus       → UNAVAILABLE (Pro+ required)
  haiku      → claude-haiku-4.5
  codex      → gpt-5.2-codex
  gpt        → gpt-5.2 (substituted from gpt-5.4)
  gpt-mini   → gpt-5.4-mini
  gpt-4      → gpt-4.1
  gemini     → UNAVAILABLE (not on Pro)
✓ gh CLI present (user: yourname) — pr <N> target available
```

### 5. Run your first review

```
/copilot:review
```

With no arguments, that reviews **staged + unstaged** changes in the current git repo using the default reviewer model (`gpt-5.2-codex`). You should see a streamed markdown review back in the transcript.

## Commands — usage with examples

Every command's full behavior lives in `commands/<name>.md`. Below are the practical recipes.

### `/copilot:setup` — verify install + auth

```
/copilot:setup
```

Idempotent. Run after install, after `copilot login`, after changing plans, or whenever something feels broken. Reports each check as `✓` or `✗` with the fix command for any failure.

### `/copilot:review [target] [--model alias]` — standard code review

Targets:

```
/copilot:review                       # staged + unstaged in cwd
/copilot:review --staged              # staged only
/copilot:review --branch              # current branch vs main
/copilot:review HEAD~3..HEAD          # arbitrary git range
/copilot:review pr 1234               # PR #1234 (needs gh CLI)
```

Override the reviewer LLM:

```
/copilot:review --model codex         # gpt-5.2-codex (default — best for code review)
/copilot:review --model haiku         # claude-haiku-4.5 (Pro)
/copilot:review --branch --model opus # Claude Opus 4.7 (Pro+)
/copilot:review --model gpt-4         # gpt-4.1 fallback
```

If the alias chain exhausts on your plan, you'll get a clear `exit 65` message — pick a different alias.

### `/copilot:adversarial-review [target] [--model alias]` — harsh review

Same target/`--model` grammar as `/copilot:review`. Uses a shipped agent profile (`~/.copilot/agents/adversarial-review.agent.md`) calibrated to be suspicious — assumes the diff is wrong until proven right and prefers REJECT/REQUEST CHANGES verdicts on close calls.

```
/copilot:adversarial-review --staged           # stress-test current staged diff
/copilot:adversarial-review pr 4421            # stress-test a PR
/copilot:adversarial-review --branch --model codex
```

First run auto-installs the agent file. After that, edit `~/.copilot/agents/adversarial-review.agent.md` to tune severity / focus axis / response length — the plugin won't overwrite your edits.

### `/copilot:rubber-duck "<thought or hypothesis>"` — cross-model critique

The only command without a codex-plugin-cc analog. Uses Copilot's built-in rubber-duck agent which deliberately picks a model complementary to your main Claude Code session for blind-spot detection.

```
/copilot:rubber-duck "the 500 error happens because the retry loop double-increments the counter on 429"
/copilot:rubber-duck "I think this race condition is in the finally block but I'm not sure"
```

Useful right after `/pro-debug` proposes a root cause and you want a second-brain check before committing to a fix.

### `/copilot:rescue "<task>" [--model alias]` — delegate to cloud agent

```
/copilot:rescue "add rate limiting to /api/login with 5 attempts per minute per IP"
/copilot:rescue "migrate the legacy session storage from Redis to PostgreSQL"
```

**Pro+ plans:** creates a feature branch, opens a draft PR, and runs the agent in the background. The job id and PR URL are saved to the local TSV at `${XDG_STATE_HOME:-~/.local/state}/copilot-plugin-cc/jobs.tsv`. Track it with `/copilot:status`.

**Pro plans (no cloud-agent entitlement):** the command degrades gracefully — Copilot CLI runs the task locally in your current terminal instead of dispatching to the cloud. You still get the result, just without the draft PR.

### `/copilot:status` — list active cloud-agent jobs

```
/copilot:status                       # active jobs only (default)
/copilot:status --all                 # include cancelled / finished
/copilot:status --json                # machine-readable TSV→JSON
```

Reads the local TSV and prints a table with job id, age, prompt first line, PR URL, status. Live server-side status lives at https://github.com/copilot/agents (linked in the footer).

### `/copilot:result <id>` — fetch result of a finished job

```
/copilot:result abc123
```

Looks up the job in the local TSV, prints its PR URL, and tells you how to inspect the result on GitHub. If/when Copilot CLI ships a native `result` verb, this command will use it transparently.

### `/copilot:cancel <id>` — cancel an active job

```
/copilot:cancel abc123
```

Marks the job as `cancelled` in the local TSV. **Server-side cancellation currently requires the GitHub web UI** — the command prints the direct link.

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
