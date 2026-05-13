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
