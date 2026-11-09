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

@test "cleanup_work_dir removes the directory" {
  create_work_dir
  dir="$WORK_DIR"

  cleanup_work_dir

  [ ! -e "$dir" ]
}

@test "cleanup_work_dir removes the files of the directory" {
  create_work_dir
  : > "$WORK_DIR/a"
  : > "$WORK_DIR/.hidden"
  mkdir "$WORK_DIR/sub"
  : > "$WORK_DIR/sub/b"

  cleanup_work_dir

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "cleanup_work_dir resets WORK_DIR" {
  create_work_dir

  cleanup_work_dir

  [ -z "$WORK_DIR" ]
}

@test "cleanup_work_dir does nothing when WORK_DIR is empty" {
  WORK_DIR=""
  : > "$TMPDIR/other"

  run cleanup_work_dir

  [ "$status" -eq 0 ]
  [ -e "$TMPDIR/other" ]
}

@test "cleanup_work_dir does not touch the current directory when WORK_DIR is empty" {
  WORK_DIR=""
  cd "$TMPDIR"
  : > keep

  cleanup_work_dir

  [ -e "$TMPDIR/keep" ]
}

@test "cleanup_work_dir succeeds when the directory is already gone" {
  WORK_DIR="$TMPDIR/gone"

  run cleanup_work_dir

  [ "$status" -eq 0 ]
}

@test "cleanup_work_dir does not remove a regular file" {
  WORK_DIR="$TMPDIR/file"
  : > "$WORK_DIR"

  cleanup_work_dir

  [ -e "$TMPDIR/file" ]
}

@test "cleanup_work_dir leaves the other files of TMPDIR alone" {
  create_work_dir
  : > "$TMPDIR/other"
  mkdir "$TMPDIR/other_dir"

  cleanup_work_dir

  [ -e "$TMPDIR/other" ]
  [ -d "$TMPDIR/other_dir" ]
}

@test "cleanup_work_dir can be called twice" {
  create_work_dir

  cleanup_work_dir
  run cleanup_work_dir

  [ "$status" -eq 0 ]
}
