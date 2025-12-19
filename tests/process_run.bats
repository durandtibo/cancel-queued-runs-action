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
    run process_run "123" 3

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Cancelling run 123" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # Exit code should be 0 (success)
    [ "$status" -eq 0 ]
}

@test "process_run returns failure exit code for 500 response" {
    run process_run "456" 4

    [[ "$output" =~ "Cancelling run 456" ]]
    [[ "$output" =~ "Status code: 500" ]]
    [[ "$output" =~ "Cancellation failed for run 456" ]]

    # Exit code should be 1 (failure)
    [ "$status" -eq 1 ]
}

@test "process_run force cancels run older than MAX_AGE_HOURS + 3h with 202 response" {
    run process_run "111" 24

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Force-cancelling run 111" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # Exit code should be 0 (success)
    [ "$status" -eq 0 ]
}

@test "process_run does nothing if age_hours is below MAX_AGE_HOURS" {
    run process_run "789" 1

    # Should have no output (nothing happens)
    [ -z "$output" ]

    # Exit code should be 0 (success - nothing to do)
    [ "$status" -eq 0 ]
}

@test "process_run does nothing if run_id is empty" {
    run process_run "" 5

    # Should have no output (nothing happens)
    [ -z "$output" ]

    # Exit code should be 0 (success - nothing to do)
    [ "$status" -eq 0 ]
}