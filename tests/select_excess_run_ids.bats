#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  RUNS='{"id":1,"queued_at":"2026-01-01T01:00:00Z"}
{"id":2,"queued_at":"2026-01-01T03:00:00Z"}
{"id":3,"queued_at":"2026-01-01T02:00:00Z"}'
}

@test "select_excess_run_ids prints nothing when MAX_RUNS is 0" {
  MAX_RUNS=0
  run select_excess_run_ids "$RUNS"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "select_excess_run_ids prints the oldest runs beyond the limit" {
  MAX_RUNS=2
  run select_excess_run_ids "$RUNS"

  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "select_excess_run_ids sorts by queue time and not by input order" {
  MAX_RUNS=1
  run select_excess_run_ids "$RUNS"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "1 3 " ]
}

@test "select_excess_run_ids prints nothing when the limit equals the number of runs" {
  MAX_RUNS=3
  run select_excess_run_ids "$RUNS"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "select_excess_run_ids prints nothing when the limit exceeds the number of runs" {
  MAX_RUNS=100
  run select_excess_run_ids "$RUNS"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "select_excess_run_ids handles an empty list" {
  MAX_RUNS=2
  run select_excess_run_ids ""

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "select_excess_run_ids ignores runs without queue time" {
  MAX_RUNS=1
  run select_excess_run_ids '{"id":1,"queued_at":null}
{"id":2,"queued_at":"2026-01-01T01:00:00Z"}'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "select_excess_run_ids fails on invalid JSON" {
  MAX_RUNS=1
  run select_excess_run_ids "not json"

  [ "$status" -ne 0 ]
}
