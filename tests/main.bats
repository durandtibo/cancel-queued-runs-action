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
  unset DRY_RUN FORCE_BUFFER_HOURS WORKFLOW STATUSES CANCEL_DELAY_SECONDS FAIL_ON_ERROR MAX_CANCELLATIONS BRANCH EVENT

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
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer (got 'abc')" ]] || false
}

@test "main fails when MAX_AGE_HOURS is zero" {
  export MAX_AGE_HOURS=0

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]] || false
}

@test "main fails when MAX_AGE_HOURS is negative" {
  export MAX_AGE_HOURS=-5

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]] || false
}

@test "main fails when MAX_AGE_HOURS is not an integer" {
  export MAX_AGE_HOURS=1.5

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]] || false
}

@test "main fails when MAX_AGE_HOURS has a leading zero" {
  export MAX_AGE_HOURS=08

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]] || false
}

@test "main fails when REPO is empty" {
  export REPO=""

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO is required" ]] || false
}

@test "main fails when REPO is unset" {
  unset REPO

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO is required" ]] || false
}

@test "main fails when REPO is not in owner/name format" {
  export REPO="not-a-repo"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO must be in owner/name format (got 'not-a-repo')" ]] || false
}

@test "main fails when REPO contains path traversal" {
  export REPO="octocat/.."

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO must be in owner/name format" ]] || false
}

@test "main fails when there are no credentials" {
  unset GH_TOKEN GITHUB_TOKEN
  gh() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "No GitHub credentials found" ]] || false
}

@test "main fails when GH_TOKEN is empty and gh is not logged in" {
  export GH_TOKEN=""
  unset GITHUB_TOKEN
  gh() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "No GitHub credentials found" ]] || false
}

@test "main reports validation errors as ::error:: annotations" {
  export REPO="bad"

  run main

  [[ "$output" =~ ^::error:: ]] || false
}

@test "main fails when an internal tuning variable is invalid" {
  export MAX_RETRIES="many"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::MAX_RETRIES must be a non-negative integer (got 'many')" ]] || false
}

@test "main does not fetch runs when an internal tuning variable is invalid" {
  fetch_runs() { echo "fetch_runs called" >> "$LOG_FILE"; }
  export RETRY_BASE_DELAY=0

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$LOG_FILE" ]
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
  [[ "$output" =~ "Configured max age: 24 hours" ]] || false
  [[ "$output" =~ "stale workflow runs for myorg/myrepo" ]] || false
}

@test "main succeeds without processing anything when there are no queued runs" {
  fetch_runs() { :; }

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 0 workflow run(s)." ]] || false
  [[ "$output" =~ "No workflow runs found." ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main reports the number of queued runs" {
  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 2 workflow run(s)." ]] || false
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
  [[ "$output" =~ "All eligible runs processed successfully." ]] || false
}

@test "main fails when process_all_runs reports a failure" {
  export MOCK_PROCESS_STATUS=1

  run main

  [ "$status" -eq 1 ]
  [[ ! "$output" =~ "All eligible runs processed successfully." ]] || false
}

@test "main accepts a MAX_AGE_HOURS value of 1" {
  export MAX_AGE_HOURS=1

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Configured max age: 1 hours" ]] || false
}

# --------------------------------------------------------
# Dry run
# --------------------------------------------------------

@test "main fails when DRY_RUN is not true or false" {
  export DRY_RUN="maybe"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "DRY_RUN must be 'true' or 'false' (got 'maybe')" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main announces the dry run" {
  export DRY_RUN=true

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dry run enabled: no run will be cancelled." ]] || false
}

@test "main still processes the runs in dry run" {
  export DRY_RUN=true

  run main

  [ "$status" -eq 0 ]
  grep -q "process_all_runs called" "$LOG_FILE"
}

@test "main does not announce a dry run by default" {
  run main

  [[ ! "$output" =~ "Dry run" ]] || false
}

# --------------------------------------------------------
# Force-cancel buffer
# --------------------------------------------------------

@test "main fails when FORCE_BUFFER_HOURS is invalid" {
  export FORCE_BUFFER_HOURS="-2"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "FORCE_BUFFER_HOURS must be a non-negative integer (got '-2')" ]] || false
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

  grep -q "Runs found | 2 |" "$GITHUB_STEP_SUMMARY"
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

# --------------------------------------------------------
# Workflow filter
# --------------------------------------------------------

@test "main fails when WORKFLOW is invalid" {
  export WORKFLOW="../secrets"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "WORKFLOW must be a workflow file name" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main announces the workflow filter" {
  export WORKFLOW="ci.yaml"

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Only the runs of the workflow ci.yaml are considered." ]] || false
}

@test "main does not mention a workflow without filter" {
  run main

  [[ ! "$output" =~ "Only the runs of the workflow" ]] || false
}

# --------------------------------------------------------
# Run statuses
# --------------------------------------------------------

@test "main fails when STATUSES contains in_progress" {
  export STATUSES="queued,in_progress"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "unsupported status 'in_progress'" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main fails when STATUSES is empty" {
  export STATUSES=""

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "STATUSES must not be empty" ]] || false
}

