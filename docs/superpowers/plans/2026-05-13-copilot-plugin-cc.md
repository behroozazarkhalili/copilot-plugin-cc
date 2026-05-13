# copilot-plugin-cc Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that surfaces GitHub Copilot CLI's review and cloud-agent capabilities as eight slash commands.

**Architecture:** A pure-shell, no-runtime plugin. Three shell scripts in `scripts/` provide reusable primitives (model resolution, diff capture, job-state TSV management). Eight `.md` command files in `commands/` are Claude Code prompts that orchestrate Bash invocations of those scripts and `copilot -p`. One `.agent.md` ships to the user's `~/.copilot/agents/` for adversarial review. Tests use bats-core against the shell scripts; commands are smoke-tested manually with a documented checklist.

**Tech Stack:** Bash 5+, jq, git, gh CLI, GitHub Copilot CLI ≥ 1.0.10, bats-core for testing. Apache-2.0 licensed.

**Spec:** `docs/superpowers/specs/2026-05-13-copilot-plugin-cc-design.md` (commit `872ccc1`).

---

## Chunk 1: Scaffolding and shared scripts

This chunk produces a working repo with the manifest, license, CI, and the three shell scripts that the eight commands depend on. After this chunk you can run `bats tests/` and see all unit tests pass.

### Task 1.1: Create `.gitignore` and LICENSE

**Files:**
- Create: `~/Downloads/copilot-plugin-cc/.gitignore`
- Create: `~/Downloads/copilot-plugin-cc/LICENSE`

- [ ] **Step 1: Write `.gitignore`**

```
# editor
*.swp
*.swo
.DS_Store

# test artifacts
/tests/tmp/
/tests/.bats/

# local state
*.log
/tmp/

# IDE
.vscode/
.idea/
```

- [ ] **Step 2: Write `LICENSE`** — Apache-2.0 boilerplate

Use the standard Apache 2.0 text. The header should read:

```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   Copyright 2026 Ermia Azarkhalili

   Licensed under the Apache License, Version 2.0 (the "License");
   ...
```

Full text at https://www.apache.org/licenses/LICENSE-2.0.txt — copy verbatim with the copyright line above.

- [ ] **Step 3: Commit**

```bash
cd ~/Downloads/copilot-plugin-cc
git add .gitignore LICENSE
git commit -m "chore: add Apache-2.0 license and gitignore"
```

### Task 1.2: Plugin manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Write `.claude-plugin/plugin.json`** — verbatim from spec

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

- [ ] **Step 2: Validate JSON**

Run:
```bash
jq . .claude-plugin/plugin.json > /dev/null && echo "valid"
```
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat(plugin): add manifest with 8 commands"
```

### Task 1.3: Install bats-core test harness

**Files:**
- Create: `tests/test_helper.bash`
- Create: `tests/.gitkeep` (placeholder so the dir is tracked before any tests exist)

- [ ] **Step 1: Verify bats installed**

```bash
command -v bats || echo "NEEDS INSTALL"
```

If `NEEDS INSTALL`:
- Ubuntu/Debian: `sudo apt install bats`
- macOS: `brew install bats-core`
- npm: `npm install -g bats`
- From source: `git clone --depth=1 https://github.com/bats-core/bats-core /tmp/bats && (cd /tmp/bats && sudo ./install.sh /usr/local)`

After install: `bats --version` should print 1.x.

- [ ] **Step 2: Write `tests/test_helper.bash`**

```bash
#!/usr/bin/env bash
# Shared test helpers for bats files.

# Resolve repo root regardless of where the test is invoked from
REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
export REPO_ROOT
export SCRIPTS_DIR="$REPO_ROOT/scripts"

# Per-test scratch dir. Cleared by each test's setup().
make_tmp() {
  TEST_TMP="$(mktemp -d -p "$REPO_ROOT/tests/tmp" 2>/dev/null || mktemp -d)"
  export TEST_TMP
}

cleanup_tmp() {
  [ -n "${TEST_TMP:-}" ] && [ -d "$TEST_TMP" ] && rm -rf "$TEST_TMP"
}

# Stub copilot binary on PATH for tests that need to mock model probes.
# Writes a fake `copilot` to TEST_TMP/bin and prepends it to PATH.
# Usage: stub_copilot <bash-script-body>
stub_copilot() {
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/copilot" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "$TEST_TMP/bin/copilot"
  export PATH="$TEST_TMP/bin:$PATH"
}
```

- [ ] **Step 3: Sanity-check bats**

Create `tests/test_smoke.bats`:
```bash
#!/usr/bin/env bats

@test "bats can run a trivial test" {
  result="$(echo "hello")"
  [ "$result" = "hello" ]
}
```

Run:
```bash
bats tests/test_smoke.bats
```
Expected: `1 test, 0 failures`

- [ ] **Step 4: Delete the smoke test** (it was a one-time sanity check)

```bash
rm tests/test_smoke.bats
```

- [ ] **Step 5: Commit**

```bash
mkdir -p tests/tmp
touch tests/tmp/.gitkeep
git add tests/test_helper.bash tests/tmp/.gitkeep
git commit -m "test: scaffold bats-core harness with shared helpers"
```

### Task 1.4: `scripts/resolve-model.sh` — write the failing test first

**Files:**
- Test: `tests/test_resolve_model.bats`
- Create: `scripts/resolve-model.sh` (after test exists)

- [ ] **Step 1: Write failing tests in `tests/test_resolve_model.bats`**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  make_tmp
}

teardown() {
  cleanup_tmp
}

@test "no arg → exits with usage message" {
  run "$SCRIPTS_DIR/resolve-model.sh"
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage:"* ]]
}

@test "full model id passes through unchanged" {
  # Stub copilot so any model probe says "AVAILABLE"
  stub_copilot 'echo "ok"; exit 0'
  run "$SCRIPTS_DIR/resolve-model.sh" claude-sonnet-4.5
  [ "$status" -eq 0 ]
  [ "$output" = "claude-sonnet-4.5" ]
}

