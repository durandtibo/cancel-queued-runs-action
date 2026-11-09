#!/usr/bin/env bats
#
# Tests of dev/check_dry_run_outputs.sh, which checks the outputs of a dry run
# of the action in ci-test-local.yaml.

setup() {
  CHECK="$BATS_TEST_DIRNAME/../dev/check_dry_run_outputs.sh"
  export FOUND_COUNT=3
  export CANCELLED_COUNT=0
  export SKIPPED_COUNT=0
  export FAILED_COUNT=0
  export WOULD_CANCEL_COUNT=2
  export DEFERRED_COUNT=0
  export LISTING_TRUNCATED=false
  unset MAX_CANCELLATIONS
}

@test "check_dry_run_outputs accepts valid outputs" {
  run "$CHECK"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "found=3 would_cancel=2 deferred=0 truncated=false" ]] || false
}

@test "check_dry_run_outputs accepts a repository without run" {
  export FOUND_COUNT=0
  export WOULD_CANCEL_COUNT=0

  run "$CHECK"

  [ "$status" -eq 0 ]
}

@test "check_dry_run_outputs accepts every run that would be cancelled" {
  export WOULD_CANCEL_COUNT=3

  run "$CHECK"

  [ "$status" -eq 0 ]
}

@test "check_dry_run_outputs accepts a truncated listing" {
  export LISTING_TRUNCATED=true

  run "$CHECK"

  [ "$status" -eq 0 ]
}

@test "check_dry_run_outputs rejects an output that action.yaml does not expose (empty)" {
  export FOUND_COUNT=""

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "The output FOUND_COUNT must be a non-negative integer (got '')" ]] || false
}

@test "check_dry_run_outputs rejects an unset output" {
  unset WOULD_CANCEL_COUNT

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "WOULD_CANCEL_COUNT must be a non-negative integer" ]] || false
}

@test "check_dry_run_outputs rejects a count that is not an integer" {
  export SKIPPED_COUNT=abc

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "SKIPPED_COUNT must be a non-negative integer (got 'abc')" ]] || false
}

@test "check_dry_run_outputs rejects a negative count" {
  export FOUND_COUNT=-1

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs reports every invalid count" {
  export FOUND_COUNT=""
  export FAILED_COUNT="x"

  run "$CHECK"

  [ "$(echo "$output" | grep -c '::error::')" -eq 2 ]
}

@test "check_dry_run_outputs rejects a run cancelled in a dry run" {
  export CANCELLED_COUNT=1

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "CANCELLED_COUNT must be 0 in a dry run (got '1')" ]] || false
}

@test "check_dry_run_outputs rejects a run skipped in a dry run" {
  export SKIPPED_COUNT=1

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs rejects a failed run in a dry run" {
  export FAILED_COUNT=1

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs rejects more runs to cancel than runs found" {
  export WOULD_CANCEL_COUNT=4

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "would_cancel_count (4) cannot exceed found_count (3)" ]] || false
}

@test "check_dry_run_outputs rejects an empty listing_truncated" {
  export LISTING_TRUNCATED=""

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "LISTING_TRUNCATED must be 'true' or 'false' (got '')" ]] || false
}

@test "check_dry_run_outputs rejects a listing_truncated that is not a boolean" {
  export LISTING_TRUNCATED=maybe

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs compares the counts as numbers" {
  export FOUND_COUNT=9
  export WOULD_CANCEL_COUNT=10

  run "$CHECK"

  [ "$status" -eq 1 ]
}

# --------------------------------------------------------
# Limit on the number of cancellations
# --------------------------------------------------------

@test "check_dry_run_outputs rejects an unset deferred_count" {
  unset DEFERRED_COUNT

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "DEFERRED_COUNT must be a non-negative integer" ]] || false
}

@test "check_dry_run_outputs rejects a deferred_count that is not a number" {
  export DEFERRED_COUNT=many

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs accepts runs left alone when there is a limit" {
  export MAX_CANCELLATIONS=2
  export FOUND_COUNT=5
  export WOULD_CANCEL_COUNT=2
  export DEFERRED_COUNT=3

  run "$CHECK"

  [ "$status" -eq 0 ]
}

@test "check_dry_run_outputs rejects runs left alone without a limit" {
  export FOUND_COUNT=5
  export DEFERRED_COUNT=1

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "deferred_count must be 0 without a limit (got '1')" ]] || false
}

@test "check_dry_run_outputs rejects runs left alone when MAX_CANCELLATIONS is 0" {
  export MAX_CANCELLATIONS=0
  export DEFERRED_COUNT=1

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs rejects more runs to cancel than the limit" {
  export MAX_CANCELLATIONS=1
  export WOULD_CANCEL_COUNT=2

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "would_cancel_count (2) cannot exceed max_cancellations (1)" ]] || false
}

@test "check_dry_run_outputs accepts exactly the limit of runs to cancel" {
  export MAX_CANCELLATIONS=2
  export WOULD_CANCEL_COUNT=2

  run "$CHECK"

  [ "$status" -eq 0 ]
}

@test "check_dry_run_outputs rejects runs to cancel and left alone that exceed the runs found" {
  export MAX_CANCELLATIONS=2
  export FOUND_COUNT=3
  export WOULD_CANCEL_COUNT=2
  export DEFERRED_COUNT=2

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "cannot exceed found_count (3) together" ]] || false
}

@test "check_dry_run_outputs rejects a MAX_CANCELLATIONS that is not a number" {
  export MAX_CANCELLATIONS=lots

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_CANCELLATIONS must be a non-negative integer (got 'lots')" ]] || false
}
