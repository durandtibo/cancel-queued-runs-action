#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_max_age_hours accepts 1" {
  run validate_max_age_hours 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_max_age_hours accepts 24" {
  run validate_max_age_hours 24
  [ "$status" -eq 0 ]
}

@test "validate_max_age_hours accepts a large value" {
  run validate_max_age_hours 87600
  [ "$status" -eq 0 ]
}

@test "validate_max_age_hours rejects 0" {
  run validate_max_age_hours 0
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::MAX_AGE_HOURS must be a positive integer (got '0')" ]] || false
}

@test "validate_max_age_hours rejects a negative number" {
  run validate_max_age_hours -5
  [ "$status" -eq 1 ]
}

@test "validate_max_age_hours rejects a decimal number" {
  run validate_max_age_hours 1.5
  [ "$status" -eq 1 ]
}

@test "validate_max_age_hours rejects a leading zero" {
  run validate_max_age_hours 08
  [ "$status" -eq 1 ]
}

@test "validate_max_age_hours rejects text" {
  run validate_max_age_hours "abc"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'abc')" ]] || false
}

@test "validate_max_age_hours rejects an empty value" {
  run validate_max_age_hours ""
  [ "$status" -eq 1 ]
}

@test "validate_max_age_hours rejects a value with a trailing space" {
  run validate_max_age_hours "24 "
  [ "$status" -eq 1 ]
}

@test "validate_max_age_hours rejects a shell injection attempt" {
  run validate_max_age_hours '1; echo pwned'
  [ "$status" -eq 1 ]
  [[ ! "$output" =~ ^pwned ]] || false
}

@test "validate_max_age_hours writes the error on stderr" {
  out=$(validate_max_age_hours abc 2>/dev/null || true)
  [ -z "$out" ]
}
