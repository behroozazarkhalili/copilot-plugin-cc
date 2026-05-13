#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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
  OUTSIDE_REPO="$(mktemp -d -p /tmp)"
  run bash -c "cd '$OUTSIDE_REPO' && '$SCRIPTS_DIR/capture-diff.sh'"
  rm -rf "$OUTSIDE_REPO"
  [ "$status" -eq 67 ]
  [[ "$output" == *"Not in a git repository"* ]] || [[ "$output" == *"not a git repository"* ]]
}
