#!/usr/bin/env bats
#
# Tests of dev/check_dry_run_outputs.sh, which checks the outputs of a dry run
# of the action in ci-action.yaml.

setup() {
  CHECK="$BATS_TEST_DIRNAME/../dev/check_dry_run_outputs.sh"
  export ELIGIBLE_COUNT=3
  export CANCELLED_COUNT=0
  export SKIPPED_COUNT=0
  export FAILED_COUNT=0
  export CANCELLED_RUN_IDS="[]"
}

@test "check_dry_run_outputs accepts valid outputs" {
  run "$CHECK"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "eligible=3" ]] || false
}

@test "check_dry_run_outputs accepts a repository without eligible run" {
  export ELIGIBLE_COUNT=0

  run "$CHECK"

  [ "$status" -eq 0 ]
}

@test "check_dry_run_outputs rejects an empty output (not exposed by action.yaml)" {
  export ELIGIBLE_COUNT=

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "The output ELIGIBLE_COUNT must be a non-negative integer" ]] || false
}

@test "check_dry_run_outputs rejects an unset output" {
  unset FAILED_COUNT

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAILED_COUNT must be a non-negative integer" ]] || false
}

@test "check_dry_run_outputs rejects a count that is not an integer" {
  export SKIPPED_COUNT=many

  run "$CHECK"

  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs rejects a negative count and a leading zero" {
  export ELIGIBLE_COUNT=-1
  run "$CHECK"
  [ "$status" -eq 1 ]

  export ELIGIBLE_COUNT=01
  run "$CHECK"
  [ "$status" -eq 1 ]
}

@test "check_dry_run_outputs reports every invalid count" {
  export ELIGIBLE_COUNT=x
  export CANCELLED_COUNT=y

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "ELIGIBLE_COUNT" ]] || false
  [[ "$output" =~ "CANCELLED_COUNT" ]] || false
}

@test "check_dry_run_outputs rejects a run cancelled, skipped or failed in a dry run" {
  local name
  for name in CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT; do
    export ELIGIBLE_COUNT=3 CANCELLED_COUNT=0 SKIPPED_COUNT=0 FAILED_COUNT=0
    export "$name=1"
    run "$CHECK"
    [ "$status" -eq 1 ] || { echo "$name=1 accepted" >&2; false; }
    [[ "$output" =~ "$name must be 0 in a dry run" ]] || false
  done
}

@test "check_dry_run_outputs rejects a cancelled_run_ids that is not an empty array" {
  local value
  for value in "" "[101]" "null" "101"; do
    export CANCELLED_RUN_IDS="$value"
    run "$CHECK"
    [ "$status" -eq 1 ] || { echo "'$value' accepted" >&2; false; }
  done
}

@test "check_dry_run_outputs rejects an unset cancelled_run_ids" {
  unset CANCELLED_RUN_IDS

  run "$CHECK"

  [ "$status" -eq 1 ]
}
