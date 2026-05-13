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
