#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_event accepts an empty value (no filter)" {
  run validate_event ""

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_event accepts a missing argument (no filter)" {
  run validate_event

  [ "$status" -eq 0 ]
}

@test "validate_event accepts push" {
  run validate_event push

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_event accepts pull_request" {
  run validate_event pull_request

  [ "$status" -eq 0 ]
}

@test "validate_event accepts pull_request_target" {
  run validate_event pull_request_target

  [ "$status" -eq 0 ]
}

@test "validate_event accepts schedule" {
  run validate_event schedule

  [ "$status" -eq 0 ]
}

@test "validate_event accepts workflow_dispatch" {
  run validate_event workflow_dispatch

  [ "$status" -eq 0 ]
}

@test "validate_event accepts an event that GitHub may add later" {
  run validate_event some_future_event

  [ "$status" -eq 0 ]
}

@test "validate_event rejects uppercase letters" {
  run validate_event Push

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::EVENT must be an event name such as push or pull_request" ]] || false
  [[ "$output" =~ "(got 'Push')" ]] || false
}

@test "validate_event rejects a dash (pull-request)" {
  run validate_event pull-request

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a space" {
  run validate_event "pull request"

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a comma separated list" {
  run validate_event "push,schedule"

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a digit" {
  run validate_event push2

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a leading underscore" {
  run validate_event _push

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a value that adds a query parameter" {
  run validate_event "push&status=completed"

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a command injection attempt" {
  run validate_event 'push; rm -rf /'

  [ "$status" -eq 1 ]
}

@test "validate_event rejects a value with a newline" {
  run validate_event $'push\nschedule'

  [ "$status" -eq 1 ]
}

@test "validate_event writes the error on stderr" {
  out=$(validate_event Push 2>/dev/null) || true

  [ -z "$out" ]
}
