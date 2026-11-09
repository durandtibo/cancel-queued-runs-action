#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR/tmp" "$MOCK_DIR/work"
  export TMPDIR="$MOCK_DIR/tmp"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  WORK_DIR=""
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "make_temp_file prints the path of an existing empty file" {
  file=$(make_temp_file)

  [ -f "$file" ]
  [ ! -s "$file" ]
}

@test "make_temp_file creates the file in TMPDIR when WORK_DIR is empty" {
  file=$(make_temp_file)

  [ "$(dirname "$file")" = "$TMPDIR" ]
}

@test "make_temp_file creates the file in WORK_DIR when it is set" {
  WORK_DIR="$MOCK_DIR/work"

  file=$(make_temp_file)

  [ "$(dirname "$file")" = "$MOCK_DIR/work" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "make_temp_file names the files after the action" {
  file=$(make_temp_file)

  [[ "$(basename "$file")" == cancel-queued-runs.* ]] || false
}

@test "make_temp_file creates a different file at every call" {
  a=$(make_temp_file)
  b=$(make_temp_file)

  [ "$a" != "$b" ]
}

@test "make_temp_file uses /tmp when neither WORK_DIR nor TMPDIR is set" {
  unset TMPDIR

  file=$(make_temp_file)

  [ "$(dirname "$file")" = "/tmp" ]
  rm -f "$file"
}

@test "make_temp_file fails when the directory does not exist" {
  WORK_DIR="$MOCK_DIR/does-not-exist"

  run make_temp_file

  [ "$status" -ne 0 ]
}

@test "make_temp_file creates a file that only the user can read" {
  file=$(make_temp_file)

  [[ "$(ls -l "$file")" == -rw-------* ]] || false
}
