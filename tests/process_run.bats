#!/usr/bin/env bats

setup() {
    # Globals used by process_run
    export MAX_AGE_HOURS=2

    # Source the script under test
    source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"

    # Mock functions
    cancel_run() {
        local run_id="$1"
        case "$run_id" in
            "456") echo -e "HTTP/2.0 500 Internal Server Error\nContent-Type: application/json\n\n{\"message\":\"error\"}" ;;
            *) echo -e "HTTP/2.0 202 Accepted\nContent-Type: application/json\n\n{}" ;;
        esac
    }

    force_cancel_run() {
        local run_id="$1"
        case "$run_id" in
            "111") echo -e "HTTP/2.0 202 Accepted\nContent-Type: application/json\n\n{}" ;;
            *) echo -e "HTTP/2.0 500 Internal Server Error\nContent-Type: application/json\n\n{\"message\":\"error\"}" ;;
        esac
    }
}

teardown() {
  rm -rf "$BATS_TEST_DIRNAME/mocks"
}

# Record the calls to the cancel functions, to check that nothing is sent
record_calls() {
  mkdir -p "$BATS_TEST_DIRNAME/mocks"
  export CALL_LOG="$BATS_TEST_DIRNAME/mocks/calls.log"
  : > "$CALL_LOG"
  cancel_run() { echo "cancel_run $1" >> "$CALL_LOG"; echo "HTTP/2.0 202 Accepted"; }
  force_cancel_run() { echo "force_cancel_run $1" >> "$CALL_LOG"; echo "HTTP/2.0 202 Accepted"; }
}

@test "process_run cancels run older than MAX_AGE_HOURS with 202 response" {
    run process_run "123" $((3 * 3600))

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Cancelling run 123" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # Exit code should be 0 (success)
    [ "$status" -eq 0 ]
}

@test "process_run returns failure exit code for 500 response" {
    run process_run "456" $((4 * 3600))

    [[ "$output" =~ "Cancelling run 456" ]]
    [[ "$output" =~ "Status code: 500" ]]
    [[ "$output" =~ "Cancellation failed for run 456" ]]

    # Exit code should be 1 (failure)
    [ "$status" -eq 1 ]
}

@test "process_run force cancels run older than MAX_AGE_HOURS + 3h with 202 response" {
    run process_run "111" $((24 * 3600))

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Force-cancelling run 111" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # Exit code should be 0 (success)
    [ "$status" -eq 0 ]
}

@test "process_run does nothing if the age is below MAX_AGE_HOURS" {
    run process_run "789" $((1 * 3600))

    # Should have no output (nothing happens)
    [ -z "$output" ]

    # Exit code should be 0 (success - nothing to do)
    [ "$status" -eq 0 ]
}

@test "process_run does nothing if run_id is empty" {
    run process_run "" $((5 * 3600))

    # Should have no output (nothing happens)
    [ -z "$output" ]

    # Exit code should be 0 (success - nothing to do)
    [ "$status" -eq 0 ]
}

@test "process_run cancels all runs when MAX_AGE_HOURS=0" {
    export MAX_AGE_HOURS=0

    # Even runs with age 1 hour should be cancelled when MAX_AGE_HOURS=0
    run process_run "999" $((1 * 3600))

    # Check output contains cancellation info
    [[ "$output" =~ "Cancelling run 999" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # Exit code should be 0 (success)
    [ "$status" -eq 0 ]
}

@test "process_run falls back to force cancel when regular cancel fails for old run" {
    cancel_run() { echo -e "HTTP/2.0 409 Conflict\n\n{}"; }
    force_cancel_run() { echo -e "HTTP/2.0 202 Accepted\n\n{}"; }

    run process_run "789" $((24 * 3600))

    [[ "$output" =~ "Force-cancelling run 789" ]]
    [[ "$output" =~ "Status code: 202" ]]
    [ "$status" -eq 0 ]
}

# --------------------------------------------------------
# Boundary ages (MAX_AGE_HOURS=2, so the force threshold is 5)
# --------------------------------------------------------

@test "process_run does nothing when the age equals MAX_AGE_HOURS" {
  run process_run "123" $((2 * 3600))

  [ -z "$output" ]
  [ "$status" -eq 0 ]
}

@test "process_run uses standard cancel when the age is MAX_AGE_HOURS + 1 hour" {
  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "Cancelling run 123" ]]
  [[ ! "$output" =~ "Force-cancelling" ]]
  [ "$status" -eq 0 ]
}

