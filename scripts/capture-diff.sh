#!/usr/bin/env bash
# capture-diff.sh — extract a diff to review based on target args.
#
# Usage:
#   capture-diff.sh                  default = staged + unstaged
#   capture-diff.sh --staged         staged only
#   capture-diff.sh --branch         current branch vs origin/main (or main)
#   capture-diff.sh <ref>..<ref>     git range
#   capture-diff.sh pr <N>           PR diff via gh
#
# Exit codes:
#   0   — diff produced (prints to stdout)
#   64  — usage error (unknown target)
#   66  — empty diff (nothing to review)
#   67  — not in a git repo
#   68  — gh required for pr <N> but not installed/authenticated

set -euo pipefail

# Must be inside a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not in a git repository." >&2
  exit 67
fi

# Parse target
TARGET="default"
RANGE=""
PR=""
case "${1:-}" in
  "")            TARGET="default";;
  --staged)      TARGET="staged";;
  --branch)      TARGET="branch";;
  pr)
    TARGET="pr"
    PR="${2:?pr requires a PR number}"
    ;;
  *..*)
    TARGET="range"
    RANGE="$1"
    ;;
  *)
    echo "Unknown target: $1" >&2
    exit 64
    ;;
esac

emit_or_empty() {
  if [ -s "$1" ]; then
    cat "$1"
  else
    echo "No changes to review for target=$TARGET." >&2
    exit 66
  fi
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

case "$TARGET" in
  default)
    {
      git diff HEAD 2>/dev/null
      git diff --cached 2>/dev/null
    } > "$TMP"
    emit_or_empty "$TMP"
    ;;
  staged)
    git diff --cached > "$TMP"
    emit_or_empty "$TMP"
    ;;
  branch)
    # Try origin/main, fall back to main
    base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)
    if [ -z "$base" ]; then
      echo "Could not find merge base with origin/main or main." >&2
      exit 66
    fi
    git diff "$base"..HEAD > "$TMP"
    emit_or_empty "$TMP"
    ;;
  range)
    git diff "$RANGE" > "$TMP"
    emit_or_empty "$TMP"
    ;;
  pr)
    if ! command -v gh >/dev/null 2>&1; then
      echo "pr target requires the gh CLI. Install: https://cli.github.com/" >&2
      exit 68
    fi
    gh pr diff "$PR" > "$TMP"
    emit_or_empty "$TMP"
    ;;
esac
