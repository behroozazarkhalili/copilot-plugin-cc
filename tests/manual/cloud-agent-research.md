# Cloud-agent CLI surface — research note (2026-05-13)

The spec assumed Copilot CLI exposes `delegate`/`job` subcommands for managing cloud-agent jobs. Direct probe of CLI 1.0.47 found:

| Imagined verb | Reality |
|---|---|
| `copilot delegate <prompt>` | Does not exist as a subcommand. The `&` prefix on a `-p` prompt is the documented delegation trigger: `copilot -p "&<prompt>"`. |
| `copilot job status <id>` | No `job` subcommand exists. No CLI verb for listing cloud-agent jobs. |
| `copilot job result <id>` | Closest equivalent: `copilot --resume=<session-id>` reattaches to the session locally. |
| `copilot job cancel <id>` | No CLI verb. Must cancel via the GitHub web UI. |

## Implications for the plugin

- `/copilot:rescue` wraps `copilot -p "&<prompt>"`. On plans without cloud-agent entitlement (Pro), this responds locally instead of dispatching — that's a Copilot product behavior, not a plugin bug.
- `/copilot:status` reads the local TSV state (jobs the user dispatched via /copilot:rescue) AND prints the GitHub web URL for live status.
- `/copilot:result <id>` either uses `copilot --resume=<id>` (best-effort local view) or directs to the web URL.
- `/copilot:cancel <id>` has no programmatic option today. Updates the local TSV optimistically + prints the cancel-via-web URL.

If GitHub ships CLI verbs for these in a future release, swap the implementations without changing the command surface.