@test "process_run uses standard cancel when the age equals MAX_AGE_HOURS + 3 hours" {
  run process_run "123" $((5 * 3600))

  [[ "$output" =~ "Cancelling run 123" ]]
  [[ ! "$output" =~ "Force-cancelling" ]]
  [ "$status" -eq 0 ]
}

@test "process_run uses force cancel when the age is MAX_AGE_HOURS + 4 hours" {
  run process_run "123" $((6 * 3600))

  [[ "$output" =~ "Force-cancelling run 123" ]]
  [ "$status" -eq 0 ]
}

@test "process_run does not call force cancel when regular cancel succeeds for old run" {
  force_cancel_run() { echo "force_cancel_run called" >&2; echo "HTTP/2.0 202 Accepted"; }

  run process_run "123" $((24 * 3600))

  [[ "$output" =~ "Force-cancelling run 123" ]]
  [[ ! "$output" =~ "force_cancel_run called" ]]
  [ "$status" -eq 0 ]
}

@test "process_run fails when both regular and force cancel fail for old run" {
  run process_run "456" $((24 * 3600))

  [[ "$output" =~ "Force-cancelling run 456" ]]
  [[ "$output" =~ "Status code: 500" ]]
  [[ "$output" =~ "Cancellation failed for run 456" ]]
  [ "$status" -eq 1 ]
}

# --------------------------------------------------------
# Sub-hour precision (regression: ages used to be truncated to whole hours)
# --------------------------------------------------------

@test "process_run does nothing when the age is exactly MAX_AGE_HOURS in seconds" {
  run process_run "123" 7200

  [ -z "$output" ]
  [ "$status" -eq 0 ]
}

@test "process_run cancels a run that is one second older than MAX_AGE_HOURS" {
  run process_run "123" 7201

  [[ "$output" =~ "Cancelling run 123" ]]
  [ "$status" -eq 0 ]
}

@test "process_run cancels a run that is 30 minutes older than MAX_AGE_HOURS" {
  run process_run "123" $((2 * 3600 + 1800))

  [[ "$output" =~ "Cancelling run 123 (age=2h30m)" ]]
  [ "$status" -eq 0 ]
}

@test "process_run uses standard cancel when the age is exactly MAX_AGE_HOURS + 3 hours in seconds" {
  run process_run "123" 18000

  [[ "$output" =~ "Cancelling run 123" ]]
  [[ ! "$output" =~ "Force-cancelling" ]]
  [ "$status" -eq 0 ]
}

@test "process_run uses force cancel when the age is one second over MAX_AGE_HOURS + 3 hours" {
  run process_run "123" 18001

  [[ "$output" =~ "Force-cancelling run 123" ]]
  [ "$status" -eq 0 ]
}

@test "process_run shows the age in hours and minutes" {
  run process_run "123" $((24 * 3600 + 59 * 60))

  [[ "$output" =~ "(age=24h59m)" ]]
}

# --------------------------------------------------------
# gh API failure without any HTTP response
# --------------------------------------------------------

@test "process_run reports a failure without HTTP response when the API call fails" {
  cancel_run() { :; }

  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "No HTTP response (the gh API call failed) for run 123" ]]
  [[ "$output" =~ "Cancellation failed for run 123" ]]
  [ "$status" -eq 1 ]
}

