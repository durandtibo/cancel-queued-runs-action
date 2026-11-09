#!/usr/bin/env bats

setup() {
  # Use absolute paths for mocks/logs (macOS BATS can change CWD)
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export LOG_FILE="$MOCK_DIR/calls.log"
  : > "$LOG_FILE"

  export REPO="myorg/myrepo"
  export MAX_AGE_HOURS=24

  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"

  # Mock the functions that talk to the network or do the actual work
  fetch_runs() {
    printf '%s\n' \
      '{"id": 1, "updated_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "updated_at": "2025-01-01T02:00:00Z"}'
  }

  process_all_runs() {
    echo "process_all_runs called" >> "$LOG_FILE"
    printf '%s\n' "$1" >> "$LOG_FILE"
    return "${MOCK_PROCESS_STATUS:-0}"
  }
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# --------------------------------------------------------
# Input validation
# --------------------------------------------------------

@test "main fails when MAX_AGE_HOURS is not a number" {
  export MAX_AGE_HOURS="abc"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer (got 'abc')" ]]
}

@test "main fails when MAX_AGE_HOURS is zero" {
  export MAX_AGE_HOURS=0

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
}

@test "main fails when MAX_AGE_HOURS is negative" {
  export MAX_AGE_HOURS=-5

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
}

@test "main fails when MAX_AGE_HOURS is not an integer" {
  export MAX_AGE_HOURS=1.5

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
}

@test "main fails when MAX_AGE_HOURS has a leading zero" {
  export MAX_AGE_HOURS=08

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
}

@test "main fails when REPO is empty" {
  export REPO=""

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO is required" ]]
}

@test "main fails when REPO is unset" {
  unset REPO

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO is required" ]]
}

@test "main does not fetch runs when the inputs are invalid" {
  fetch_runs() { echo "fetch_runs called" >> "$LOG_FILE"; }
  export MAX_AGE_HOURS="abc"

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$LOG_FILE" ]
}

# --------------------------------------------------------
# Main flow
# --------------------------------------------------------

@test "main prints the configuration and the repository" {
  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Configured max age: 24 hours" ]]
  [[ "$output" =~ "stale queued workflow runs for myorg/myrepo" ]]
}

@test "main succeeds without processing anything when there are no queued runs" {
  fetch_runs() { :; }

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 0 queued workflow run(s)." ]]
  [[ "$output" =~ "No queued runs found." ]]
  [ ! -s "$LOG_FILE" ]
}

@test "main reports the number of queued runs" {
  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 2 queued workflow run(s)." ]]
}

@test "main passes the fetched runs to process_all_runs" {
  run main

  [ "$status" -eq 0 ]
  grep -q "process_all_runs called" "$LOG_FILE"
  grep -q '"id": 1' "$LOG_FILE"
  grep -q '"id": 2' "$LOG_FILE"
}

@test "main succeeds when all runs are processed successfully" {
  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "All eligible runs processed successfully." ]]
}

@test "main fails when process_all_runs reports a failure" {
  export MOCK_PROCESS_STATUS=1

  run main

  [ "$status" -eq 1 ]
  [[ ! "$output" =~ "All eligible runs processed successfully." ]]
}

@test "main accepts a MAX_AGE_HOURS value of 1" {
  export MAX_AGE_HOURS=1

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Configured max age: 1 hours" ]]
}
