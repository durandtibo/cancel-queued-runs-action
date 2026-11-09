#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "record_run starts with no record" {
  [ -z "$RUN_RECORDS" ]
}

@test "record_run stores the id, the age and the outcome" {
  record_run 123 30h12m cancelled

  [ "$RUN_RECORDS" = "123|30h12m|cancelled"$'\n' ]
}

@test "record_run appends one line per run" {
  record_run 1 5h00m cancelled
  record_run 2 6h00m failed
  record_run 3 unknown failed

  [ "$(printf '%s' "$RUN_RECORDS" | grep -c '')" -eq 3 ]
  printf '%s' "$RUN_RECORDS" | sed -n 2p | grep -qx "2|6h00m|failed"
}

@test "record_run prints nothing" {
  out=$(record_run 1 5h00m cancelled)

  [ -z "$out" ]
}

@test "record_run is forgotten by reset_counters" {
  record_run 1 5h00m cancelled

  reset_counters

  [ -z "$RUN_RECORDS" ]
}
