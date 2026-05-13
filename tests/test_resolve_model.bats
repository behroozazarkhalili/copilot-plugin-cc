#!/usr/bin/env bats

load test_helper

setup() {
  make_tmp
}

teardown() {
  cleanup_tmp
}

# Helper for stubs: grab the value following --model in argv.
# Stubs use: MODEL=$(get_model "$@") then case on $MODEL.
GET_MODEL_HELPER='
get_model() {
  while [ $# -gt 0 ]; do
    if [ "$1" = "--model" ]; then echo "$2"; return; fi
    shift
  done
}
'

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
  stub_copilot "$GET_MODEL_HELPER"'
    MODEL=$(get_model "$@")
    if [ "$MODEL" = "claude-sonnet-4.7" ]; then echo ok; exit 0; fi
    echo "Error: Model \"$MODEL\" from --model flag is not available."; exit 1
  '
  run "$SCRIPTS_DIR/resolve-model.sh" sonnet
  [ "$status" -eq 0 ]
  [ "$output" = "claude-sonnet-4.7" ]
}

@test "alias 'sonnet' falls back to 4.6 when 4.7 not available" {
  stub_copilot "$GET_MODEL_HELPER"'
    MODEL=$(get_model "$@")
    case "$MODEL" in
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
