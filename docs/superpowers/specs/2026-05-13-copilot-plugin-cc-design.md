# copilot-plugin-cc — Design Spec

Date: 2026-05-13
Status: Draft, pending user review.
Author: drafted with Claude Code under the superpowers:brainstorming flow.

## Purpose

Bring GitHub Copilot CLI's code-review capability into Claude Code as two slash commands, modeled on `openai/codex-plugin-cc` but stripped to review-only scope. Run reviews from inside a Claude Code session, with a choice of reviewer model (Anthropic, OpenAI, Google) and an optional adversarial mode that uses a custom Copilot agent profile.

## Out of scope (explicitly)

- No cloud delegation (`/copilot:rescue`, `/copilot:status`, `/copilot:result`, `/copilot:cancel`).
- No subagent.
- No Stop / PostToolUse hook (no auto-review gate).
- No MCP server.
- No `/copilot:setup` command. Setup is documented in the README; auth is `copilot login` run by the user once.

## Commands

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

Execution flow when Claude runs the command:

1. Parse args — target (one of the forms above) plus optional `--model`.
2. Capture diff into `/tmp/copilot-review-<sessionid>.diff`. Exit with "no changes" if empty.
3. Resolve model alias via `scripts/resolve-model.sh` (see Model resolution).
4. Invoke `copilot -p --silent --agent=code-review` with the resolved model and the diff piped on stdin.
5. Stream the markdown review back into Claude's transcript.

### `/copilot:adversarial-review`

Same input surface and same `--model` flag. Uses a shipped custom agent `~/.copilot/agents/adversarial-review.agent.md` instead of Copilot's built-in `code-review`.

The custom agent's charter:

  Assume the code is wrong until proven right. Hunt for security holes, off-by-one errors, race conditions, and unhandled error paths. Flag over-abstraction and premature optimization. Demand justification for every new dependency. Refuse to give a "looks good" verdict without specific evidence pointing at why.

Execution flow:

1. Same arg parse + diff capture as `/copilot:review`.
2. On first run, copy `agents/adversarial-review.agent.md` from the plugin install dir to `~/.copilot/agents/adversarial-review.agent.md` if it does not exist. User can edit that file thereafter; the plugin does not overwrite it on subsequent runs.
3. Invoke `copilot -p --silent --agent=adversarial-review --model <resolved>` with the diff piped on stdin.
4. Stream the review back.

The custom agent file is also callable directly from a normal terminal (`copilot --agent=adversarial-review -p "..."`), so the value persists outside Claude Code too.

## Model resolution

Default behavior: no `--model` flag means Copilot's Auto picker chooses.

When `--model` is passed, the value is either a full model id (passes through unchanged) or an alias resolved by `scripts/resolve-model.sh`:

