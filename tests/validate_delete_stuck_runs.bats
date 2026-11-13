#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_delete_stuck_runs accepts true" {
  run validate_delete_stuck_runs true

  [ "$status" -eq 0 ]
}

@test "validate_delete_stuck_runs accepts false" {
  run validate_delete_stuck_runs false

  [ "$status" -eq 0 ]
}

@test "validate_delete_stuck_runs rejects another value" {
  run validate_delete_stuck_runs yes

  [ "$status" -eq 1 ]
  [[ "$output" =~ "DELETE_STUCK_RUNS must be 'true' or 'false' (got 'yes')" ]] || false
}

@test "validate_delete_stuck_runs rejects an empty value" {
  run validate_delete_stuck_runs ""

  [ "$status" -eq 1 ]
}
