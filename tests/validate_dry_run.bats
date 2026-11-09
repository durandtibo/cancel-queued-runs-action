#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_dry_run accepts true" {
  run validate_dry_run true
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_dry_run accepts false" {
  run validate_dry_run false
  [ "$status" -eq 0 ]
}

@test "validate_dry_run rejects an empty value" {
  run validate_dry_run ""
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::DRY_RUN must be 'true' or 'false' (got '')" ]] || false
}

@test "validate_dry_run rejects yes" {
  run validate_dry_run yes
  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'yes')" ]] || false
}

@test "validate_dry_run rejects 1" {
  run validate_dry_run 1
  [ "$status" -eq 1 ]
}

@test "validate_dry_run rejects a capitalized True" {
  run validate_dry_run True
  [ "$status" -eq 1 ]
}

@test "validate_dry_run writes the error on stderr" {
  out=$(validate_dry_run nope 2>/dev/null || true)
  [ -z "$out" ]
}
