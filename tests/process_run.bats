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
    output=$(process_run "123" 3 0)

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Cancelling run 123" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # failed counter should remain 0
    # The last line of output is the updated failed count
    failed=$(echo "$output" | tail -n1)
    [ "$failed" -eq 0 ]
}

@test "process_run increments failed counter for 500 response" {
    output=$(process_run "456" 4 0)

    [[ "$output" =~ "Cancelling run 456" ]]
    [[ "$output" =~ "Status code: 500" ]]
    [[ "$output" =~ "Cancellation failed for run 456" ]]

    # The last line of output is the updated failed count
    failed=$(echo "$output" | tail -n1)
    [ "$failed" -eq 1 ]
}

@test "process_run force cancels run older than MAX_AGE_HOURS + 3h with 202 response" {
    output=$(process_run "111" 24 0)

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Force-cancelling run 111" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # failed counter should remain 0
    # The last line of output is the updated failed count
    failed=$(echo "$output" | tail -n1)
    [ "$failed" -eq 0 ]
}

@test "process_run does nothing if age_hours is below MAX_AGE_HOURS" {
    output=$(process_run "789" 1 0)

    # failed counter should remain 0
    # The line of output is the updated failed count
    [ "$output" -eq 0 ]
}

@test "process_run does nothing if run_id is empty" {
    output=$(process_run "" 5 0)

    # failed counter should remain 0
    # The line of output is the updated failed count
    [ "$output" -eq 0 ]
}

@test "process_run does nothing if age_hours equals MAX_AGE_HOURS exactly" {
    output=$(process_run "789" 2 0)

    # failed counter should remain 0 (not > MAX_AGE_HOURS)
    # The line of output is the updated failed count
    [ "$output" -eq 0 ]
}

@test "process_run cancels if age_hours is exactly MAX_AGE_HOURS + 1" {
    output=$(process_run "123" 3 0)

    # Should cancel since 3 > 2
    [[ "$output" =~ "Cancelling run 123" ]]
    [[ "$output" =~ "Status code: 202" ]]

    failed=$(echo "$output" | tail -n1)
    [ "$failed" -eq 0 ]
}

@test "process_run force cancels if age_hours is exactly MAX_AGE_HOURS + 4" {
    output=$(process_run "111" 6 0)

    # Should force-cancel since 6 > (2 + 3)
    [[ "$output" =~ "Force-cancelling run 111" ]]
    [[ "$output" =~ "Status code: 202" ]]

    failed=$(echo "$output" | tail -n1)
    [ "$failed" -eq 0 ]
}