# --------------------------------------------------------
# Runs that are no longer cancellable (404 / 409) are skipped, not failed
# --------------------------------------------------------

@test "process_run skips a run when the cancel request returns 404" {
  cancel_run() { echo -e "HTTP/2.0 404 Not Found\n\n{}"; }

  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "::warning::Run 123 could not be cancelled (HTTP 404)" ]]
  [[ ! "$output" =~ "Cancellation failed" ]]
  [ "$status" -eq 0 ]
}

@test "process_run skips a run when the cancel request returns 409" {
  cancel_run() { echo -e "HTTP/2.0 409 Conflict\n\n{}"; }

  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "::warning::Run 123 could not be cancelled (HTTP 409)" ]]
  [[ ! "$output" =~ "Cancellation failed" ]]
  [ "$status" -eq 0 ]
}

@test "process_run skips an old run when the regular and the force cancel return 409" {
  cancel_run() { echo -e "HTTP/2.0 409 Conflict\n\n{}"; }
  force_cancel_run() { echo -e "HTTP/2.0 409 Conflict\n\n{}"; }

  run process_run "123" $((24 * 3600))

  [[ "$output" =~ "::warning::Run 123 could not be cancelled (HTTP 409)" ]]
  [[ ! "$output" =~ "Cancellation failed" ]]
  [ "$status" -eq 0 ]
}

@test "process_run skips an old run when the force cancel returns 404" {
  cancel_run() { echo -e "HTTP/2.0 500 Internal Server Error\n\n{}"; }
  force_cancel_run() { echo -e "HTTP/2.0 404 Not Found\n\n{}"; }

  run process_run "123" $((24 * 3600))

  [[ "$output" =~ "::warning::Run 123 could not be cancelled (HTTP 404)" ]]
  [ "$status" -eq 0 ]
}

@test "process_run does not print the success line for a skipped run" {
  cancel_run() { echo -e "HTTP/2.0 409 Conflict\n\n{}"; }

  run process_run "123" $((3 * 3600))

  [[ ! "$output" =~ "Cancellation request accepted" ]]
}

@test "process_run still fails when the cancel request returns 403" {
  cancel_run() { echo -e "HTTP/2.0 403 Forbidden\n\n{}"; }

  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "Status code: 403" ]]
  [[ "$output" =~ "Cancellation failed for run 123" ]]
  [ "$status" -eq 1 ]
}

@test "process_run still fails when the cancel request returns 401" {
  cancel_run() { echo -e "HTTP/2.0 401 Unauthorized\n\n{}"; }

  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "Cancellation failed for run 123" ]]
  [ "$status" -eq 1 ]
}

# --------------------------------------------------------
# Dry run
# --------------------------------------------------------

@test "process_run in dry run only logs the run that would be cancelled" {
  record_calls
  export DRY_RUN=true

  run process_run "123" $((3 * 3600))

  [ "$status" -eq 0 ]
  [[ "$output" == "🧪 [dry-run] Would cancel run 123 (age=3h00m)" ]]
  [ ! -s "$CALL_LOG" ]
}

@test "process_run in dry run only logs the run that would be force-cancelled" {
  record_calls
  export DRY_RUN=true

  run process_run "123" $((24 * 3600))

  [ "$status" -eq 0 ]
  [[ "$output" == "🧪 [dry-run] Would force-cancel run 123 (age=24h00m)" ]]
  [ ! -s "$CALL_LOG" ]
}

@test "process_run in dry run does nothing for a run below the threshold" {
  record_calls
  export DRY_RUN=true

  run process_run "123" $((1 * 3600))

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALL_LOG" ]
}

@test "process_run in dry run succeeds even if the API would fail" {
  export DRY_RUN=true
  # the default mocks return 500 for run 456
  run process_run "456" $((3 * 3600))

  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Cancellation failed" ]]
}

