#!/usr/bin/env bash
# job-state.sh — manage the cloud-job state file at
#   $XDG_STATE_HOME/copilot-plugin-cc/jobs.tsv
# (or ~/.local/state/copilot-plugin-cc/jobs.tsv if XDG_STATE_HOME unset).
#
# Subcommands:
#   append <job_id> <prompt_first_line> <pr_url> <status>
#   list [--all] [--json]
#   update <job_id> <new_status>
#
# TSV columns: job_id, created_at_iso8601, prompt_first_line, pr_url, status

set -euo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
DIR="$STATE_HOME/copilot-plugin-cc"
TSV="$DIR/jobs.tsv"
mkdir -p "$DIR"
[ -f "$TSV" ] || : > "$TSV"

LOCK="$DIR/.lock"

with_lock() {
  (
    exec 9>"$LOCK"
    flock 9
    "$@"
  )
}

cmd_append() {
  local job_id="$1" prompt="$2" pr_url="$3" status="$4"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf "%s\t%s\t%s\t%s\t%s\n" "$job_id" "$now" "$prompt" "$pr_url" "$status" >> "$TSV"
}

cmd_list() {
  local all=0 json=0
  for a in "$@"; do
    case "$a" in
      --all)  all=1;;
      --json) json=1;;
    esac
  done

  if [ "$json" -eq 1 ]; then
    awk -F'\t' -v all="$all" '
      {
        if (!all && ($5 == "cancelled" || $5 == "failed")) next
        printf "{\"job_id\":\"%s\",\"created_at\":\"%s\",\"prompt\":\"%s\",\"pr_url\":\"%s\",\"status\":\"%s\"}\n",
               $1, $2, $3, $4, $5
      }
    ' "$TSV" | jq -s '.'
  else
    printf "%-12s %-20s %-10s %s\n" "JOB ID" "CREATED" "STATUS" "PR"
    awk -F'\t' -v all="$all" '
      {
        if (!all && ($5 == "cancelled" || $5 == "failed")) next
        printf "%-12s %-20s %-10s %s\n", substr($1,1,12), $2, $5, $4
      }
    ' "$TSV"
  fi
}

cmd_update() {
  local job_id="$1" new_status="$2"
  local tmp
  tmp=$(mktemp)
  awk -F'\t' -v id="$job_id" -v st="$new_status" '
    BEGIN { OFS="\t" }
    $1 == id { $5 = st }
    { print }
  ' "$TSV" > "$tmp" && mv "$tmp" "$TSV"
}

case "${1:-}" in
  append) shift; with_lock cmd_append "$@";;
  list)   shift; with_lock cmd_list "$@";;
  update) shift; with_lock cmd_update "$@";;
  *)
    cat >&2 <<EOF
usage: job-state.sh <subcommand> [args]

Subcommands:
  append <job_id> <prompt_first_line> <pr_url> <status>
  list   [--all] [--json]
  update <job_id> <new_status>
EOF
    exit 64
    ;;
esac
