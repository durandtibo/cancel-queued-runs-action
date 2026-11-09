#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  CANCELLED_COUNT=3
  SKIPPED_COUNT=2
  FAILED_COUNT=1
  WOULD_CANCEL_COUNT=4
  DEFERRED_COUNT=5
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "write_outputs writes the five outputs" {
  run write_outputs 10

  [ "$status" -eq 0 ]
  grep -qx "found_count=10" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=3" "$GITHUB_OUTPUT"
  grep -qx "skipped_count=2" "$GITHUB_OUTPUT"
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
  grep -qx "would_cancel_count=4" "$GITHUB_OUTPUT"
}

@test "write_outputs writes zeros" {
  reset_counters

  run write_outputs 0

  grep -qx "found_count=0" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=0" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
}

@test "write_outputs appends to the file instead of overwriting it" {
  echo "previous=value" > "$GITHUB_OUTPUT"

  run write_outputs 10

  grep -qx "previous=value" "$GITHUB_OUTPUT"
  grep -qx "found_count=10" "$GITHUB_OUTPUT"
}

@test "write_outputs prints nothing on stdout" {
  run write_outputs 10

  [ -z "$output" ]
}

@test "write_outputs does nothing when GITHUB_OUTPUT is unset" {
  unset GITHUB_OUTPUT

  run write_outputs 10

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "write_outputs does nothing when GITHUB_OUTPUT is empty" {
  export GITHUB_OUTPUT=""

  run write_outputs 10

  [ "$status" -eq 0 ]
}

@test "write_outputs writes listing_truncated=false by default" {
  run write_outputs 10

  grep -qx "listing_truncated=false" "$GITHUB_OUTPUT"
}

@test "write_outputs writes listing_truncated=true when the listing was truncated" {
  LISTING_TRUNCATED=true

  run write_outputs 10

  grep -qx "listing_truncated=true" "$GITHUB_OUTPUT"
}

@test "write_outputs writes deferred_count" {
  write_outputs 10

  grep -qx "deferred_count=5" "$GITHUB_OUTPUT"
}

@test "write_outputs writes deferred_count=0 after a reset" {
  reset_counters

  write_outputs 0

  grep -qx "deferred_count=0" "$GITHUB_OUTPUT"
}
