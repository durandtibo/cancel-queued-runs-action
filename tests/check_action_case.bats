#!/usr/bin/env bats
#
# Tests of dev/check_action_case.sh, which asserts the result of one case of
# tests/action_cases.json in ci-action.yaml (local and released action).

setup() {
  CHECK="$BATS_TEST_DIRNAME/../dev/check_action_case.sh"
  export CASE='{"id":"c","inputs":{"dry-run":"true"},"expect":"success"}'
  export OUTCOME=success
  export ELIGIBLE_COUNT=3 CANCELLED_COUNT=0 SKIPPED_COUNT=0 FAILED_COUNT=0 CANCELLED_RUN_IDS="[]"
}

# fails_with TEXT: the check fails (exit 1) and reports TEXT as an ::error::
fails_with() {
  run "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::[c] "*"$1"* ]] || { echo "$output" >&2; false; }
}

@test "a dry run with well formed outputs passes" {
  run "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Case c"*"eligible=3"* ]] || false
}

@test "an empty repository passes" {
  ELIGIBLE_COUNT=0 run "$CHECK"
  [ "$status" -eq 0 ]
}

@test "the outcome must be the expected one" {
  OUTCOME=failure fails_with "The outcome must be 'success'"
}

@test "a count that is empty (not exposed by action.yaml), negative, with a leading zero or not a number fails" {
  local value
  for value in "" -1 01 many 1.5; do
    ELIGIBLE_COUNT="$value" fails_with "ELIGIBLE_COUNT must be a non-negative integer"
  done
}

@test "an unset count fails" {
  unset SKIPPED_COUNT
  fails_with "SKIPPED_COUNT must be a non-negative integer"
}

@test "every invalid count is reported" {
  ELIGIBLE_COUNT=x CANCELLED_COUNT=y run "$CHECK"
  [[ "$output" == *"ELIGIBLE_COUNT"* && "$output" == *"CANCELLED_COUNT"* ]] || false
}

@test "cancelled-run-ids must be a JSON array of integers" {
  local value
  for value in "" "null" "101" '["a"]' "[1.5]" "[1,"; do
    CANCELLED_RUN_IDS="$value" fails_with "CANCELLED_RUN_IDS must be a JSON array of integers"
  done
}

@test "cancelled-run-ids must have one id per cancelled run" {
  CASE='{"id":"c","inputs":{},"expect":"success"}' CANCELLED_COUNT=1 ELIGIBLE_COUNT=1 CANCELLED_RUN_IDS="[]" \
    fails_with "must have CANCELLED_COUNT (1) ids"
}

@test "in a dry run nothing is cancelled, skipped or failed" {
  CANCELLED_COUNT=1 CANCELLED_RUN_IDS="[7]" fails_with "CANCELLED_COUNT must be 0 in a dry run"
  SKIPPED_COUNT=1 fails_with "SKIPPED_COUNT must be 0 in a dry run"
  FAILED_COUNT=1 fails_with "FAILED_COUNT must be 0 in a dry run"
}

@test "outside a dry run cancelled + skipped + failed must be eligible" {
  CASE='{"id":"c","inputs":{},"expect":"success"}' ELIGIBLE_COUNT=3 CANCELLED_COUNT=1 CANCELLED_RUN_IDS="[7]" \
    SKIPPED_COUNT=1 FAILED_COUNT=0 fails_with "must be eligible (3)"
  CASE='{"id":"c","inputs":{},"expect":"success"}' ELIGIBLE_COUNT=3 CANCELLED_COUNT=1 CANCELLED_RUN_IDS="[7]" \
    SKIPPED_COUNT=1 FAILED_COUNT=1 run "$CHECK"
  [ "$status" -eq 0 ]
}

@test "an exact eligible-count is asserted" {
  CASE='{"id":"c","inputs":{"dry-run":"true"},"expect":"success","eligible-count":"0"}' fails_with "ELIGIBLE_COUNT must be 0 (got '3')"
  CASE='{"id":"c","inputs":{"dry-run":"true"},"expect":"success","eligible-count":"0"}' ELIGIBLE_COUNT=0 run "$CHECK"
  [ "$status" -eq 0 ]
}

@test "a failure case expects the failure, and outputs that were not set after a failed validation" {
  export CASE='{"id":"c","inputs":{},"expect":"failure","outputs":"unset"}'
  OUTCOME=failure ELIGIBLE_COUNT="" CANCELLED_COUNT="" SKIPPED_COUNT="" FAILED_COUNT="" CANCELLED_RUN_IDS="" run "$CHECK"
  [ "$status" -eq 0 ]
  OUTCOME=success fails_with "The outcome must be 'failure'"
  OUTCOME=failure fails_with "must not be set after a failed validation"
}

@test "a failure after the validation has every output at 0 and []" {
  export CASE='{"id":"c","inputs":{},"expect":"failure","outputs":"zero"}'
  OUTCOME=failure ELIGIBLE_COUNT=0 CANCELLED_COUNT=0 SKIPPED_COUNT=0 FAILED_COUNT=0 CANCELLED_RUN_IDS="[]" run "$CHECK"
  [ "$status" -eq 0 ]
  OUTCOME=failure ELIGIBLE_COUNT="" CANCELLED_COUNT="" SKIPPED_COUNT="" FAILED_COUNT="" CANCELLED_RUN_IDS="" fails_with "must be 0"
}

@test "a failure case without an outputs rule only checks the outcome" {
  export CASE='{"id":"c","inputs":{},"expect":"failure"}'
  OUTCOME=failure ELIGIBLE_COUNT="" run "$CHECK"
  [ "$status" -eq 0 ]
}

@test "CASE is required" {
  unset CASE
  run "$CHECK"
  [ "$status" -ne 0 ]
}
