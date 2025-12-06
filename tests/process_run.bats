#!/usr/bin/env bats

setup() {
    # Test directory for mocks/logs
    TEST_DIR="$BATS_TEST_DIRNAME"
    MOCK_DIR="$TEST_DIR/mocks"
    mkdir -p "$MOCK_DIR"
    export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
    echo -n > "$MOCK_GH_CALL_LOG"

    # Globals used by process_run
    export MAX_AGE_HOURS=2
    failed=0

    # Mock functions
    force_cancel_run() {
        local run_id="$1"
        case "$run_id" in
            "123") echo -e "HTTP/2.0 202 Accepted\nContent-Type: application/json\n\n{}" ;;
            "456") echo -e "HTTP/2.0 500 Internal Server Error\nContent-Type: application/json\n\n{\"message\":\"error\"}" ;;
            *) echo -e "HTTP/2.0 202 Accepted\nContent-Type: application/json\n\n{}" ;;
        esac
    }

    # Source the script under test
    source "$BATS_TEST_DIRNAME/../scripts/cancel2.sh"
}

@test "process_run cancels run older than MAX_AGE_HOURS with 202 response" {
    run process_run "123" 3

    # Check output contains cancellation info and log_status
    [[ "$output" =~ "Cancelling run 123" ]]
    [[ "$output" =~ "Status code: 202" ]]

    # failed counter should remain 0
    [ "$failed" -eq 0 ]
}

@test "process_run increments failed counter for 500 response" {
    run process_run "456" 4

    [[ "$output" =~ "Cancelling run 456" ]]
    [[ "$output" =~ "Status code: 500" ]]
    [[ "$output" =~ "⚠️ Cancellation failed for run 456" ]]

    # failed counter should be incremented
    [ "$failed" -eq 1 ]
}

@test "process_run does nothing if age_hours is below MAX_AGE_HOURS" {
    run process_run "789" 1

    # Output should be empty
    [ -z "$output" ]

    # failed counter should remain 0
    [ "$failed" -eq 0 ]
}

@test "process_run does nothing if run_id is empty" {
    run process_run "" 5

    # Output should be empty
    [ -z "$output" ]

    # failed counter should remain 0
    [ "$failed" -eq 0 ]
}