@test "process_run cancels for real when DRY_RUN is false" {
  record_calls
  export DRY_RUN=false

  run process_run "123" $((3 * 3600))

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Cancelling run 123" ]]
  [ "$(cat "$CALL_LOG")" = "cancel_run 123" ]
}

@test "process_run cancels for real by default" {
  unset DRY_RUN
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  record_calls

  run process_run "123" $((3 * 3600))

  [[ "$output" =~ "Cancelling run 123" ]]
  [ "$(cat "$CALL_LOG")" = "cancel_run 123" ]
}

# --------------------------------------------------------
# Configurable force-cancel buffer (MAX_AGE_HOURS=2)
# --------------------------------------------------------

@test "process_run uses a 3 hour force-cancel buffer by default" {
  unset FORCE_BUFFER_HOURS
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  cancel_run() { echo "HTTP/2.0 202 Accepted"; }

  run process_run "123" $((5 * 3600))
  [[ "$output" =~ "Cancelling run 123" ]]

  run process_run "123" $((5 * 3600 + 1))
  [[ "$output" =~ "Force-cancelling run 123" ]]
}

@test "process_run force-cancels as soon as the age exceeds MAX_AGE_HOURS when the buffer is 0" {
  export FORCE_BUFFER_HOURS=0

  run process_run "123" $((2 * 3600 + 1))

  [[ "$output" =~ "Force-cancelling run 123" ]]
  [ "$status" -eq 0 ]
}

@test "process_run does nothing at exactly MAX_AGE_HOURS when the buffer is 0" {
  export FORCE_BUFFER_HOURS=0

  run process_run "123" $((2 * 3600))

  [ -z "$output" ]
}

@test "process_run uses standard cancel up to MAX_AGE_HOURS + buffer when the buffer is 10" {
  export FORCE_BUFFER_HOURS=10

  run process_run "123" $((12 * 3600))

  [[ "$output" =~ "Cancelling run 123" ]]
  [[ ! "$output" =~ "Force-cancelling" ]]
}

@test "process_run force-cancels just after MAX_AGE_HOURS + buffer when the buffer is 10" {
  export FORCE_BUFFER_HOURS=10

  run process_run "123" $((12 * 3600 + 1))

  [[ "$output" =~ "Force-cancelling run 123" ]]
}

@test "process_run dry run honours the force-cancel buffer" {
  export FORCE_BUFFER_HOURS=1
  export DRY_RUN=true

  run process_run "123" $((3 * 3600 + 1))

  [[ "$output" =~ "Would force-cancel run 123" ]]
}

# --------------------------------------------------------
# Outcome reported to the caller (PROCESS_RUN_OUTCOME)
# --------------------------------------------------------
# These tests call process_run without `run` so that the global is visible.

@test "process_run sets the outcome to cancelled after a 202" {
  process_run "123" $((3 * 3600)) > /dev/null

  [ "$PROCESS_RUN_OUTCOME" = "cancelled" ]
}

@test "process_run sets the outcome to cancelled after a force-cancel 202" {
  process_run "111" $((24 * 3600)) > /dev/null || true

  [ "$PROCESS_RUN_OUTCOME" = "cancelled" ]
}

@test "process_run sets the outcome to failed after a 500" {
  process_run "456" $((3 * 3600)) > /dev/null || true

  [ "$PROCESS_RUN_OUTCOME" = "failed" ]
}

@test "process_run sets the outcome to skipped after a 409" {
  cancel_run() { echo -e "HTTP/2.0 409 Conflict\n\n{}"; }

  process_run "123" $((3 * 3600)) > /dev/null

  [ "$PROCESS_RUN_OUTCOME" = "skipped" ]
}

@test "process_run sets the outcome to would-cancel in dry run" {
  export DRY_RUN=true

  process_run "123" $((3 * 3600)) > /dev/null

  [ "$PROCESS_RUN_OUTCOME" = "would-cancel" ]
}

