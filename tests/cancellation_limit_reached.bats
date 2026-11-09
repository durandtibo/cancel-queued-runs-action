#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  reset_counters
  MAX_CANCELLATIONS=3
}

@test "cancellation_limit_reached is false before any cancellation" {
  run cancellation_limit_reached

  [ "$status" -eq 1 ]
}

@test "cancellation_limit_reached is false below the limit" {
  CANCELLED_COUNT=2

  run cancellation_limit_reached

  [ "$status" -eq 1 ]
}

@test "cancellation_limit_reached is true at the limit" {
  CANCELLED_COUNT=3

  run cancellation_limit_reached

  [ "$status" -eq 0 ]
}

@test "cancellation_limit_reached is true above the limit" {
  CANCELLED_COUNT=4

  run cancellation_limit_reached

  [ "$status" -eq 0 ]
}

@test "cancellation_limit_reached counts the runs that would be cancelled" {
  WOULD_CANCEL_COUNT=3

  run cancellation_limit_reached

  [ "$status" -eq 0 ]
}

@test "cancellation_limit_reached adds the cancelled runs and the runs that would be" {
  CANCELLED_COUNT=1
  WOULD_CANCEL_COUNT=2

  run cancellation_limit_reached

  [ "$status" -eq 0 ]
}

@test "cancellation_limit_reached does not count the skipped runs" {
  SKIPPED_COUNT=10

  run cancellation_limit_reached

  [ "$status" -eq 1 ]
}

@test "cancellation_limit_reached does not count the failed runs" {
  FAILED_COUNT=10

  run cancellation_limit_reached

  [ "$status" -eq 1 ]
}

@test "cancellation_limit_reached does not count the deferred runs" {
  DEFERRED_COUNT=10

  run cancellation_limit_reached

  [ "$status" -eq 1 ]
}

@test "cancellation_limit_reached is never true without a limit" {
  MAX_CANCELLATIONS=0
  CANCELLED_COUNT=1000

  run cancellation_limit_reached

  [ "$status" -eq 1 ]
}

@test "cancellation_limit_reached works with a limit of 1" {
  MAX_CANCELLATIONS=1

  run cancellation_limit_reached
  [ "$status" -eq 1 ]

  CANCELLED_COUNT=1
  run cancellation_limit_reached
  [ "$status" -eq 0 ]
}

@test "cancellation_limit_reached compares the numbers, not the text" {
  MAX_CANCELLATIONS=9
  CANCELLED_COUNT=10

  run cancellation_limit_reached

  [ "$status" -eq 0 ]
}

@test "cancellation_limit_reached prints nothing" {
  CANCELLED_COUNT=3

  run cancellation_limit_reached

  [ -z "$output" ]
}
