#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_cancel_delay_seconds accepts 0" {
  run validate_cancel_delay_seconds 0

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_cancel_delay_seconds accepts 1" {
  run validate_cancel_delay_seconds 1

  [ "$status" -eq 0 ]
}

@test "validate_cancel_delay_seconds accepts a large value" {
  run validate_cancel_delay_seconds 3600

  [ "$status" -eq 0 ]
}

@test "validate_cancel_delay_seconds rejects an empty value" {
  run validate_cancel_delay_seconds ""

  [ "$status" -eq 1 ]
  [ "$output" = "::error::CANCEL_DELAY_SECONDS must be a non-negative integer (got '')" ]
}

@test "validate_cancel_delay_seconds rejects a missing argument" {
  run validate_cancel_delay_seconds

  [ "$status" -eq 1 ]
}

@test "validate_cancel_delay_seconds rejects a negative value" {
  run validate_cancel_delay_seconds -1

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got '-1')" ]]
}

@test "validate_cancel_delay_seconds rejects a decimal value" {
  run validate_cancel_delay_seconds 1.5

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got '1.5')" ]]
}

@test "validate_cancel_delay_seconds rejects a leading zero" {
  run validate_cancel_delay_seconds 01

  [ "$status" -eq 1 ]
}

@test "validate_cancel_delay_seconds rejects text" {
  run validate_cancel_delay_seconds "abc"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'abc')" ]]
}

@test "validate_cancel_delay_seconds rejects a command injection attempt" {
  run validate_cancel_delay_seconds '1; rm -rf /'

  [ "$status" -eq 1 ]
}

@test "validate_cancel_delay_seconds writes the error on stderr" {
  out=$(validate_cancel_delay_seconds abc 2>/dev/null) || true

  [ -z "$out" ]
}
