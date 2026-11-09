#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_fail_on_error accepts true" {
  run validate_fail_on_error true

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_fail_on_error accepts false" {
  run validate_fail_on_error false

  [ "$status" -eq 0 ]
}

@test "validate_fail_on_error rejects an empty value" {
  run validate_fail_on_error ""

  [ "$status" -eq 1 ]
  [ "$output" = "::error::FAIL_ON_ERROR must be 'true' or 'false' (got '')" ]
}

@test "validate_fail_on_error rejects a missing argument" {
  run validate_fail_on_error

  [ "$status" -eq 1 ]
}

@test "validate_fail_on_error rejects yes" {
  run validate_fail_on_error yes

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'yes')" ]]
}

@test "validate_fail_on_error rejects 0" {
  run validate_fail_on_error 0

  [ "$status" -eq 1 ]
}

@test "validate_fail_on_error rejects a different case" {
  run validate_fail_on_error True

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'True')" ]]
}

@test "validate_fail_on_error writes the error on stderr" {
  out=$(validate_fail_on_error maybe 2>/dev/null) || true

  [ -z "$out" ]
}
