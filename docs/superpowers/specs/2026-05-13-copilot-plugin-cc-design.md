# copilot-plugin-cc — Design Spec

Date: 2026-05-13
Status: Draft, pending user review.
Author: drafted with Claude Code under the superpowers:brainstorming flow.

## Purpose

Bring GitHub Copilot CLI's review and autonomous-execution capabilities into Claude Code as slash commands. Modeled on `openai/codex-plugin-cc` with full command parity plus one Copilot-specific addition (`/copilot:rubber-duck`) that has no codex analog because Codex CLI lacks a dedicated cross-model critique agent.

## Command list (8 total)

| # | Command | Wraps | Category |
|---|---|---|---|
| 1 | `/copilot:review` | `copilot --agent=code-review` on a diff | Review |
| 2 | `/copilot:adversarial-review` | Custom adversarial `.agent.md` on a diff | Review |
| 3 | `/copilot:rubber-duck` | `copilot --agent=rubber-duck` on a diff or piece of code | Review (cross-model) |
| 4 | `/copilot:rescue` | `copilot /delegate` — cloud agent → draft PR | Autonomous |
| 5 | `/copilot:status` | List active cloud-agent jobs | Cloud job mgmt |
| 6 | `/copilot:result <id>` | Fetch result of a finished cloud job | Cloud job mgmt |
| 7 | `/copilot:cancel <id>` | Cancel an active cloud job | Cloud job mgmt |
| 8 | `/copilot:setup` | Verify install + auth + agent-file install | Setup |

## Out of scope (explicitly)

- No Stop hook (review gate). The user already has a heavy hook chain — adding another Stop hook adds latency to every turn for marginal value.
- No PostToolUse review-on-write hook.
- No MCP server.

## Review commands (1–3)

### `/copilot:review`

Standard code review using Copilot's built-in `code-review` agent.

Inputs:

| Form | Behavior |
|---|---|
| `/copilot:review` | Default — combined working dir diff (staged + unstaged). |
| `/copilot:review <ref>..<ref>` | Git range, e.g. `HEAD~5..HEAD`. |
| `/copilot:review pr <N>` | PR by number, fetched via `gh pr diff <N>`. |
| `/copilot:review --staged` | Staged changes only. |
| `/copilot:review --branch` | Current branch vs main. |
| `/copilot:review --model <name-or-alias>` | Optional, combinable with any target. |

Execution flow:

1. Parse args (target + optional `--model`).
2. Capture diff into `/tmp/copilot-review-<sessionid>.diff`. Exit with "no changes" if empty.
3. Resolve model alias via `scripts/resolve-model.sh`.
4. Invoke `copilot -p --silent --agent=code-review --model <resolved>` with the diff piped on stdin.
5. Stream the markdown review back into Claude's transcript.

### `/copilot:adversarial-review`

Same input surface and same `--model` flag. Uses a shipped custom agent `~/.copilot/agents/adversarial-review.agent.md` instead of Copilot's built-in `code-review`.

Agent charter:

  Assume the code is wrong until proven right. Hunt for security holes, off-by-one errors, race conditions, and unhandled error paths. Flag over-abstraction and premature optimization. Demand justification for every new dependency. Refuse to give a "looks good" verdict without specific evidence pointing at why.

On first run, the command copies `agents/adversarial-review.agent.md` from the plugin install dir to `~/.copilot/agents/adversarial-review.agent.md` if it does not exist. The plugin does not overwrite it on subsequent runs — user edits persist.

The custom agent file is also callable directly from a normal terminal (`copilot --agent=adversarial-review -p "..."`), so the value persists outside Claude Code too.

### `/copilot:rubber-duck`

Wraps Copilot's built-in `rubber-duck` agent. Per GitHub's docs, the rubber-duck agent "uses a complementary model to provide a constructive critique" — meaning it explicitly picks a *different* model from the main session to surface blind spots a same-model review would miss.

Inputs: same target grammar as `/copilot:review`. The `--model` flag, when passed, picks the rubber-duck's model (not the main session model). When omitted, Copilot chooses a complementary model automatically.

This command has no codex-plugin-cc analog and is the strongest reason to choose Copilot over Codex for review work — Codex CLI cannot do cross-vendor critique, only same-vendor.

## Autonomous + job management commands (4–7)

### `/copilot:rescue`

Wraps `copilot /delegate` — pushes a task to the GitHub cloud agent. Creates a branch, opens a draft pull request, and runs in the background remotely. Survives your laptop closing.

Inputs:

