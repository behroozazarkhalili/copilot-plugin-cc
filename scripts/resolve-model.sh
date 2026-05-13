#!/usr/bin/env bash
# resolve-model.sh — resolve a Copilot model alias to a concrete model id,
# probing for availability with fallback chains. See spec section "Model resolution".
#
# Usage: resolve-model.sh <alias-or-full-id>
# Exit codes:
#   0   — resolved successfully (prints model id to stdout)
#   64  — usage error (bad arg, unknown alias)
#   65  — chain exhausted (no model in chain is available on user's plan)

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: resolve-model.sh <alias-or-full-model-id>

Aliases (each with a fallback chain):
  sonnet    claude-sonnet-4.7 → 4.6 → 4.5
  opus      claude-opus-4.7 → 4.6 → 4.5
  haiku     claude-haiku-4.5
  codex     gpt-5.2-codex → gpt-5.1-codex
  gpt       gpt-5.4 → gpt-5.2 → gpt-5.1
  gpt-mini  gpt-5.4-mini → gpt-5-mini
  gpt-4     gpt-4.1
  gemini    gemini-4 → gemini-3.1-pro → gemini-3-pro-preview
  auto      (omit --model flag, returns empty string)

Full model ids pass through unchanged after a single availability check.
EOF
  exit 64
}

[ $# -eq 1 ] || usage

ALIAS="$1"

# Probe whether a model id is available on the current Copilot auth.
# Returns 0 if available, 1 if not.
probe_model() {
  local m="$1"
  local out
  out=$(copilot -p "ok" --silent --model "$m" 2>&1 | head -1 || true)
  case "$out" in
    *"not available"*) return 1;;
    *Error:*)          return 1;;
    *)                 return 0;;
  esac
}

resolve_chain() {
  local chain=("$@")
  local primary="${chain[0]}"
  for candidate in "${chain[@]}"; do
    if probe_model "$candidate"; then
      if [ "$candidate" != "$primary" ]; then
        # Human-readable substitution diagnostic to stderr;
        # only the resolved model id goes to stdout so callers can
        # cleanly capture it with $(...) and pass it as --model.
        echo "Resolved --model $ALIAS → $candidate ($primary not available on your plan)" >&2
      fi
      echo "$candidate"
      return 0
    fi
  done
  cat >&2 <<EOF
None of {${chain[*]}} are available on your plan.
Run /model in copilot to see your enabled models, or upgrade to Pro+ at
https://github.com/settings/copilot.
EOF
  return 65
}

case "$ALIAS" in
  auto)     echo ""; exit 0;;
  sonnet)   resolve_chain claude-sonnet-4.7 claude-sonnet-4.6 claude-sonnet-4.5;;
  opus)     resolve_chain claude-opus-4.7 claude-opus-4.6 claude-opus-4.5;;
  haiku)    resolve_chain claude-haiku-4.5;;
  codex)    resolve_chain gpt-5.2-codex gpt-5.1-codex;;
  gpt)      resolve_chain gpt-5.4 gpt-5.2 gpt-5.1;;
  gpt-mini) resolve_chain gpt-5.4-mini gpt-5-mini;;
  gpt-4)    resolve_chain gpt-4.1;;
  gemini)   resolve_chain gemini-4 gemini-3.1-pro gemini-3-pro-preview;;
  *)
    # Full id pass-through with single availability check
    case "$ALIAS" in
      claude-*|gpt-*|gemini-*|o[0-9]*-*)
        if probe_model "$ALIAS"; then echo "$ALIAS"; exit 0
        else echo "Error: $ALIAS not available on your plan." >&2; exit 65; fi
        ;;
      *) echo "unknown alias '$ALIAS'" >&2; usage;;
    esac
    ;;
esac
