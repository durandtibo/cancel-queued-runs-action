#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "dedupe_runs prints nothing for an empty input" {
  run dedupe_runs <<< ""

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dedupe_runs keeps the runs that are all different" {
  run dedupe_runs <<< "$(printf '%s\n' '{"id":1,"queued_at":"a"}' '{"id":2,"queued_at":"b"}')"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "dedupe_runs removes a run listed twice" {
  run dedupe_runs <<< "$(printf '%s\n' '{"id":1,"queued_at":"a"}' '{"id":2,"queued_at":"b"}' '{"id":1,"queued_at":"a"}')"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(echo "$output" | grep -c '"id":1,')" -eq 1 ]
}

@test "dedupe_runs keeps the first occurrence of a run" {
  run dedupe_runs <<< "$(printf '%s\n' '{"id":1,"queued_at":"first"}' '{"id":1,"queued_at":"second"}')"

  [ "$status" -eq 0 ]
  [ "$output" = '{"id":1,"queued_at":"first"}' ]
}

@test "dedupe_runs preserves the order of the runs" {
  run dedupe_runs <<< "$(printf '%s\n' '{"id":3}' '{"id":1}' '{"id":3}' '{"id":2}')"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\n')" = '{"id":3}{"id":1}{"id":2}' ]
}

@test "dedupe_runs compares numeric and string IDs as the same ID" {
  run dedupe_runs <<< "$(printf '%s\n' '{"id":1}' '{"id":"1"}')"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "dedupe_runs fails when the input is not valid JSON" {
  run dedupe_runs <<< "this is not json"

  [ "$status" -ne 0 ]
}

@test "dedupe_runs keeps working with large ids" {
  run dedupe_runs <<< "$(printf '%s\n' '{"id":12947114653}' '{"id":12947114653}')"

  [ "$status" -eq 0 ]
  [ "$output" = '{"id":12947114653}' ]
}
