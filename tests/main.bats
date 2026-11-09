#!/usr/bin/env bats

setup() {
  # Use absolute paths for mocks/logs (macOS BATS can change CWD)
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export LOG_FILE="$MOCK_DIR/calls.log"
  : > "$LOG_FILE"

  export REPO="myorg/myrepo"
  export MAX_AGE_HOURS=24
  export GH_TOKEN="test-token"

  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"

  # Mock the functions that talk to the network or do the actual work
  fetch_runs() {
    printf '%s\n' \
      '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "queued_at": "2025-01-01T02:00:00Z"}'
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

@test "main fails when REPO is not in owner/name format" {
  export REPO="not-a-repo"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO must be in owner/name format (got 'not-a-repo')" ]]
}

@test "main fails when REPO contains path traversal" {
  export REPO="octocat/.."

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO must be in owner/name format" ]]
}

@test "main fails when there are no credentials" {
  unset GH_TOKEN GITHUB_TOKEN
  gh() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "No GitHub credentials found" ]]
}

@test "main fails when GH_TOKEN is empty and gh is not logged in" {
  export GH_TOKEN=""
  unset GITHUB_TOKEN
  gh() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "No GitHub credentials found" ]]
}

@test "main reports validation errors as ::error:: annotations" {
  export REPO="bad"

  run main

  [[ "$output" =~ ^::error:: ]]
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

# --------------------------------------------------------
# Dry run
# --------------------------------------------------------

@test "main fails when DRY_RUN is not true or false" {
  export DRY_RUN="maybe"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "DRY_RUN must be 'true' or 'false' (got 'maybe')" ]]
  [ ! -s "$LOG_FILE" ]
}

@test "main announces the dry run" {
  export DRY_RUN=true

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dry run enabled: no run will be cancelled." ]]
}

@test "main still processes the runs in dry run" {
  export DRY_RUN=true

  run main

  [ "$status" -eq 0 ]
  grep -q "process_all_runs called" "$LOG_FILE"
}

@test "main does not announce a dry run by default" {
  run main

  [[ ! "$output" =~ "Dry run" ]]
}

# --------------------------------------------------------
# Force-cancel buffer
# --------------------------------------------------------

@test "main fails when FORCE_BUFFER_HOURS is invalid" {
  export FORCE_BUFFER_HOURS="-2"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "FORCE_BUFFER_HOURS must be a non-negative integer (got '-2')" ]]
  [ ! -s "$LOG_FILE" ]
}

@test "main accepts a FORCE_BUFFER_HOURS value of 0" {
  export FORCE_BUFFER_HOURS=0

  run main

  [ "$status" -eq 0 ]
}

# --------------------------------------------------------
# Outputs and summary
# --------------------------------------------------------

setup_outputs() {
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"

  # process_all_runs sets the counters like the real one
  process_all_runs() {
    CANCELLED_COUNT=2
    SKIPPED_COUNT=1
    FAILED_COUNT="${MOCK_FAILED:-0}"
    WOULD_CANCEL_COUNT=0
    return "${MOCK_PROCESS_STATUS:-0}"
  }
}

@test "main writes the outputs" {
  setup_outputs

  run main

  [ "$status" -eq 0 ]
  grep -qx "found_count=2" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=2" "$GITHUB_OUTPUT"
  grep -qx "skipped_count=1" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
  grep -qx "would_cancel_count=0" "$GITHUB_OUTPUT"
}

@test "main writes the summary" {
  setup_outputs

  run main

  grep -q "Queued runs found | 2 |" "$GITHUB_STEP_SUMMARY"
  grep -q "Cancelled | 2 |" "$GITHUB_STEP_SUMMARY"
}

@test "main writes the outputs even when some runs failed" {
  setup_outputs
  export MOCK_PROCESS_STATUS=1
  export MOCK_FAILED=3

  run main

  [ "$status" -eq 1 ]
  grep -qx "failed_count=3" "$GITHUB_OUTPUT"
  grep -q "Failed | 3 |" "$GITHUB_STEP_SUMMARY"
}

@test "main writes zeros when there are no queued runs" {
  setup_outputs
  fetch_runs() { :; }

  run main

  [ "$status" -eq 0 ]
  grep -qx "found_count=0" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=0" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
}

@test "main does not write outputs when the inputs are invalid" {
  setup_outputs
  export REPO="bad"

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$GITHUB_OUTPUT" ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

@test "main works without GITHUB_OUTPUT and GITHUB_STEP_SUMMARY" {
  unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY

  run main

  [ "$status" -eq 0 ]
}