@test "main announces the statuses when they are not only queued" {
  export STATUSES="queued, waiting"

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Run statuses considered: queued,waiting" ]] || false
}

@test "main does not mention the statuses by default" {
  run main

  [[ ! "$output" =~ "Run statuses considered" ]] || false
}

# --------------------------------------------------------
# Failure to list the runs
# --------------------------------------------------------

@test "main fails with an ::error:: annotation when the runs cannot be listed" {
  fetch_runs() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Cannot list the workflow runs of myorg/myrepo" ]] || false
}

@test "main does not process any run when the runs cannot be listed" {
  fetch_runs() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$LOG_FILE" ]
  [[ ! "$output" =~ "Found" ]] || false
}

@test "main writes zero outputs when the runs cannot be listed" {
  setup_outputs
  fetch_runs() { return 1; }

  run main

  [ "$status" -eq 1 ]
  grep -qx "found_count=0" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=0" "$GITHUB_OUTPUT"
  grep -qx "skipped_count=0" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
  grep -qx "would_cancel_count=0" "$GITHUB_OUTPUT"
}

@test "main does not write the summary when the runs cannot be listed" {
  setup_outputs
  fetch_runs() { return 1; }

  run main

  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

# --------------------------------------------------------
# Required commands
# --------------------------------------------------------

@test "main fails when a required command is missing" {
  validate_dependencies() {
    echo "::error::Required command(s) not found: jq" >&2
    return 1
  }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Required command(s) not found: jq" ]] || false
}

@test "main checks the required commands before anything else" {
  validate_dependencies() { return 1; }
  validate_max_age_hours() { echo "validate_max_age_hours called" >> "$LOG_FILE"; }
  fetch_runs() { echo "fetch_runs called" >> "$LOG_FILE"; }

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$LOG_FILE" ]
}

# --------------------------------------------------------
# Variables
# --------------------------------------------------------

@test "main does not leak its variables in the calling shell" {
  # Called without run, so that the variables would be visible here
  main >/dev/null

  [ -z "${runs+x}" ]
  [ -z "${run_count+x}" ]
}

@test "main fails with an ::error:: annotation when the list of runs cannot be counted" {
  jq() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Cannot parse the list of workflow runs of myorg/myrepo" ]] || false
}

@test "main writes zero outputs when the list of runs cannot be counted" {
  setup_outputs
  jq() { return 1; }

  run main

  [ "$status" -eq 1 ]
  grep -qx "found_count=0" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
}

@test "main does not process any run when the list of runs cannot be counted" {
  jq() { return 1; }

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$LOG_FILE" ]
}

@test "main fails when the list of runs cannot be counted even if FAIL_ON_ERROR is false" {
  export FAIL_ON_ERROR=false
  jq() { return 1; }

  run main

  [ "$status" -eq 1 ]
}

@test "main reports listing_truncated=false by default" {
  setup_outputs

  run main

  [ "$status" -eq 0 ]
  grep -qx "listing_truncated=false" "$GITHUB_OUTPUT"
}

@test "main reports listing_truncated=true when fetch_runs reports a truncated listing" {
  setup_outputs
  fetch_runs() {
    LISTING_TRUNCATED=true
    echo '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}'
  }

  run main

  [ "$status" -eq 0 ]
  grep -qx "listing_truncated=true" "$GITHUB_OUTPUT"
  grep -q 'maximum that GitHub returns' "$GITHUB_STEP_SUMMARY"
}

@test "main does not keep a truncation from a previous call" {
  setup_outputs
  LISTING_TRUNCATED=true

  run main

  grep -qx "listing_truncated=false" "$GITHUB_OUTPUT"
}

@test "main reports listing_truncated=false when the runs cannot be listed" {
  setup_outputs
  fetch_runs() { LISTING_TRUNCATED=true; return 1; }

  run main

  [ "$status" -eq 1 ]
  grep -qx "listing_truncated=false" "$GITHUB_OUTPUT"
}

@test "main passes the listing to process_all_runs through a file without altering it" {
  fetch_runs() { printf '%s\n' '{"id": 7, "queued_at": "2025-01-01T01:00:00Z"}' '{"id": 8, "queued_at": "2025-01-01T02:00:00Z"}'; }

  run main

  [ "$(sed -n 2p "$LOG_FILE")" = '{"id": 7, "queued_at": "2025-01-01T01:00:00Z"}' ]
  [ "$(sed -n 3p "$LOG_FILE")" = '{"id": 8, "queued_at": "2025-01-01T02:00:00Z"}' ]
}

@test "main removes its temporary file" {
  export TMPDIR="$MOCK_DIR/tmp"
  mkdir -p "$TMPDIR"

  run main

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "main removes its temporary file when the runs cannot be listed" {
  export TMPDIR="$MOCK_DIR/tmp"
  mkdir -p "$TMPDIR"
  fetch_runs() { return 1; }

  run main

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "main does not leak its variables when the runs cannot be listed" {
  fetch_runs() { return 1; }

  main >/dev/null 2>&1 || true

  [ -z "${runs+x}" ]
  [ -z "${run_count+x}" ]
}

@test "main does not overwrite a runs variable of the calling shell" {
  runs="caller value"

  main >/dev/null

  [ "$runs" = "caller value" ]
}

# --------------------------------------------------------
# Delay between the cancel requests
# --------------------------------------------------------

@test "main fails when CANCEL_DELAY_SECONDS is invalid" {
  export CANCEL_DELAY_SECONDS="-1"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "CANCEL_DELAY_SECONDS must be a non-negative integer (got '-1')" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main accepts a CANCEL_DELAY_SECONDS value of 0" {
  export CANCEL_DELAY_SECONDS=0

  run main

  [ "$status" -eq 0 ]
}

@test "main announces the delay between the requests" {
  export CANCEL_DELAY_SECONDS=2

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Waiting 2s between two cancel requests." ]] || false
}

@test "main does not mention the delay by default" {
  run main

  [[ ! "$output" =~ "Waiting" ]] || false
}

# --------------------------------------------------------
# Fail on error
# --------------------------------------------------------

@test "main fails when FAIL_ON_ERROR is not true or false" {
  export FAIL_ON_ERROR="sometimes"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAIL_ON_ERROR must be 'true' or 'false' (got 'sometimes')" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main fails when a run could not be cancelled by default" {
  export MOCK_PROCESS_STATUS=1

  run main

  [ "$status" -eq 1 ]
}

@test "main fails when a run could not be cancelled and FAIL_ON_ERROR is true" {
  export FAIL_ON_ERROR=true
  export MOCK_PROCESS_STATUS=1

  run main

  [ "$status" -eq 1 ]
  [[ ! "$output" =~ "fail_on_error is false" ]] || false
}

@test "main succeeds with a warning when a run could not be cancelled and FAIL_ON_ERROR is false" {
  export FAIL_ON_ERROR=false
  export MOCK_PROCESS_STATUS=1

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::" ]] || false
  [[ "$output" =~ "fail_on_error is false" ]] || false
}

@test "main does not say that all the runs succeeded when FAIL_ON_ERROR is false and a run failed" {
  export FAIL_ON_ERROR=false
  export MOCK_PROCESS_STATUS=1

  run main

  [[ ! "$output" =~ "All eligible runs processed successfully." ]] || false
}

@test "main still writes the failed count when FAIL_ON_ERROR is false" {
  setup_outputs
  export FAIL_ON_ERROR=false
  export MOCK_PROCESS_STATUS=1
  export MOCK_FAILED=3

  run main

  [ "$status" -eq 0 ]
  grep -qx "failed_count=3" "$GITHUB_OUTPUT"
  grep -q "Failed | 3 |" "$GITHUB_STEP_SUMMARY"
}

@test "main reports a failed run when the list of runs cannot be parsed and FAIL_ON_ERROR is false" {
  setup_outputs
  export FAIL_ON_ERROR=false
  # use the real process_all_runs with a listing that is valid JSON but that
  # does not contain run objects, so that the runs can be counted but not parsed
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  fetch_runs() { printf '%s\n' '"not a run"' '"neither is this"'; }

  run main

  [ "$status" -eq 0 ]
  grep -qx "failed_count=2" "$GITHUB_OUTPUT"
  [[ "$output" =~ "2 run(s) could not be processed" ]] || false
}

@test "main still fails when the runs cannot be listed and FAIL_ON_ERROR is false" {
  export FAIL_ON_ERROR=false
  fetch_runs() { return 1; }

  run main

  [ "$status" -eq 1 ]
}

@test "main still fails on an invalid input when FAIL_ON_ERROR is false" {
  export FAIL_ON_ERROR=false
  export MAX_AGE_HOURS=abc

  run main

  [ "$status" -eq 1 ]
}

@test "main succeeds when nothing failed and FAIL_ON_ERROR is false" {
  export FAIL_ON_ERROR=false

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "All eligible runs processed successfully." ]] || false
}

@test "main writes the statuses considered in the summary" {
  setup_outputs
  export STATUSES="queued,waiting"

  run main

  [ "$status" -eq 0 ]
  grep -qx 'Statuses considered: `queued,waiting`' "$GITHUB_STEP_SUMMARY"
}

# --------------------------------------------------------
# Wording of the logs
# --------------------------------------------------------

@test "main does not say queued when only other statuses are considered" {
  export STATUSES="waiting"

  run main

  [ "$status" -eq 0 ]
  [[ ! "$output" =~ [Qq]ueued ]] || false
}

@test "main does not say queued when no run is found for other statuses" {
  export STATUSES="pending,requested"
  fetch_runs() { :; }

  run main

  [ "$status" -eq 0 ]
  [[ "$output" =~ "No workflow runs found." ]] || false
  [[ ! "$output" =~ [Qq]ueued ]] || false
}

# --------------------------------------------------------
# Failure matrix: exit code and reporting for each kind of failure, with
# FAIL_ON_ERROR=true and FAIL_ON_ERROR=false. The real process_all_runs is
# used, with a fake listing and a fake process_run.
# --------------------------------------------------------

OLD_RUN='{"id": 11, "queued_at": "2020-01-01T00:00:00Z"}'

# Use the real functions of the script and fake the listing
use_real_flow() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  fetch_runs() { printf '%s\n' "$MOCK_RUNS"; }
}

# --- a cancel request fails ---

@test "failure matrix: a failed cancellation fails main when FAIL_ON_ERROR is true" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS="$OLD_RUN"
  export FAIL_ON_ERROR=true
  process_run() { PROCESS_RUN_OUTCOME=failed; return 1; }

  run main

  [ "$status" -eq 1 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
}

@test "failure matrix: a failed cancellation does not fail main when FAIL_ON_ERROR is false" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS="$OLD_RUN"
  export FAIL_ON_ERROR=false
  process_run() { PROCESS_RUN_OUTCOME=failed; return 1; }

  run main

  [ "$status" -eq 0 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
}

@test "failure matrix: a failed cancellation is listed in the summary" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS="$OLD_RUN"
  export FAIL_ON_ERROR=false
  process_run() { PROCESS_RUN_OUTCOME=failed; return 1; }

  run main

  grep -q "| Failed | 1 |" "$GITHUB_STEP_SUMMARY"
  grep -q "actions/runs/11) | .* | Failed |$" "$GITHUB_STEP_SUMMARY"
}