| Alias | Primary target | Fallback chain (when primary not available on user's plan) |
|---|---|---|
| `sonnet` | `claude-sonnet-4.7` | `claude-sonnet-4.6` → `claude-sonnet-4.5` |
| `opus` | `claude-opus-4.7` | `claude-opus-4.6` → `claude-opus-4.5` |
| `haiku` | `claude-haiku-4.5` | (no fallback — single supported variant) |
| `codex` | `gpt-5.2-codex` | `gpt-5.1-codex` |
| `gpt` | `gpt-5.4` | `gpt-5.2` → `gpt-5.1` |
| `gpt-mini` | `gpt-5.4-mini` | `gpt-5-mini` |
| `gemini` | `gemini-4` | `gemini-3.1-pro` → `gemini-3-pro-preview` |
| `auto` | (omit `--model` flag) | — |

`scripts/resolve-model.sh` probes `copilot --model help` once per session (cached to `/tmp/copilot-models-<sessionid>.txt`) and picks the first available entry in the fallback chain. If none of the entries in the chain are present, the script exits with a clear error pointing the user at `copilot /model` to verify their plan.

Full model ids are always pass-through, e.g. `/copilot:review --model claude-sonnet-4.5` works regardless of alias availability.

## Plugin layout

```
copilot-plugin-cc/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── review.md
│   └── adversarial-review.md
├── agents/
│   └── adversarial-review.agent.md
├── scripts/
│   └── resolve-model.sh
├── tests/
│   ├── test_resolve_model.bats
│   └── fixtures/
├── README.md
└── LICENSE
```

### `.claude-plugin/plugin.json`

```json
{
  "name": "copilot",
  "version": "0.1.0",
  "description": "GitHub Copilot CLI code review inside Claude Code. Two commands: /copilot:review (standard) and /copilot:adversarial-review (harsh). Optional --model picker with aliases.",
  "author": {
    "name": "Ermia Azarkhalili",
    "url": "https://github.com/behroozazarkhalili"
  },
  "homepage": "https://github.com/behroozazarkhalili/copilot-plugin-cc",
  "license": "Apache-2.0",
  "commands": [
    {
      "name": "review",
      "file": "commands/review.md"
    },
    {
      "name": "adversarial-review",
      "file": "commands/adversarial-review.md"
    }
  ]
}
```

## Auth

The plugin does not handle authentication. README directs users to run once:

```bash
copilot login
```

This opens an OAuth device flow against the user's GitHub account (which must be linked to their Microsoft email and have an active Copilot subscription — Pro, Pro+, Business, or Enterprise). The plugin checks for `copilot` binary presence and a working `copilot --version` invocation; if missing, it instructs the user to install Copilot CLI and re-run.

## Error handling

The plugin surfaces three classes of error with clear messages:

  Missing binary. `copilot` not on PATH → message: "Install Copilot CLI: npm install -g @github/copilot-cli (or see https://docs.github.com/copilot/how-tos/copilot-cli/install-copilot-cli)".

  Not authenticated. `copilot --version` works but invocation returns auth error → message: "Run `copilot login` once to authenticate."

  Model unavailable. Alias chain exhausted, no variant available on user's plan → message: "None of {chain} are available on your plan. Run `copilot /model` to see your enabled models, then pass a full model id via --model."

The plugin never silently substitutes a different model than what the user asked for. If `--model sonnet` resolves to a fallback (e.g. `claude-sonnet-4.6` because 4.7 is not enabled), the plugin prints `Resolved --model sonnet → claude-sonnet-4.6 (4.7 not available on your plan)` before running. This keeps the user in control.

## Testing

`tests/test_resolve_model.bats` covers the alias resolution logic with bats-core. Fixtures simulate three plan states:

  - Pro+ user with 4.7 enabled → primary targets hit.
  - Pro user with 4.6 latest → fallbacks hit.
  - Plan with neither 4.7 nor 4.6 → error path.

No end-to-end test against the live Copilot API. The plugin's job is to construct the right command and parse the right output; verifying the Copilot API itself is out of scope.

## Open risks

  - Sonnet 4.7 is unconfirmed in public GitHub Copilot changelogs as of 2026-05-13. The alias `sonnet` may resolve to `claude-sonnet-4.6` for most users until 4.7 ships.
  - Gemini 4 is unconfirmed in public docs as of 2026-05-13 (latest Gemini on Copilot CLI is `gemini-3.1-pro` per Google models hosting doc). Same fallback handling applies.
  - Copilot CLI's `--model` flag list is not programmatically queryable today (issue #700 open). The fallback probe relies on parsing `copilot --model help` output, whose format may change. Tests pin against fixture output; if the format changes, tests fail loudly.
  - `--silent -p` mode was added in the Jan 2026 changelog. The plugin requires Copilot CLI >= 1.0.10 (rough estimate; will pin to the actual minimum in the README during implementation).
  - License is Apache-2.0 to match codex-plugin-cc. The user has not stated a preference.

## What this design does NOT decide

  - The exact wording of the adversarial agent charter. The shipped file is a starting point; user is expected to edit `~/.copilot/agents/adversarial-review.agent.md` to taste.
  - Marketplace publication. The plugin is local-first (private GitHub repo). Public marketplace listing is a later, separate decision.
  - Whether to add a `--output <file>` flag for writing the review to disk. YAGNI for v0.1.

## Approval gate

This design is the contract. Before any implementation, the user reviews this document and either approves or requests changes. Implementation begins only after explicit approval via the writing-plans flow.
