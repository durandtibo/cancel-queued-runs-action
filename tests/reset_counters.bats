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

@test "reset_counters forgets the requests already sent" {
  REQUEST_SENT=true

  reset_counters

  [ "$REQUEST_SENT" = "false" ]
}

@test "no request is recorded as sent when the script is sourced" {
  [ "$REQUEST_SENT" = "false" ]
}

@test "reset_counters forgets the recorded runs" {
  RUN_RECORDS="1|5h00m|cancelled"$'\n'

  reset_counters

  [ -z "$RUN_RECORDS" ]
}

@test "reset_counters does not reset LISTING_TRUNCATED, which is set before the runs are processed" {
  LISTING_TRUNCATED=true

  reset_counters

  [ "$LISTING_TRUNCATED" = "true" ]
}