# --- a run has an invalid timestamp ---

@test "failure matrix: an invalid timestamp fails main when FAIL_ON_ERROR is true" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS='{"id": 12, "queued_at": "yesterday"}'
  export FAIL_ON_ERROR=true

  run main

  [ "$status" -eq 1 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
}

@test "failure matrix: an invalid timestamp does not fail main when FAIL_ON_ERROR is false" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS='{"id": 12, "queued_at": "yesterday"}'
  export FAIL_ON_ERROR=false

  run main

  [ "$status" -eq 0 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
  [[ "$output" =~ "::error::Skipping run 12" ]] || false
}

@test "failure matrix: an invalid timestamp does not prevent the other runs from being processed" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS="$(printf '%s\n' '{"id": 12, "queued_at": "yesterday"}' "$OLD_RUN")"
  export FAIL_ON_ERROR=false
  process_run() { echo "process_run $1" >> "$LOG_FILE"; PROCESS_RUN_OUTCOME=cancelled; return 0; }

  run main

  grep -qx "process_run 11" "$LOG_FILE"
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=1" "$GITHUB_OUTPUT"
}

# --- the list of runs cannot be parsed ---

@test "failure matrix: an unparsable list fails main when FAIL_ON_ERROR is true" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS='"not a run"'
  export FAIL_ON_ERROR=true

  run main

  [ "$status" -eq 1 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
}