@test "alias 'sonnet' resolves to 4.7 when available" {
  stub_copilot '
    if [ "$3" = "claude-sonnet-4.7" ]; then echo ok; exit 0; fi
    echo "Error: Model \"$3\" from --model flag is not available."; exit 1
  '
  run "$SCRIPTS_DIR/resolve-model.sh" sonnet
  [ "$status" -eq 0 ]
  [ "$output" = "claude-sonnet-4.7" ]
}

@test "alias 'sonnet' falls back to 4.6 when 4.7 not available" {
  stub_copilot '
    case "$3" in
      claude-sonnet-4.7) echo "Error: not available"; exit 1;;
      claude-sonnet-4.6) echo ok; exit 0;;
    esac
  '
  run "$SCRIPTS_DIR/resolve-model.sh" sonnet
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-sonnet-4.6"* ]]
  [[ "$output" == *"4.7 not available"* ]]
}

@test "alias chain exhausts → exit 65 with clear error" {
  stub_copilot 'echo "Error: not available"; exit 1'
  run "$SCRIPTS_DIR/resolve-model.sh" sonnet
  [ "$status" -eq 65 ]
  [[ "$output" == *"None of"* ]]
  [[ "$output" == *"upgrade to Pro+"* ]] || [[ "$output" == *"copilot /model"* ]]
}

@test "alias 'auto' returns empty string (caller omits --model)" {
  run "$SCRIPTS_DIR/resolve-model.sh" auto
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unknown alias → exit 64 with usage hint" {
  run "$SCRIPTS_DIR/resolve-model.sh" doesnotexist
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown alias"* ]]
}
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
bats tests/test_resolve_model.bats
```
Expected: all 7 tests fail with `command not found: resolve-model.sh` or similar (the script doesn't exist yet).

- [ ] **Step 3: Implement `scripts/resolve-model.sh`**

```bash
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
        # Non-silent substitution per spec
        echo "Resolved --model $ALIAS → $candidate ($primary not available on your plan)"
      else
        echo "$candidate"
      fi
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
```

Make it executable:
```bash
chmod +x scripts/resolve-model.sh
```

- [ ] **Step 4: Run tests, verify they pass**

```bash
bats tests/test_resolve_model.bats
```
Expected: `7 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/resolve-model.sh tests/test_resolve_model.bats
git commit -m "feat(scripts): resolve-model.sh with alias + fallback chains

Per spec section 'Model resolution'. Probes copilot CLI for each
candidate in the fallback chain. Non-silent substitution: prints
'Resolved --model X → Y (X not available)' before yielding Y. Exits
65 when chain exhausts."
```

### Task 1.5: `scripts/capture-diff.sh`

**Files:**
- Test: `tests/test_capture_diff.bats`
- Create: `scripts/capture-diff.sh`

- [ ] **Step 1: Write failing tests in `tests/test_capture_diff.bats`**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  make_tmp
  cd "$TEST_TMP"
  git init -q -b main
  git config user.email "t@t.t"
  git config user.name "T"
  echo "hello" > a.txt
  git add a.txt
  git commit -q -m "init"
}

teardown() {
  cleanup_tmp
}

@test "default → captures staged + unstaged diff" {
  echo "world" >> a.txt           # unstaged change
  echo "new" > b.txt && git add b.txt  # staged change
  run "$SCRIPTS_DIR/capture-diff.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"world"* ]]
  [[ "$output" == *"new"* ]]
}

@test "default with no changes → exit 66 with 'no changes' message" {
  run "$SCRIPTS_DIR/capture-diff.sh"
  [ "$status" -eq 66 ]
  [[ "$output" == *"No changes to review"* ]]
}

@test "--staged → captures only staged changes" {
  echo "unstaged" >> a.txt
  echo "staged" > c.txt && git add c.txt
  run "$SCRIPTS_DIR/capture-diff.sh" --staged
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged"* ]]
  [[ "$output" != *"unstaged"* ]]
}

@test "--branch → diffs current branch vs main" {
  git checkout -q -b feature
  echo "feature-line" > f.txt && git add f.txt
  git commit -q -m "feature"
  run "$SCRIPTS_DIR/capture-diff.sh" --branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-line"* ]]
}

@test "<ref>..<ref> range → diffs that range" {
  echo "v2" > a.txt && git commit -q -am "v2"
  echo "v3" > a.txt && git commit -q -am "v3"
  run "$SCRIPTS_DIR/capture-diff.sh" HEAD~2..HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"v3"* ]]
}

@test "outside git repo → exit 67" {
  cd "$TEST_TMP/.." 2>/dev/null || cd /tmp
  rm -rf "$TEST_TMP/.git" 2>/dev/null || true
  mkdir -p "$TEST_TMP/notarepo"
  cd "$TEST_TMP/notarepo"
  run "$SCRIPTS_DIR/capture-diff.sh"
  [ "$status" -eq 67 ]
  [[ "$output" == *"not a git repository"* ]] || [[ "$output" == *"Not in a git repo"* ]]
}
```

- [ ] **Step 2: Run, verify all 6 fail**

```bash
bats tests/test_capture_diff.bats
```

- [ ] **Step 3: Implement `scripts/capture-diff.sh`**

```bash
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
```

```bash
chmod +x scripts/capture-diff.sh
```

- [ ] **Step 4: Run tests, verify pass**

```bash
bats tests/test_capture_diff.bats
```
Expected: `6 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/capture-diff.sh tests/test_capture_diff.bats
git commit -m "feat(scripts): capture-diff.sh for all five target forms

Default (staged+unstaged), --staged, --branch, <ref>..<ref>, and
pr <N>. Exits 66 on empty diff, 67 outside a git repo, 68 if pr
target needs gh and it's not installed."
```

### Task 1.6: `scripts/job-state.sh`

