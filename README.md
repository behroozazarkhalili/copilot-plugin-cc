# copilot-plugin-cc

GitHub Copilot CLI inside Claude Code. Eight slash commands for code review (`/copilot:review`, `/copilot:adversarial-review`, `/copilot:rubber-duck`), cloud-agent delegation (`/copilot:rescue` + `/copilot:status` + `/copilot:result` + `/copilot:cancel`), and `/copilot:setup`.

Status: **v0.1.0 — under development**. See `docs/superpowers/plans/` for the implementation plan.

## Requirements

- Claude Code (any current version)
- GitHub Copilot CLI ≥ 1.0.10 — install via `npm install -g @github/copilot`
- A GitHub Copilot subscription (Pro for review-only, Pro+ for full model coverage + cloud-agent rescue)
- Optional: gh CLI for the `pr <N>` target form
- Optional: bats-core for running the test suite

## Quick start

```bash
copilot login           # one-time OAuth device flow
/plugin marketplace add ~/Downloads/copilot-plugin-cc   # in Claude Code
/copilot:setup          # verify install + auth
/copilot:review         # review uncommitted changes
```

## Commands

Full reference: see `commands/*.md` and the spec at `docs/superpowers/specs/2026-05-13-copilot-plugin-cc-design.md`.

## Testing

```bash
bats tests/
```

## License

Apache-2.0. See `LICENSE`.
