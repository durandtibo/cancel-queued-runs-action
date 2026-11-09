#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_force_buffer_hours accepts 0" {
  run validate_force_buffer_hours 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_force_buffer_hours accepts 3" {
  run validate_force_buffer_hours 3
  [ "$status" -eq 0 ]
}

@test "validate_force_buffer_hours accepts a large value" {
  run validate_force_buffer_hours 720
  [ "$status" -eq 0 ]
}

@test "validate_force_buffer_hours rejects a negative number" {
  run validate_force_buffer_hours -1
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::FORCE_BUFFER_HOURS must be a non-negative integer (got '-1')" ]] || false
}

@test "validate_force_buffer_hours rejects a decimal number" {
  run validate_force_buffer_hours 1.5
  [ "$status" -eq 1 ]
}

@test "validate_force_buffer_hours rejects a leading zero" {
  run validate_force_buffer_hours 03
  [ "$status" -eq 1 ]
}

@test "validate_force_buffer_hours rejects 00" {
  run validate_force_buffer_hours 00
  [ "$status" -eq 1 ]
}

@test "validate_force_buffer_hours rejects text" {
  run validate_force_buffer_hours abc
  [ "$status" -eq 1 ]
}

@test "validate_force_buffer_hours rejects an empty value" {
  run validate_force_buffer_hours ""
  [ "$status" -eq 1 ]
}

@test "validate_force_buffer_hours writes the error on stderr" {
  out=$(validate_force_buffer_hours abc 2>/dev/null || true)
  [ -z "$out" ]
}