| Form | Behavior |
|---|---|
| `/copilot:rescue <prompt>` | Delegate the prompt to the cloud agent. |
| `/copilot:rescue --base <branch> <prompt>` | Specify base branch for the draft PR (default: main). |
| `/copilot:rescue --repo <owner/repo> <prompt>` | Cross-repo delegation. |

Execution flow:

1. Parse args.
2. Run `copilot -p "&<prompt>"` (the `&` prefix delegates per Copilot's documented convention).
3. Capture the returned job session ID and PR URL.
4. Append a row to `~/.local/state/copilot-plugin-cc/jobs.tsv` — fields: `job_id`, `created_at`, `prompt_first_line`, `pr_url`, `status`.
5. Print the PR URL and job ID to the Claude transcript.

State store rationale: a TSV under `~/.local/state/` is the simplest cross-session tracker that lets `/copilot:status`, `/copilot:result`, and `/copilot:cancel` find the user's jobs. Jobs are scoped per-user, not per-repo, because Copilot cloud jobs cross repo boundaries.

### `/copilot:status`

Lists active and recent cloud-agent jobs. Reads `~/.local/state/copilot-plugin-cc/jobs.tsv`, refreshes status for each via `copilot job status <id>` (or whatever Copilot's verb is — verified during implementation), and prints a table:

```
JOB ID      AGE     STATUS    PR
abc12345    3m      running   https://github.com/owner/repo/pull/42
def67890    1h      completed https://github.com/owner/repo/pull/41
```

Flags:

- `--all` — include cancelled and failed jobs (default: hide).
- `--json` — machine-readable output for shell scripting.

### `/copilot:result <id>`

Fetches the full output of a finished cloud job. Wraps `copilot job result <id>` and renders the markdown back into the Claude transcript. Shorthand: `<id>` may be a unique prefix of the actual job id.

### `/copilot:cancel <id>`

Cancels an active cloud job. Wraps `copilot job cancel <id>`. Updates `jobs.tsv` row status to `cancelled`. Errors loudly if the job is already finished — does not silently no-op.

## Setup command (8)

### `/copilot:setup`

Verifies the install and authentication state. Runs:

1. `command -v copilot` — checks the CLI is on PATH. If missing, prints install instructions.
2. `copilot --version` — confirms it runs. Records the version.
3. `copilot auth status` (or equivalent) — confirms authentication. If not authenticated, prints "Run `copilot login` to authenticate via OAuth device flow."
4. Verifies `~/.copilot/agents/adversarial-review.agent.md` exists. If missing, copies it from the plugin install dir.
5. Probes available models with `copilot --model help`, caches the list to `/tmp/copilot-models-<sessionid>.txt` so the model resolver doesn't re-probe.
6. Prints a green checklist:
   ```
   ✓ copilot binary: 1.0.31
   ✓ authenticated as: <github-login>
   ✓ adversarial-review agent installed
   ✓ 14 models available (sonnet=claude-sonnet-4.6, opus=claude-opus-4.7, ...)
   ```

`/copilot:setup` is idempotent — safe to run repeatedly. Other commands DO NOT depend on it having been run; they handle their own preconditions inline. `/copilot:setup` is for the user to see the system state, not for the plugin's own gating.

## Model resolution

### Defaults per command category

| Commands | Default when `--model` is omitted |
|---|---|
| `/copilot:review`, `/copilot:adversarial-review`, `/copilot:rubber-duck` | `gpt-5.2-codex` (GitHub's documented best-for-review model). Falls through the `codex` chain if not on plan. |
| `/copilot:rescue` | Auto (omit `--model`) — let Copilot pick based on task. |

Rationale: review work has a documented optimal model; autonomous task execution does not. Pinning the review default makes outputs reproducible across sessions; leaving rescue on Auto keeps the cloud agent's adaptivity.

### Alias map (Pro and Pro+ aware)

When `--model` is passed, the value is either a full model id (passes through unchanged) or an alias resolved by `scripts/resolve-model.sh`:

| Alias | Primary target | Fallback chain |
|---|---|---|
| `sonnet` | `claude-sonnet-4.7` | `claude-sonnet-4.6` → `claude-sonnet-4.5` |
| `opus` | `claude-opus-4.7` | `claude-opus-4.6` → `claude-opus-4.5` |
| `haiku` | `claude-haiku-4.5` | (no fallback) |
| `codex` | `gpt-5.2-codex` | `gpt-5.1-codex` |
| `gpt` | `gpt-5.4` | `gpt-5.2` → `gpt-5.1` |
| `gpt-mini` | `gpt-5.4-mini` | `gpt-5-mini` |
| `gpt-4` | `gpt-4.1` | (no fallback) |
| `gemini` | `gemini-4` | `gemini-3.1-pro` → `gemini-3-pro-preview` |
| `auto` | (omit `--model` flag) | — |

### Pro vs Pro+ behavior

Pro+ subscribers typically have all aliases resolvable on the primary target. Pro subscribers usually see a narrower available set — Claude Sonnet/Opus and Gemini frequently require Pro+. The plugin handles both:

  Pro+ user → most aliases hit primary target. `sonnet` → `claude-sonnet-4.7`, `opus` → `claude-opus-4.7`, etc.

  Pro user → premium aliases fall through their chain and then error out cleanly. `sonnet` exhausts {4.7, 4.6, 4.5} and surfaces: `None of {claude-sonnet-4.7, claude-sonnet-4.6, claude-sonnet-4.5} are available on your plan. Run /model in copilot to see your enabled models, or upgrade to Pro+ at github.com/settings/copilot.`

  Same plugin code, same alias map — the resolver script discovers the user's effective plan at first call by probing each candidate. Available models are cached at `/tmp/copilot-models-<sessionid>.txt` for the duration of the session.

### Discovery mechanics

`scripts/resolve-model.sh` does not parse `copilot --model help` output (the help text no longer enumerates models as of CLI 1.0.47). Instead it probes each candidate from the fallback chain via `copilot -p "ok" --silent --model <candidate>`, treats `not available` errors as a signal to advance, and pins the first available variant. The probe cost is ~3 seconds per model on first invocation; cached results make subsequent calls instant.

### Non-silent substitution

The plugin never silently substitutes a different model than what the user asked for. When `sonnet` resolves to a fallback (e.g. `claude-sonnet-4.6` because 4.7 is not enabled), the command prints `Resolved --model sonnet → claude-sonnet-4.6 (4.7 not available on your plan)` before running. When the chain exhausts entirely, the command errors and exits — it never auto-promotes to a different alias family.

## Plugin layout

```
copilot-plugin-cc/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── review.md
│   ├── adversarial-review.md
│   ├── rubber-duck.md
│   ├── rescue.md
│   ├── status.md
│   ├── result.md
│   ├── cancel.md
│   └── setup.md
├── agents/
│   └── adversarial-review.agent.md
├── scripts/
│   ├── resolve-model.sh
│   ├── capture-diff.sh
│   └── job-state.sh
├── tests/
│   ├── test_resolve_model.bats
│   ├── test_capture_diff.bats
│   ├── test_job_state.bats
│   └── fixtures/
├── README.md
└── LICENSE
```

### `.claude-plugin/plugin.json`

```json
{
  "name": "copilot",
  "version": "0.1.0",
  "description": "GitHub Copilot CLI inside Claude Code — review (code-review, adversarial, rubber-duck), rescue (cloud-agent delegation), job management, and setup. 8 commands.",
  "author": {
    "name": "Ermia Azarkhalili",
    "url": "https://github.com/behroozazarkhalili"
  },
  "homepage": "https://github.com/behroozazarkhalili/copilot-plugin-cc",
  "license": "Apache-2.0",
  "commands": [
    { "name": "review",              "file": "commands/review.md" },
    { "name": "adversarial-review",  "file": "commands/adversarial-review.md" },
    { "name": "rubber-duck",         "file": "commands/rubber-duck.md" },
    { "name": "rescue",              "file": "commands/rescue.md" },
    { "name": "status",              "file": "commands/status.md" },
    { "name": "result",              "file": "commands/result.md" },
    { "name": "cancel",              "file": "commands/cancel.md" },
    { "name": "setup",               "file": "commands/setup.md" }
  ]
}
```

## State store

Cloud-agent job tracking lives at `~/.local/state/copilot-plugin-cc/jobs.tsv` per the XDG Base Directory spec. Format:

```
job_id<TAB>created_at_iso8601<TAB>prompt_first_line<TAB>pr_url<TAB>status
```

`scripts/job-state.sh` provides three primitives: `append <fields>`, `list [--all] [--json]`, and `update <job_id> <new_status>`. Commands 4–7 use these primitives; the state file is the source of truth for the plugin's own view of jobs (Copilot's server is the authoritative source for actual job state, which `/copilot:status` queries on each invocation).

## Auth

The plugin does not handle authentication. README and `/copilot:setup` direct users to run once:

```bash
copilot login
```

OAuth device flow against the user's GitHub account. Their Microsoft email must be linked to that GitHub account and the GitHub account must have an active Copilot subscription (Pro, Pro+, Business, or Enterprise — `/copilot:rescue` and the cloud-agent commands additionally require Pro+ or higher per current GitHub policy).

## Error handling

Five error classes surface with clear messages:

  Missing binary. `copilot` not on PATH → "Install Copilot CLI: see https://docs.github.com/copilot/how-tos/copilot-cli/install-copilot-cli"

  Not authenticated. `copilot --version` works but invocation returns auth error → "Run `copilot login` once to authenticate."

  Model unavailable. Alias fallback chain exhausted, no variant available on user's plan → "None of {chain} are available on your plan. Run `copilot /model` to see your enabled models, then pass a full model id via --model."

  No diff. Diff capture produced empty output → "No changes to review. Stage some changes or pass a target (e.g. /copilot:review HEAD~5..HEAD)."

  Cloud-agent unavailable. `/copilot:rescue` invoked on a plan that doesn't include cloud agents → "Cloud-agent delegation requires Copilot Pro+ or higher. You appear to be on {plan}. See https://docs.github.com/copilot for upgrade options."

The plugin never silently substitutes a different model than what the user asked for.

## Testing

Three bats-core test files cover the scripts directory:

  `tests/test_resolve_model.bats` — alias resolution with plan-state fixtures (Pro+ with 4.7, Pro with 4.6, plan missing both).

  `tests/test_capture_diff.bats` — diff capture for the five target forms (default, range, pr, staged, branch). Uses temp git repos in fixtures.

  `tests/test_job_state.bats` — TSV append/list/update with concurrent-write safety check.

No end-to-end test against the live Copilot API. The plugin's job is to construct the right command and parse the right output; verifying the Copilot API itself is out of scope.

## Open risks

  - Sonnet 4.7 is unconfirmed in public GitHub Copilot changelogs as of 2026-05-13. The alias `sonnet` may resolve to `claude-sonnet-4.6` for Pro+ users with 4.7 still rolling out, and is **not available at all** on Pro plans.
  - Gemini 4 is unconfirmed in public docs as of 2026-05-13. The alias `gemini` may resolve to `gemini-3.1-pro` for Pro+ users with Gemini access. Gemini is **not available** on Pro plans.
  - Author's own Copilot Pro plan currently has only 5 models enabled (`claude-haiku-4.5`, `gpt-5.2`, `gpt-5.2-codex`, `gpt-5-mini`, `gpt-4.1`), confirmed by direct probe on 2026-05-13. This is the canonical "Pro" plan shape the plugin must handle gracefully. Pro+ shape is inferred from GitHub docs (full Claude + GPT + Gemini coverage).
  - The exact verb for cloud-job status/result/cancel (`copilot job status`, `copilot delegate status`, or other) needs verification during implementation. The spec uses `copilot job <verb>` as a placeholder; will pin to actual verbs in code.
  - Copilot CLI's `--model` flag list is not programmatically queryable today (github/copilot-cli#700 open). As of CLI 1.0.47, `copilot help` no longer enumerates models in `--model` description. The resolver script probes each candidate via test invocation rather than parsing help output. Cost: ~3 seconds per probed alias on first call, cached thereafter.
  - `--silent -p` mode was added in the Jan 2026 changelog. The plugin requires Copilot CLI >= 1.0.10 (rough; pinned to actual minimum in README during implementation).
  - The rubber-duck agent's exact behavior around model selection ("uses a complementary model") may differ from the spec's interpretation. The `--model` flag's interaction with rubber-duck is documented in implementation tests, not assumed.
  - `/copilot:rescue` and the cloud-agent commands (`status`, `result`, `cancel`) require GitHub Copilot cloud-agent access, which historically gates on Pro+ or higher. The plugin surfaces a clear error if invoked on a plan that lacks cloud-agent entitlement.

## What this design does NOT decide

  - The exact wording of the adversarial agent charter. The shipped file is a starting point; user edits in `~/.copilot/agents/adversarial-review.agent.md` persist across plugin updates.
  - Marketplace publication. The plugin is local-first (private GitHub repo). Public marketplace listing is a later, separate decision.
  - Whether to add a `--output <file>` flag for writing reviews to disk. YAGNI for v0.1.
  - A subagent equivalent of codex-plugin-cc's `codex:codex-rescue`. The cloud-agent flow runs remotely on GitHub's infrastructure; a local subagent adds nothing.

## Approval gate

This design is the contract. Before any implementation, the user reviews this document and either approves or requests changes. Implementation begins only after explicit approval via the writing-plans flow.
