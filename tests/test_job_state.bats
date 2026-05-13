#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  make_tmp
  export XDG_STATE_HOME="$TEST_TMP/state"
}

teardown() {
  cleanup_tmp
}

@test "list on empty store → prints header only or empty" {
  run "$SCRIPTS_DIR/job-state.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"JOB ID"* ]] || [ -z "$output" ]
}

@test "append → row appears in list" {
  "$SCRIPTS_DIR/job-state.sh" append "job_abc123" "fix auth" "https://github.com/o/r/pull/1" "running"
  run "$SCRIPTS_DIR/job-state.sh" list
  [[ "$output" == *"job_abc123"* ]]
  [[ "$output" == *"fix auth"* ]] || [[ "$output" == *"running"* ]]
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
