#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_max_cancellations accepts 0" {
  run validate_max_cancellations 0

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_max_cancellations accepts 1" {
  run validate_max_cancellations 1

  [ "$status" -eq 0 ]
}

@test "validate_max_cancellations accepts a large value" {
  run validate_max_cancellations 3600

  [ "$status" -eq 0 ]
}

@test "validate_max_cancellations rejects an empty value" {
  run validate_max_cancellations ""

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_CANCELLATIONS must be a non-negative integer (got '')" ]
}

@test "validate_max_cancellations rejects a missing argument" {
  run validate_max_cancellations

  [ "$status" -eq 1 ]
}

@test "validate_max_cancellations rejects a negative value" {
  run validate_max_cancellations -1

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got '-1')" ]] || false
}

@test "validate_max_cancellations rejects a decimal value" {
  run validate_max_cancellations 1.5

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got '1.5')" ]] || false
}

@test "validate_max_cancellations rejects a leading zero" {
  run validate_max_cancellations 01

  [ "$status" -eq 1 ]
}

@test "validate_max_cancellations rejects text" {
  run validate_max_cancellations "abc"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'abc')" ]] || false
}

@test "validate_max_cancellations rejects a command injection attempt" {
  run validate_max_cancellations '1; rm -rf /'

  [ "$status" -eq 1 ]
}

@test "validate_max_cancellations writes the error on stderr" {
  out=$(validate_max_cancellations abc 2>/dev/null) || true

  [ -z "$out" ]
}