@test "failure matrix: an unparsable list does not fail main when FAIL_ON_ERROR is false" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS='"not a run"'
  export FAIL_ON_ERROR=false

  run main

  [ "$status" -eq 0 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
}

# --- the runs cannot be listed: always a failure ---

@test "failure matrix: a listing failure fails main when FAIL_ON_ERROR is true" {
  setup_outputs
  export FAIL_ON_ERROR=true
  fetch_runs() { return 1; }

  run main

  [ "$status" -eq 1 ]
}

@test "failure matrix: a listing failure fails main when FAIL_ON_ERROR is false" {
  setup_outputs
  export FAIL_ON_ERROR=false
  fetch_runs() { return 1; }

  run main

  [ "$status" -eq 1 ]
}

@test "failure matrix: a listing failure writes the outputs but no summary" {
  setup_outputs
  fetch_runs() { return 1; }

  run main

  grep -qx "found_count=0" "$GITHUB_OUTPUT"
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

# --- an input is invalid: always a failure, before any API call ---

@test "failure matrix: an invalid input fails main when FAIL_ON_ERROR is false" {
  setup_outputs
  export FAIL_ON_ERROR=false
  export MAX_AGE_HOURS=abc
  fetch_runs() { echo "fetch_runs called" >> "$LOG_FILE"; }

  run main

  [ "$status" -eq 1 ]
  [ ! -s "$LOG_FILE" ]
}

@test "failure matrix: an invalid input writes neither outputs nor summary" {
  setup_outputs
  export MAX_AGE_HOURS=abc

  run main

  [ ! -s "$GITHUB_OUTPUT" ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

# --- cases that are not failures ---

@test "failure matrix: a skipped run is not a failure whatever FAIL_ON_ERROR is" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS="$OLD_RUN"
  export FAIL_ON_ERROR=true
  process_run() { PROCESS_RUN_OUTCOME=skipped; return 0; }

  run main

  [ "$status" -eq 0 ]
  grep -qx "skipped_count=1" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
}

@test "failure matrix: no run is not a failure" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS=""
  export FAIL_ON_ERROR=true

  run main

  [ "$status" -eq 0 ]
  grep -qx "found_count=0" "$GITHUB_OUTPUT"
}

@test "failure matrix: some failures among successes still fail main when FAIL_ON_ERROR is true" {
  setup_outputs
  use_real_flow
  export MOCK_RUNS="$(printf '%s\n' '{"id": 11, "queued_at": "2020-01-01T00:00:00Z"}' '{"id": 13, "queued_at": "2020-01-01T00:00:00Z"}')"
  export FAIL_ON_ERROR=true
  process_run() {
    if [ "$1" = "13" ]; then PROCESS_RUN_OUTCOME=failed; return 1; fi
    PROCESS_RUN_OUTCOME=cancelled
  }

  run main

  [ "$status" -eq 1 ]
  grep -qx "cancelled_count=1" "$GITHUB_OUTPUT"
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
}

@test "main creates its temporary file with make_temp_file" {
  make_temp_file() {
    echo called >> "$MOCK_DIR/make_temp_file.log"
    mktemp "$MOCK_DIR/runs.XXXXXX"
  }

  main > /dev/null

  [ "$(wc -l < "$MOCK_DIR/make_temp_file.log" | tr -d ' ')" -eq 1 ]
}

# --------------------------------------------------------
# Limit on the number of cancellations
# --------------------------------------------------------

@test "main fails when MAX_CANCELLATIONS is invalid" {
  export MAX_CANCELLATIONS="-1"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_CANCELLATIONS must be a non-negative integer (got '-1')" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main fails when MAX_CANCELLATIONS has a leading zero" {
  export MAX_CANCELLATIONS="05"

  run main

  [ "$status" -eq 1 ]
}

@test "main accepts a MAX_CANCELLATIONS value of 0" {
  export MAX_CANCELLATIONS=0

  run main

  [ "$status" -eq 0 ]
}

@test "main accepts a MAX_CANCELLATIONS value of 10" {
  export MAX_CANCELLATIONS=10

  run main

  [ "$status" -eq 0 ]
}

@test "main announces the limit on the number of cancellations" {
  export MAX_CANCELLATIONS=5

  run main

  [[ "$output" =~ "At most 5 run(s) will be cancelled." ]] || false
}

@test "main does not mention the limit by default" {
  run main

  [[ ! "$output" =~ "At most" ]] || false
}

@test "main does not fail when runs are left alone because of the limit" {
  export MAX_CANCELLATIONS=1
  process_all_runs() { DEFERRED_COUNT=4; return 0; }

  run main

  [ "$status" -eq 0 ]
}

@test "main writes deferred_count in the outputs" {
  export MAX_CANCELLATIONS=1
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"
  process_all_runs() { DEFERRED_COUNT=4; return 0; }

  main > /dev/null

  grep -qx "deferred_count=4" "$GITHUB_OUTPUT"
}

# --------------------------------------------------------
# Filters on the branch and the event
# --------------------------------------------------------

@test "main fails when BRANCH is a ref" {
  export BRANCH="refs/heads/main"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "BRANCH must be a branch name, not a ref" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main fails when EVENT is invalid" {
  export EVENT="Pull Request"

  run main

  [ "$status" -eq 1 ]
  [[ "$output" =~ "EVENT must be an event name" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "main accepts a branch and an event" {
  export BRANCH="feat/my-feature"
  export EVENT="pull_request"

  run main

  [ "$status" -eq 0 ]
}

@test "main announces the branch" {
  export BRANCH="main"

  run main

  [[ "$output" =~ "Only the runs of the branch main are considered." ]] || false
}

@test "main announces the event" {
  export EVENT="schedule"

  run main

  [[ "$output" =~ "Only the runs triggered by the event schedule are considered." ]] || false
}

@test "main does not mention the branch and the event by default" {
  run main

  [[ ! "$output" =~ "Only the runs of the branch" ]] || false
  [[ ! "$output" =~ "triggered by the event" ]] || false
}