**Files:**
- Test: `tests/test_job_state.bats`
- Create: `scripts/job-state.sh`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  make_tmp
  export XDG_STATE_HOME="$TEST_TMP/state"
}

teardown() {
  cleanup_tmp
}

@test "list on empty store → prints header only" {
  run "$SCRIPTS_DIR/job-state.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"JOB ID"* ]] || [ -z "$output" ]
}

@test "append → row appears in list" {
  "$SCRIPTS_DIR/job-state.sh" append "job_abc123" "fix auth" "https://github.com/o/r/pull/1" "running"
  run "$SCRIPTS_DIR/job-state.sh" list
  [[ "$output" == *"job_abc123"* ]]
  [[ "$output" == *"fix auth"* ]]
  [[ "$output" == *"running"* ]]
}

@test "update changes status" {
  "$SCRIPTS_DIR/job-state.sh" append "job_xyz" "task" "https://x.com/pr/2" "running"
  "$SCRIPTS_DIR/job-state.sh" update "job_xyz" "completed"
  run "$SCRIPTS_DIR/job-state.sh" list
  [[ "$output" == *"completed"* ]]
  [[ "$output" != *"running"* ]]
}

@test "list --json emits valid JSON array" {
  "$SCRIPTS_DIR/job-state.sh" append "j1" "t1" "url1" "running"
  "$SCRIPTS_DIR/job-state.sh" append "j2" "t2" "url2" "completed"
  run "$SCRIPTS_DIR/job-state.sh" list --json
  [ "$status" -eq 0 ]
  # Must be parseable JSON array with 2 elements
  echo "$output" | jq -e 'length == 2'
}

@test "list (default) hides cancelled jobs; --all shows them" {
  "$SCRIPTS_DIR/job-state.sh" append "j1" "t" "url" "running"
  "$SCRIPTS_DIR/job-state.sh" append "j2" "t" "url" "cancelled"
  run "$SCRIPTS_DIR/job-state.sh" list
  [[ "$output" == *"j1"* ]]
  [[ "$output" != *"j2"* ]]

  run "$SCRIPTS_DIR/job-state.sh" list --all
  [[ "$output" == *"j1"* ]]
  [[ "$output" == *"j2"* ]]
}

@test "concurrent append doesn't corrupt the file" {
  for i in $(seq 1 20); do
    "$SCRIPTS_DIR/job-state.sh" append "job_$i" "t" "u" "running" &
  done
  wait
  run "$SCRIPTS_DIR/job-state.sh" list --json
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 20 ]
}
```

- [ ] **Step 2: Run, verify failure**

```bash
bats tests/test_job_state.bats
```

- [ ] **Step 3: Implement `scripts/job-state.sh`**

```bash
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
  exec 9>"$LOCK"
  flock 9
  "$@"
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
```

```bash
chmod +x scripts/job-state.sh
```

- [ ] **Step 4: Run tests, verify pass**

```bash
bats tests/test_job_state.bats
```
Expected: `6 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/job-state.sh tests/test_job_state.bats
git commit -m "feat(scripts): job-state.sh for cloud-job TSV management

