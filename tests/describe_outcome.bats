#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "describe_outcome describes a cancelled run" {
  run describe_outcome cancelled

  [ "$output" = "Cancelled" ]
}

@test "describe_outcome describes a run that would be cancelled" {
  run describe_outcome would-cancel

  [ "$output" = "Would be cancelled (dry run)" ]
}

@test "describe_outcome describes a skipped run" {
  run describe_outcome skipped

  [ "$output" = "Skipped (no longer cancellable)" ]
}

@test "describe_outcome describes a failed run" {
  run describe_outcome failed

  [ "$output" = "Failed" ]
}

@test "describe_outcome returns an unknown outcome as is" {
  run describe_outcome something

  [ "$output" = "something" ]
}

@test "describe_outcome returns nothing for a missing outcome" {
  run describe_outcome

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "describe_outcome describes a deleted run" {
  run describe_outcome deleted

  [ "$output" = "Deleted (zombie run without job)" ]
}
