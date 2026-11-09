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
