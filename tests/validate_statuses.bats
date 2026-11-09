#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_statuses accepts queued" {
  run validate_statuses "queued"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_statuses accepts each supported status" {
  for s in queued waiting pending requested; do
    run validate_statuses "$s"
    [ "$status" -eq 0 ]
  done
}

@test "validate_statuses accepts a comma-separated list" {
  run validate_statuses "queued,waiting,pending,requested"
  [ "$status" -eq 0 ]
}

@test "validate_statuses ignores spaces around the commas" {
  run validate_statuses "queued, waiting , pending"
  [ "$status" -eq 0 ]
}

@test "validate_statuses accepts a trailing comma" {
  run validate_statuses "queued,"
  [ "$status" -eq 0 ]
}

@test "validate_statuses accepts duplicated statuses" {
  run validate_statuses "queued,queued"
  [ "$status" -eq 0 ]
}

@test "validate_statuses rejects in_progress" {
  run validate_statuses "in_progress"
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::STATUSES contains an unsupported status 'in_progress' (allowed: queued, waiting, pending, requested)" ]] || false
}

@test "validate_statuses rejects completed" {
  run validate_statuses "completed"
  [ "$status" -eq 1 ]
}

@test "validate_statuses rejects an unsupported status in a list" {
  run validate_statuses "queued,in_progress"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "'in_progress'" ]] || false
}

@test "validate_statuses rejects a typo" {
  run validate_statuses "queud"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "'queud'" ]] || false
}

@test "validate_statuses rejects an empty value" {
  run validate_statuses ""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "STATUSES must not be empty" ]] || false
}

@test "validate_statuses rejects a value with only spaces and commas" {
  run validate_statuses " , "
  [ "$status" -eq 1 ]
}

@test "validate_statuses rejects an empty element in the list" {
  run validate_statuses "queued,,waiting"
  [ "$status" -eq 1 ]
}

@test "validate_statuses rejects a leading comma" {
  run validate_statuses ",queued"
  [ "$status" -eq 1 ]
}

@test "validate_statuses rejects query string characters" {
  run validate_statuses "queued&per_page=1"
  [ "$status" -eq 1 ]
}

@test "validate_statuses is case sensitive" {
  run validate_statuses "Queued"
  [ "$status" -eq 1 ]
}

@test "validate_statuses writes the error on stderr" {
  out=$(validate_statuses "nope" 2>/dev/null || true)
  [ -z "$out" ]
}