@test "process_run sets the outcome to noop for a recent run" {
  PROCESS_RUN_OUTCOME="stale"

  process_run "123" $((1 * 3600)) > /dev/null

  [ "$PROCESS_RUN_OUTCOME" = "noop" ]
}

@test "process_run sets the outcome to noop for an empty run id" {
  PROCESS_RUN_OUTCOME="stale"

  process_run "" $((3 * 3600)) > /dev/null

  [ "$PROCESS_RUN_OUTCOME" = "noop" ]
}

# --------------------------------------------------------
# Delay between the cancel requests
# --------------------------------------------------------

# Record the waits instead of sleeping
record_sleeps() {
  mkdir -p "$BATS_TEST_DIRNAME/mocks"
  export SLEEP_LOG="$BATS_TEST_DIRNAME/mocks/sleep.log"
  : > "$SLEEP_LOG"
  sleep() { echo "$1" >> "$SLEEP_LOG"; }
}

@test "process_run does not wait before its first request" {
  record_sleeps
  record_calls
  CANCEL_DELAY_SECONDS=5

  process_run "123" $((3 * 3600)) >/dev/null

  [ ! -s "$SLEEP_LOG" ]
}

@test "process_run waits CANCEL_DELAY_SECONDS between the requests of two runs" {
  record_sleeps
  record_calls
  CANCEL_DELAY_SECONDS=5

  process_run "123" $((3 * 3600)) >/dev/null
  process_run "124" $((3 * 3600)) >/dev/null

  [ "$(cat "$SLEEP_LOG")" = "5" ]
  grep -q "cancel_run 124" "$CALL_LOG"
}

@test "process_run does not wait when CANCEL_DELAY_SECONDS is 0" {
  record_sleeps
  record_calls
  CANCEL_DELAY_SECONDS=0

  process_run "123" $((3 * 3600)) >/dev/null
  process_run "124" $((3 * 3600)) >/dev/null

  [ ! -s "$SLEEP_LOG" ]
}

@test "process_run waits between the cancel and the force-cancel requests of one run" {
  record_sleeps
  CANCEL_DELAY_SECONDS=4
  cancel_run() { echo "HTTP/2.0 409 Conflict"; }
  force_cancel_run() { echo "HTTP/2.0 202 Accepted"; }

  process_run "123" $((10 * 3600)) >/dev/null

  [ "$(cat "$SLEEP_LOG")" = "4" ]
}

@test "process_run does not wait when the run is too recent" {
  record_sleeps
  record_calls
  CANCEL_DELAY_SECONDS=5

  process_run "123" $((3 * 3600)) >/dev/null
  process_run "124" $((1 * 3600)) >/dev/null
  process_run "125" $((1 * 3600)) >/dev/null

  [ ! -s "$SLEEP_LOG" ]
}

@test "process_run does not wait for a run that is too recent after a request" {
  record_sleeps
  record_calls
  CANCEL_DELAY_SECONDS=5

  process_run "123" $((3 * 3600)) >/dev/null
  process_run "124" $((1 * 3600)) >/dev/null
  process_run "125" $((3 * 3600)) >/dev/null

  [ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 1 ]
}

@test "process_run does not wait in dry run" {
  record_sleeps
  record_calls
  CANCEL_DELAY_SECONDS=5
  DRY_RUN=true

  process_run "123" $((3 * 3600)) >/dev/null
  process_run "124" $((10 * 3600)) >/dev/null

  [ ! -s "$SLEEP_LOG" ]
  [ ! -s "$CALL_LOG" ]
}

@test "process_run waits after a failed request too" {
  record_sleeps
  CANCEL_DELAY_SECONDS=5
  cancel_run() { echo "HTTP/2.0 500 Internal Server Error"; }

  process_run "123" $((3 * 3600)) >/dev/null || true
  process_run "124" $((3 * 3600)) >/dev/null || true

  [ "$(cat "$SLEEP_LOG")" = "5" ]
}

