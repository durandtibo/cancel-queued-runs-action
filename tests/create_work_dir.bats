#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR/tmp"
  export TMPDIR="$MOCK_DIR/tmp"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "create_work_dir sets WORK_DIR to an existing directory" {
  create_work_dir

  [ -n "$WORK_DIR" ]
  [ -d "$WORK_DIR" ]
}

@test "create_work_dir creates the directory in TMPDIR" {
  create_work_dir

  [ "$(dirname "$WORK_DIR")" = "$TMPDIR" ]
}

@test "create_work_dir creates an empty directory" {
  create_work_dir

  [ -z "$(ls -A "$WORK_DIR")" ]
}

@test "create_work_dir creates a directory that only the user can use" {
  create_work_dir

  # ls -ld prints drwx------ for the mode 700
  [[ "$(ls -ld "$WORK_DIR")" == drwx------* ]] || false
}

@test "create_work_dir creates a new directory at every call" {
  create_work_dir
  first="$WORK_DIR"
  create_work_dir

  [ "$first" != "$WORK_DIR" ]
}

@test "create_work_dir uses /tmp when TMPDIR is not set" {
  unset TMPDIR

  create_work_dir

  [ "$(dirname "$WORK_DIR")" = "/tmp" ]
  rm -rf "$WORK_DIR"
}

@test "create_work_dir fails when the directory cannot be created" {
  export TMPDIR="$MOCK_DIR/does-not-exist"

  run create_work_dir

  [ "$status" -ne 0 ]
}

@test "create_work_dir leaves WORK_DIR empty when the directory cannot be created" {
  export TMPDIR="$MOCK_DIR/does-not-exist"

  create_work_dir 2> /dev/null || true

  [ -z "$WORK_DIR" ]
}
