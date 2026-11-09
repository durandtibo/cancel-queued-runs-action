#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "reset_counters sets all the counters to 0" {
  CANCELLED_COUNT=5
  SKIPPED_COUNT=4
  FAILED_COUNT=3
  WOULD_CANCEL_COUNT=2

  reset_counters

  [ "$CANCELLED_COUNT" -eq 0 ]
  [ "$SKIPPED_COUNT" -eq 0 ]
  [ "$FAILED_COUNT" -eq 0 ]
  [ "$WOULD_CANCEL_COUNT" -eq 0 ]
}

@test "the counters are 0 when the script is sourced" {
  [ "$CANCELLED_COUNT" -eq 0 ]
  [ "$SKIPPED_COUNT" -eq 0 ]
  [ "$FAILED_COUNT" -eq 0 ]
  [ "$WOULD_CANCEL_COUNT" -eq 0 ]
}
