#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  reset_counters
}

@test "cancelled_run_ids_json prints an empty array when no run was recorded" {
  run cancelled_run_ids_json

  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "cancelled_run_ids_json lists a cancelled run" {
  record_run 101 "30h00m" cancelled

  run cancelled_run_ids_json

  [ "$output" = "[101]" ]
}

@test "cancelled_run_ids_json lists the cancelled runs in the order they were recorded" {
  record_run 103 "30h00m" cancelled
  record_run 101 "31h00m" cancelled
  record_run 102 "32h00m" cancelled

  run cancelled_run_ids_json

  [ "$output" = "[103,101,102]" ]
}

@test "cancelled_run_ids_json does not list the runs that would be cancelled" {
  record_run 101 "30h00m" would-cancel

  run cancelled_run_ids_json

  [ "$output" = "[]" ]
}

@test "cancelled_run_ids_json does not list the skipped runs" {
  record_run 101 "30h00m" skipped

  run cancelled_run_ids_json

  [ "$output" = "[]" ]
}

@test "cancelled_run_ids_json does not list the failed runs" {
  record_run 101 "30h00m" failed
  record_run 102 "unknown" failed

  run cancelled_run_ids_json

  [ "$output" = "[]" ]
}

@test "cancelled_run_ids_json only lists the cancelled runs among all the outcomes" {
  record_run 1 "30h00m" failed
  record_run 2 "30h00m" cancelled
  record_run 3 "30h00m" skipped
  record_run 4 "30h00m" would-cancel
  record_run 5 "30h00m" cancelled

  run cancelled_run_ids_json

  [ "$output" = "[2,5]" ]
}

@test "cancelled_run_ids_json prints a single line" {
  record_run 1 "30h00m" cancelled
  record_run 2 "30h00m" cancelled

  run cancelled_run_ids_json

  [ "${#lines[@]}" -eq 1 ]
}

@test "cancelled_run_ids_json prints a valid JSON array of numbers" {
  record_run 12947114653 "30h00m" cancelled
  record_run 12947114654 "30h00m" cancelled

  out=$(cancelled_run_ids_json)

  [ "$(echo "$out" | jq -c '.')" = "[12947114653,12947114654]" ]
  [ "$(echo "$out" | jq 'map(type) | unique | join(",")' -r)" = "number" ]
}

@test "cancelled_run_ids_json ignores a record whose ID is not a number" {
  record_run "abc" "30h00m" cancelled
  record_run "1; rm -rf /" "30h00m" cancelled
  record_run 7 "30h00m" cancelled

  run cancelled_run_ids_json

  [ "$output" = "[7]" ]
}

@test "cancelled_run_ids_json does not match a longer outcome" {
  record_run 1 "30h00m" cancelled-twice

  run cancelled_run_ids_json

  [ "$output" = "[]" ]
}

@test "cancelled_run_ids_json prints an empty array after a reset" {
  record_run 1 "30h00m" cancelled
  reset_counters

  run cancelled_run_ids_json

  [ "$output" = "[]" ]
}