Append/list/update primitives with flock-based concurrent-write
safety. Honors XDG_STATE_HOME. list --json for shell consumers,
list --all to include cancelled/failed jobs."
```

### Task 1.7: README skeleton + CI

**Files:**
- Create: `README.md` (skeleton, expanded in chunk 4)
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Write `README.md` skeleton**

```markdown
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
```

- [ ] **Step 2: Write CI workflow `.github/workflows/test.yml`**

```yaml
name: tests
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats jq
      - name: Run tests
        run: bats tests/
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: shellcheck
        run: |
          sudo apt-get update && sudo apt-get install -y shellcheck
          shellcheck scripts/*.sh tests/test_helper.bash
```

- [ ] **Step 3: Run shellcheck locally before committing**

```bash
sudo apt install -y shellcheck 2>/dev/null || true
shellcheck scripts/*.sh tests/test_helper.bash
```
Expected: no errors. Fix any flagged issues before continuing.

- [ ] **Step 4: Commit**

```bash
mkdir -p .github/workflows
git add README.md .github/workflows/test.yml
git commit -m "docs: README skeleton + CI workflow (bats + shellcheck)"
```

**Chunk 1 done.** State at end:
- Repo has manifest, license, ignore, README skeleton, CI
- Three shell scripts implemented and tested (19 tests, all passing)
- No commands yet — that's chunk 2

---

## Chunk 2: Review commands (1–3)

### Task 2.1: Ship the adversarial agent profile

**Files:**
- Create: `agents/adversarial-review.agent.md`

- [ ] **Step 1: Write the agent profile**

```markdown
---
name: adversarial-review
description: Harsh adversarial code review. Assume the diff is wrong until proven right. Use when a normal "code-review" pass feels too gentle — for security-sensitive changes, suspected over-abstraction, or any review where you want every assumption challenged.
tools: read
---

# Adversarial review agent

You are an adversarial reviewer. Your job is not to be nice. Your job is to find what is wrong with this code.

## Your charter

1. **Assume the code is wrong until proven right.** Every "looks good" requires specific evidence. Refuse to give a positive verdict without naming why.

2. **Hunt for security holes.** Injection paths (SQL, shell, HTML, log), authentication and authorization gaps, secret material in logs or error messages, missing input validation at trust boundaries, hardcoded credentials, insecure defaults.

3. **Hunt for correctness bugs.** Off-by-one errors, race conditions, unhandled error paths, missing null/undefined checks, integer overflow, time-of-check-to-time-of-use, retry/timeout/cancellation interactions, sort/equality assumptions, encoding/decoding mismatches.

4. **Flag over-abstraction.** New base classes with one subclass, new interfaces with one implementer, premature dependency injection, abstract factories for two-element configuration. Demand the concrete case that justifies each new abstraction.

5. **Demand justification for every new dependency.** For each `import`, `require`, `use`, or `dependencies` entry the diff adds: why this library, why this version, what was wrong with the standard library or existing in-tree code, what is the security and maintenance posture of the package.

6. **Flag dead code.** Functions added but never called. Branches that can never trigger. Parameters that are passed but unused. Comments that have rotted away from the code they describe.

## How to respond

Structure your review as:

1. **Verdict** — one of: `REJECT`, `REQUEST CHANGES`, `APPROVE WITH CONCERNS`. Never just `APPROVE`. If you cannot find anything wrong, say `APPROVE WITH CONCERNS: I could not find issues but recommend a second pass focused on [specific area].`

2. **Critical issues** — bugs that will cause production incidents. Each one: file:line reference, what is wrong, smallest reproduction, suggested fix.

3. **Design concerns** — things that aren't bugs but signal worse problems ahead. Over-abstraction, leaky abstractions, modules that change together but live apart, modules that don't change together but live together.

4. **Minor** — style, naming, comments. One short line each. Cap at 5.

## What you don't do

- You do not soften feedback to seem polite.
- You do not say "consider" when you mean "this is wrong."
- You do not pad with restatements of what the code does.
- You do not give kudos. The reviewer's job is to find problems.
```

- [ ] **Step 2: Commit**

```bash
git add agents/adversarial-review.agent.md
git commit -m "feat(agents): ship adversarial-review.agent.md profile

Charter: assume wrong until proven right; security + correctness +
over-abstraction + dependency hunt. Verdict labels REJECT /
REQUEST CHANGES / APPROVE WITH CONCERNS — never bare APPROVE."
```

### Task 2.2: `/copilot:review` command

**Files:**
- Create: `commands/review.md`

- [ ] **Step 1: Write `commands/review.md`**

```markdown
---
description: Review uncommitted changes (or a specified target) with GitHub Copilot CLI's built-in code-review agent. Use --model to override the reviewer LLM.
allowed-tools: Bash, Read
---

# /copilot:review

Run a Copilot code review on a diff target.

## Arguments

`$ARGUMENTS` — optional target plus optional `--model <alias-or-id>`. Examples:
- `` (empty) — review staged + unstaged working dir
- `HEAD~5..HEAD`
- `pr 123`
- `--staged`
- `--branch`
- `--model sonnet`
- `--branch --model codex`

## Behavior

1. Parse `$ARGUMENTS`. Separate target args (everything that isn't `--model X`) from the model alias.
2. Determine the plugin install directory. The scripts live at `${CLAUDE_PLUGIN_ROOT}/scripts/`.
3. Capture the diff:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/capture-diff.sh" <target-args> > /tmp/copilot-review-$$.diff
   ```
   If the script exits with 66 (no changes), tell the user "No changes to review. Stage some changes or pass a target." and stop.
4. Resolve the model. If `--model X` was passed, run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh" X
   ```
   If the script exits 65 (chain exhausted), surface its stderr to the user and stop.
   If no `--model` was passed, default to `codex` (per spec: gpt-5.2-codex is GitHub's documented best-for-review).
5. Build the copilot invocation:
   ```bash
   if [ -n "$RESOLVED_MODEL" ]; then
     copilot -p --silent --agent=code-review --model "$RESOLVED_MODEL" < /tmp/copilot-review-$$.diff
   else
     copilot -p --silent --agent=code-review < /tmp/copilot-review-$$.diff
   fi
   ```
6. Stream the markdown response back into the transcript. Render it as-is — do not summarize.
7. Clean up `/tmp/copilot-review-$$.diff`.

## Error handling

- If `copilot` is not on PATH: tell the user to run `/copilot:setup` first.
- If `copilot` returns an auth error: tell the user to run `copilot login`.
- If `resolve-model.sh` exits 65: print its stderr verbatim and stop.
- If `capture-diff.sh` exits 67 (not a git repo): tell the user to `cd` into a git repo first.
- If the diff is enormous (>500KB): warn the user before sending and offer to narrow the target.
```

- [ ] **Step 2: Smoke-test manually** (no bats — these are Claude Code prompts)

Document the smoke-test procedure in `tests/manual_smoke.md`:

```markdown
# Manual smoke tests for command .md files

## /copilot:review

1. `cd ~/Downloads/copilot-plugin-cc` (or any git repo with uncommitted changes)
2. Make a trivial edit so there's a diff
3. In Claude Code: `/copilot:review`
4. Expected: a markdown code review streams back
5. Then: `/copilot:review --model codex` — should explicitly resolve to gpt-5.2-codex
6. Then in a repo with NO diff: `/copilot:review` — should say "No changes to review"
```

- [ ] **Step 3: Commit**

```bash
mkdir -p tests/manual
mv tests/manual_smoke.md tests/manual/smoke.md 2>/dev/null || \
  mv tests/manual_smoke.md tests/manual/ 2>/dev/null || \
  cp /dev/null tests/manual/.gitkeep
git add commands/review.md tests/manual/
git commit -m "feat(commands): /copilot:review — standard code-review

Wraps copilot --agent=code-review on diff target. Default model is
codex (gpt-5.2-codex fallback chain). All target forms supported via
capture-diff.sh."
```

### Task 2.3: `/copilot:adversarial-review` command

**Files:**
- Create: `commands/adversarial-review.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Harsh adversarial code review. Assumes the diff is wrong until proven right. Uses a shipped custom agent profile.
allowed-tools: Bash, Read
---

# /copilot:adversarial-review

Same input grammar as `/copilot:review`, but uses the adversarial agent profile.

## Behavior

1. Parse `$ARGUMENTS` exactly like `/copilot:review`.
2. **Install the custom agent on first run.** Check whether `~/.copilot/agents/adversarial-review.agent.md` exists. If not, copy it from `${CLAUDE_PLUGIN_ROOT}/agents/adversarial-review.agent.md`:
   ```bash
   mkdir -p ~/.copilot/agents
   if [ ! -f ~/.copilot/agents/adversarial-review.agent.md ]; then
     cp "${CLAUDE_PLUGIN_ROOT}/agents/adversarial-review.agent.md" ~/.copilot/agents/
     echo "Installed adversarial-review.agent.md to ~/.copilot/agents/"
   fi
   ```
   Never overwrite an existing file — the user may have edited it.
3. Capture diff via `capture-diff.sh` (same as /copilot:review).
4. Resolve model (same default: codex).
5. Invoke `copilot --agent=adversarial-review --model "$RESOLVED" -p --silent < diff`.
6. Stream output back.

## Why this exists

The built-in `code-review` agent is calibrated to be helpful. Sometimes you want a reviewer that defaults to suspicious. That's this command.

## Tuning

After first run, you can edit `~/.copilot/agents/adversarial-review.agent.md` to adjust:
- Severity gradient (make REJECT cheaper or harder)
- Focus axis (security-only, perf-only, etc.)
- Length budget for the response

The plugin will not overwrite your edits on subsequent runs.
```

- [ ] **Step 2: Add to smoke tests**

Append to `tests/manual/smoke.md`:

```markdown
## /copilot:adversarial-review

1. First-run check: `rm -f ~/.copilot/agents/adversarial-review.agent.md`
2. `/copilot:adversarial-review` in a repo with diff
3. Expected output: "Installed adversarial-review.agent.md to ~/.copilot/agents/" followed by a harsh review
4. Verify the file exists: `ls ~/.copilot/agents/adversarial-review.agent.md`
5. Edit the file (add "extra harsh" to the charter), run again, verify the edit is honored (it was not overwritten)
```

- [ ] **Step 3: Commit**

```bash
git add commands/adversarial-review.md tests/manual/smoke.md
git commit -m "feat(commands): /copilot:adversarial-review with first-run agent install

Copies agents/adversarial-review.agent.md to ~/.copilot/agents/ on
first invocation. Never overwrites existing files (user edits
persist). Same target grammar and --model flag as /copilot:review."
```

### Task 2.4: `/copilot:rubber-duck` command

**Files:**
- Create: `commands/rubber-duck.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Cross-model critique. Uses Copilot's built-in rubber-duck agent which deliberately picks a complementary model from your main session for blind-spot detection.
allowed-tools: Bash, Read
---

# /copilot:rubber-duck

Run Copilot's rubber-duck agent on a diff. The rubber-duck agent is designed to pick a *complementary* model — meaning if your main Claude Code session is on an Anthropic model, the rubber-duck will pick an OpenAI or Google model (when available on your plan) to surface cross-vendor blind spots.

## Arguments

`$ARGUMENTS` — same grammar as /copilot:review.

## Behavior

1. Parse `$ARGUMENTS`.
2. Capture diff via `capture-diff.sh`.
3. Model resolution: if user passed `--model`, resolve via `resolve-model.sh`. Otherwise omit `--model` and let the rubber-duck agent pick its complementary model.
4. Invoke:
   ```bash
   if [ -n "$RESOLVED_MODEL" ]; then
     copilot -p --silent --agent=rubber-duck --model "$RESOLVED_MODEL" < diff
   else
     copilot -p --silent --agent=rubber-duck < diff
   fi
   ```
5. Stream output.

## When to use

After running `/copilot:review` or `/copilot:adversarial-review`, run `/copilot:rubber-duck` to get a second opinion from a different model family. If both reviewers flag the same issue, it's almost certainly real. If only one does, it's worth investigating which is right.

## Plan notes

On the author's Pro plan with limited model coverage, rubber-duck still works but the "complementary model" pool is small. Pro+ users get the full benefit because the model pool spans Anthropic, OpenAI, and (when enabled) Google.
```

- [ ] **Step 2: Add to smoke tests** — append to `tests/manual/smoke.md`:

```markdown
## /copilot:rubber-duck

1. In any repo with a diff: `/copilot:rubber-duck`
2. Expected: a critique back from the rubber-duck agent
3. Compare to `/copilot:review` output on the same diff — note differences in tone and findings
```

- [ ] **Step 3: Commit**

```bash
git add commands/rubber-duck.md tests/manual/smoke.md
git commit -m "feat(commands): /copilot:rubber-duck for cross-model critique

Wraps copilot --agent=rubber-duck. Leaves --model unset by default
so the agent picks a complementary model from a different vendor."
```

**Chunk 2 done.** State at end:
- Three review commands implemented
- Adversarial agent profile shipped
- Manual smoke test checklist documented
- Still 19 bats tests passing (no new shell scripts in this chunk)

---

## Chunk 3: Autonomous + job management (commands 4–7)

### Task 3.1: Verify the actual cloud-agent verbs

**Manual research step — no commit.**

- [ ] **Step 1: Discover the real subcommand verbs**

```bash
copilot --help 2>&1 | grep -iE "delegate|job|cloud|background" | head -20
copilot delegate --help 2>&1 | head -40
copilot job --help 2>&1 | head -40 || true
```

Record the actual verbs in `tests/manual/cloud-agent-research.md`. The spec uses `copilot job <verb>` as a placeholder — pin to whatever the live CLI actually exposes for `status`, `result`, and `cancel`. The most likely shapes per the public docs are:
- `&<prompt>` or `copilot -p "&<prompt>"` — delegate via prefix
- `copilot /delegate <prompt>` — explicit slash form
- Status: probably exposed via the GitHub web at `claude.ai/code/sessions` or `github.com/copilot/agents` rather than a CLI subcommand

**Important:** if Copilot CLI does NOT expose CLI subcommands for status/result/cancel, this chunk's design changes: commands 5–7 will need to call the GitHub REST API directly via `gh api`. Document the discovered shape before continuing.

### Task 3.2: `/copilot:rescue` command

**Files:**
- Create: `commands/rescue.md`

- [ ] **Step 1: Write the command** (assuming `copilot -p "&<prompt>"` is the canonical form per task 3.1)

```markdown
---
description: Delegate a task to GitHub Copilot's cloud agent. Cloud agent creates a branch, opens a draft PR, and works in the background while you continue locally. Requires Copilot Pro+ or higher.
allowed-tools: Bash, Read
---

# /copilot:rescue

Push a task to Copilot's cloud agent.

## Arguments

`$ARGUMENTS` — required free-form prompt describing the task. Optional `--base <branch>` and `--repo <owner/repo>`. Examples:
- `/copilot:rescue add unit tests for src/parser.ts`
- `/copilot:rescue --base develop refactor the auth flow to use JWT`
- `/copilot:rescue --repo behroozazarkhalili/foo fix the failing CI on main`

## Behavior

1. Parse `$ARGUMENTS`. Separate the prompt from `--base` and `--repo` flags.
2. Verify cloud-agent entitlement. Run `copilot -p "&test"` as a dry-run with a known short prompt; if it errors with "cloud agent not available" or similar, surface "Cloud-agent delegation requires Copilot Pro+. You appear to be on a plan without cloud-agent access. Upgrade at https://github.com/settings/copilot." and stop.
3. Construct the delegation invocation:
   ```bash
   copilot -p "&${PROMPT}" --silent 2>&1
   ```
   (With `--base` and `--repo` translated to whatever the live CLI's flag shape requires — verified in task 3.1.)
4. Capture the response. The expected shape includes a job session ID and a PR URL. Parse both with regex:
   ```bash
   JOB_ID=$(echo "$RESPONSE" | grep -oE 'session_[a-zA-Z0-9]+' | head -1)
   PR_URL=$(echo "$RESPONSE" | grep -oE 'https://github.com/[^ ]+/pull/[0-9]+' | head -1)
   ```
5. Append to state store:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" append \
     "$JOB_ID" "${PROMPT:0:80}" "$PR_URL" "running"
   ```
6. Print to the user:
   ```
   Job dispatched: $JOB_ID
   Draft PR:       $PR_URL
   Track with:     /copilot:status
   Cancel with:    /copilot:cancel $JOB_ID
   ```

## Error handling

- Not authenticated: "Run `copilot login` first."
- Plan doesn't include cloud agent: see step 2 above.
- Repo permission error (bazarkhalili lacks write on a behroozazarkhalili repo): "Cloud agent needs write access to <repo>. Either add the authenticated user as a collaborator, or use /copilot:review instead which only needs read access."
- Network/transport error: print the raw error and exit.
```

- [ ] **Step 2: Add to smoke tests**

```markdown
## /copilot:rescue (Pro+ required)

1. In a repo you have write access to: `/copilot:rescue add a comment explaining the main function`
2. Expected: job_id printed, draft PR URL printed
3. Verify the PR appears at the URL
4. Verify the row exists: `cat ~/.local/state/copilot-plugin-cc/jobs.tsv`
```

- [ ] **Step 3: Commit**

```bash
git add commands/rescue.md tests/manual/smoke.md
git commit -m "feat(commands): /copilot:rescue for cloud-agent delegation

Wraps copilot -p '&<prompt>'. Parses job_id and PR URL from response,
appends to ~/.local/state/copilot-plugin-cc/jobs.tsv. Surfaces clear
errors for cloud-agent-unavailable plans and repo permission issues."
```

### Task 3.3: `/copilot:status` command

**Files:**
- Create: `commands/status.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: List active and recent Copilot cloud-agent jobs. Reads local state, optionally refreshes each job's status against GitHub.
allowed-tools: Bash, Read
---

# /copilot:status

List Copilot cloud-agent jobs the user has dispatched via `/copilot:rescue`.

## Arguments

`$ARGUMENTS` — optional flags:
- `--all` — include cancelled and failed jobs (default: hide)
- `--json` — machine-readable output

## Behavior

1. Call `${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh list $ARGUMENTS` to read the local state.
2. For each running job (status=`running`), refresh the live status by querying Copilot. The verb is one of:
   - `copilot job status <id>` if available (verified in task 3.1)
   - Or fall back to `gh api` against the GitHub Copilot endpoints
3. If a job's live status differs from the cached status, call:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" update <id> <new-status>
   ```
4. Re-render the list with refreshed statuses.

## Output (default text mode)

```
JOB ID       CREATED              STATUS     PR
session_abc  2026-05-13T11:00:00Z running    https://github.com/o/r/pull/42
session_def  2026-05-13T10:30:00Z completed  https://github.com/o/r/pull/41
```

## Output (--json)

```json
[
  {"job_id":"session_abc","created_at":"2026-05-13T11:00:00Z","prompt":"add tests","pr_url":"...","status":"running"},
  ...
]
```

## Error handling

- No jobs tracked yet: print "No jobs dispatched yet. Run /copilot:rescue to delegate a task."
- Live refresh fails (network/auth): print cached statuses with a footer "Note: could not refresh live statuses — showing cached values from <last update>."
```

- [ ] **Step 2: Commit**

```bash
git add commands/status.md
git commit -m "feat(commands): /copilot:status — list cloud-agent jobs

Reads local TSV via job-state.sh, refreshes running-job statuses
against the live Copilot API, updates the cache, re-renders.
Supports --all (include cancelled/failed) and --json."
```

### Task 3.4: `/copilot:result` and `/copilot:cancel`

**Files:**
- Create: `commands/result.md`
- Create: `commands/cancel.md`

- [ ] **Step 1: Write `commands/result.md`**

```markdown
---
description: Fetch the output of a finished Copilot cloud-agent job.
allowed-tools: Bash, Read
---

# /copilot:result

Fetch and render the result of a finished cloud-agent job.

## Arguments

`$ARGUMENTS` — required job ID or unique prefix. Examples:
- `/copilot:result session_abc123`
- `/copilot:result abc` — if only one job's ID starts with "abc"

## Behavior

1. Parse the ID from $ARGUMENTS.
2. Resolve prefix to a full ID via:
   ```bash
   matches=$("${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" list --json | jq -r --arg p "$PREFIX" '.[] | select(.job_id | startswith($p)) | .job_id')
   ```
   - 0 matches → "No job matches prefix '$PREFIX'. Run /copilot:status to see tracked jobs."
   - >1 matches → "Multiple jobs match '$PREFIX': ... Disambiguate with a longer prefix."
   - 1 match → continue.
3. Verify the job is finished (status in {completed, cancelled, failed}). If status is `running`, tell the user to wait or use `/copilot:status` to refresh.
4. Fetch the result via Copilot's API (`copilot job result <id>` or `gh api` equivalent — pinned in task 3.1).
5. Render the result as markdown.

## Error handling

- ID not found: see step 2.
- Job still running: see step 3.
- Auth or network error: surface clearly.
```

- [ ] **Step 2: Write `commands/cancel.md`**

```markdown
---
description: Cancel an in-progress Copilot cloud-agent job.
allowed-tools: Bash, Read
---

# /copilot:cancel

Cancel an active cloud-agent job.

## Arguments

`$ARGUMENTS` — required job ID or unique prefix.

## Behavior

1. Parse and resolve the prefix exactly like /copilot:result.
2. Verify the job is currently `running`. If status is already terminal (completed, cancelled, failed), error: "Job $ID is already $STATUS — cannot cancel."
3. Send the cancellation:
   ```bash
   copilot job cancel "$JOB_ID"   # or gh api equivalent
   ```
4. Update the TSV:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/job-state.sh" update "$JOB_ID" cancelled
   ```
5. Print confirmation: "Cancelled $JOB_ID."

## Error handling

- Not running anymore: see step 2.
- Already cancelled: same.
- Network error: surface, do NOT update TSV (preserves accurate state).
```

- [ ] **Step 3: Add both to smoke tests**

```markdown
## /copilot:result + /copilot:cancel

1. Dispatch with /copilot:rescue (see earlier task)
2. Run /copilot:status — note the job_id
3. Run /copilot:result <full-id> — if still running, expect "wait" message
4. Run /copilot:result <prefix> — should resolve uniquely
5. To test cancel: dispatch a long task, then /copilot:cancel <id>
6. Verify TSV updates: cat ~/.local/state/copilot-plugin-cc/jobs.tsv
```

- [ ] **Step 4: Commit**

```bash
git add commands/result.md commands/cancel.md tests/manual/smoke.md
git commit -m "feat(commands): /copilot:result and /copilot:cancel

Prefix-based ID resolution via job-state.sh list --json | jq. Result
fetches and renders cloud-agent output. Cancel updates TSV only on
successful cancellation."
```

**Chunk 3 done.** State at end:
- Four cloud-agent commands shipped
- Manual smoke checklist now covers 7 commands
- Still 19 bats tests, all green

---

## Chunk 4: Setup command, README, release

### Task 4.1: `/copilot:setup` command

**Files:**
- Create: `commands/setup.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Verify Copilot CLI install + authentication + agent file installation. Idempotent — safe to run repeatedly.
allowed-tools: Bash, Read
---

# /copilot:setup

Verify the local environment is ready for the plugin and print a checklist.

## Behavior

Run each check, recording success/failure. Print a final summary.

```bash
echo "Checking copilot-plugin-cc environment..."
echo ""

# 1. copilot binary
if command -v copilot >/dev/null 2>&1; then
  V=$(copilot --version 2>&1 | head -1)
  echo "✓ copilot binary: $V"
else
  echo "✗ copilot binary: NOT FOUND"
  echo "    Install: npm install -g @github/copilot"
  exit 1
fi

# 2. Authentication
if copilot -p "ok" --silent 2>&1 | grep -qi "not authenticated\|Run.*login"; then
  echo "✗ authentication: NOT AUTHENTICATED"
  echo "    Run: copilot login"
  exit 1
else
  echo "✓ authenticated"
fi

# 3. Adversarial agent installed
if [ -f ~/.copilot/agents/adversarial-review.agent.md ]; then
  echo "✓ adversarial-review agent installed"
else
  mkdir -p ~/.copilot/agents
  cp "${CLAUDE_PLUGIN_ROOT}/agents/adversarial-review.agent.md" ~/.copilot/agents/
  echo "✓ adversarial-review agent installed (just now)"
fi

# 4. Probe available models for each alias
echo ""
echo "Available models per alias:"
for alias in sonnet opus haiku codex gpt gpt-mini gpt-4 gemini; do
  resolved=$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh" "$alias" 2>&1 || echo "UNAVAILABLE")
  printf "  %-10s → %s\n" "$alias" "$resolved"
done

# 5. State store
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/copilot-plugin-cc"
if [ -d "$STATE_HOME" ]; then
  njobs=$(wc -l < "$STATE_HOME/jobs.tsv" 2>/dev/null || echo 0)
  echo ""
  echo "✓ state store: $STATE_HOME ($njobs jobs tracked)"
else
  echo ""
  echo "✓ state store will be created on first /copilot:rescue"
fi

# 6. gh CLI (optional)
echo ""
if command -v gh >/dev/null 2>&1; then
  ghuser=$(gh api user --jq .login 2>/dev/null || echo "not-authed")
  echo "✓ gh CLI present (user: $ghuser) — pr <N> target available"
else
  echo "⚠ gh CLI not installed — pr <N> target unavailable. Install: https://cli.github.com/"
fi

echo ""
echo "All required checks passed. Try /copilot:review to start."
```

## Notes

`/copilot:setup` is idempotent. Other commands DO NOT depend on it having been run; they handle their own preconditions inline. This command exists for the user to see the system state, not for the plugin's own gating.
```

- [ ] **Step 2: Commit**

```bash
git add commands/setup.md
git commit -m "feat(commands): /copilot:setup verification checklist

Idempotent. Checks binary, auth, agent file, per-alias model
availability, state store, and gh CLI. Auto-installs the
adversarial agent file if missing."
```

### Task 4.2: Expand README

**Files:**
- Modify: `README.md` (full rewrite)

- [ ] **Step 1: Replace `README.md` with the full version**

```markdown
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

Full design in `docs/superpowers/specs/2026-05-13-copilot-plugin-cc-design.md`. Implementation plan in `docs/superpowers/plans/`.

## License

Apache-2.0. See `LICENSE`.

## Acknowledgments

Modeled on `openai/codex-plugin-cc`. The structure (review + adversarial + rescue + status + result + cancel + setup) is intentionally parallel so users familiar with one can use the other. `/copilot:rubber-duck` has no codex analog and is the strongest reason to choose this plugin over codex-plugin-cc for review work.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: full README with quick start, alias table, multi-account notes"
```

### Task 4.3: Final test pass + shellcheck

- [ ] **Step 1: Run all bats tests**

```bash
cd ~/Downloads/copilot-plugin-cc
bats tests/
```
Expected: `19 tests, 0 failures` (7 resolve_model + 6 capture_diff + 6 job_state)

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck scripts/*.sh tests/test_helper.bash
```
Expected: clean exit. Fix any warnings.

- [ ] **Step 3: Validate plugin.json**

```bash
jq . .claude-plugin/plugin.json > /dev/null && echo OK
```

- [ ] **Step 4: List all command files exist**

```bash
for c in review adversarial-review rubber-duck rescue status result cancel setup; do
  test -f "commands/$c.md" && echo "✓ $c.md" || echo "✗ MISSING $c.md"
done
```
Expected: 8 checkmarks.

### Task 4.4: Install plugin locally and smoke-test in Claude Code

- [ ] **Step 1: Add the local plugin to Claude Code**

In your Claude Code prompt:
```
/plugin marketplace add /home/ermia/Downloads/copilot-plugin-cc
/plugin install copilot
/reload-plugins
```

- [ ] **Step 2: Run /copilot:setup**

Expected: green checklist with all 4–6 items checked, model alias probe shows your Pro+ coverage.

- [ ] **Step 3: Run /copilot:review on a real diff**

In a repo with uncommitted changes, run `/copilot:review`. Expected: a markdown code review streams back.

- [ ] **Step 4: Run /copilot:adversarial-review on the same diff**

Compare tone. Expected: more critical, structured with REJECT / REQUEST CHANGES / APPROVE WITH CONCERNS verdict.

- [ ] **Step 5: Run /copilot:rubber-duck**

Expected: a third review from a different model (if Pro+).

- [ ] **Step 6: If on Pro+, smoke /copilot:rescue**

```
/copilot:rescue add a comment to the main function explaining its purpose
```
Expected: job_id + PR URL. Then `/copilot:status` should list the job.

- [ ] **Step 7: Fix anything that broke**

Common gotchas to expect:
- `CLAUDE_PLUGIN_ROOT` not set as expected → wrap paths in `${CLAUDE_PLUGIN_ROOT:-$HOME/Downloads/copilot-plugin-cc}` as fallback
- copilot CLI verb mismatches → adjust per task 3.1 findings
- Argument parsing edge cases → add tests for the specific failing case, then fix

### Task 4.5: Publish private repo and tag v0.1.0

- [ ] **Step 1: Create the private repo**

```bash
cd ~/Downloads/copilot-plugin-cc
gh repo create behroozazarkhalili/copilot-plugin-cc --private --source=. --remote=origin --push
```

- [ ] **Step 2: Tag and push the release**

```bash
git tag -a v0.1.0 -m "v0.1.0 — initial release

Eight slash commands wrapping GitHub Copilot CLI for code review
and cloud-agent delegation inside Claude Code. Pro and Pro+ aware
model alias resolver with graceful fallback chains."
git push origin v0.1.0
```

- [ ] **Step 3: Confirm**

```bash
gh repo view behroozazarkhalili/copilot-plugin-cc --json visibility,defaultBranchRef,url
gh release list -R behroozazarkhalili/copilot-plugin-cc
```

Expected:
- visibility: PRIVATE
- url: https://github.com/behroozazarkhalili/copilot-plugin-cc
- Tag v0.1.0 listed

### Task 4.6: Update spec with implementation findings

If anything in the implementation diverged from the spec (e.g. real cloud-agent verb shape from task 3.1), update the spec:

- [ ] **Step 1: Edit `docs/superpowers/specs/2026-05-13-copilot-plugin-cc-design.md`** as needed

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/
git commit -m "docs(spec): reconcile spec with implementation findings"
git push
```

**Chunk 4 done. Release shipped.**

---

## Definition of Done

- [ ] `bats tests/` → 19 tests, 0 failures
- [ ] `shellcheck scripts/*.sh tests/test_helper.bash` → clean
- [ ] `jq . .claude-plugin/plugin.json` → valid
- [ ] All 8 command files exist under `commands/`
- [ ] `agents/adversarial-review.agent.md` exists
- [ ] README.md covers requirements, quickstart, aliases, multi-account, license
- [ ] Repo pushed to `behroozazarkhalili/copilot-plugin-cc` (private)
- [ ] Tag `v0.1.0` exists
- [ ] All 8 commands manually smoke-tested per `tests/manual/smoke.md`
- [ ] At least one real diff reviewed with each of /copilot:review, /copilot:adversarial-review, /copilot:rubber-duck
- [ ] If Pro+ available: at least one /copilot:rescue dispatch + status check completed

## Out-of-band followups (not part of v0.1)

These were explicitly de-scoped in the spec and remain so for v0.1:

- Stop hook for auto-review-on-write
- PostToolUse hook for opportunistic critique
- MCP server integration
- Subagent equivalents
- Marketplace publication (public)
- `--output <file>` flag
- Configurable adversarial-agent prompt via plugin settings
- Statusline integration showing active /copilot:rescue jobs

Track these in GitHub issues after v0.1 is shipped.
