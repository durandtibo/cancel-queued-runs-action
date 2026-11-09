#!/usr/bin/env bats

setup() {
  # Log file for calls
  # Use absolute paths for mocks/logs (macOS BATS can change CWD)
  TEST_DIR="$BATS_TEST_DIRNAME"
  MOCK_DIR="$TEST_DIR/mocks"
  mkdir -p "$MOCK_DIR"
  export LOG_FILE="$MOCK_DIR/calls.log"

  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"

  # -------------------------
  # Mock compute_age_seconds
  # -------------------------
  compute_age_seconds() {
    # Always return a fixed age (5 hours) for deterministic tests
    echo 18000
  }

  # -------------------------
  # Mock process_run
  # Controlled by MOCK_RESULT
  # -------------------------
  process_run() {
    echo "process_run $1 $2" >> "$LOG_FILE"

    if [[ "$MOCK_RESULT" == "fail" ]]; then
      return 1
    else
      return 0
    fi
  }

  export MOCK_RESULT="success"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# --------------------------------------------------------
# Tests
# --------------------------------------------------------

@test "process_all_runs returns 0 when all runs succeed" {
  runs_stream=$(
    printf '%s\n' \
      '{"id": 101, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 202, "queued_at": "2025-01-01T02:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  # Exit code should be 0 (success)
  [ "$status" -eq 0 ]

  # Output should NOT contain error message
  [[ ! "$output" =~ "Error:" ]]

  grep -q "process_run 101 18000" "$LOG_FILE"
  grep -q "process_run 202 18000" "$LOG_FILE"
}

@test "process_all_runs returns 1 when process_run fails" {
  export MOCK_RESULT="fail"

  runs_stream=$(
    printf '%s\n' \
      '{"id": 111, "queued_at": "2025-02-01T03:00:00Z"}' \
      '{"id": 222, "queued_at": "2025-02-01T04:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  # Exit code should be 1 (failure)
  [ "$status" -eq 1 ]

  # Output should contain error message with count
  [[ "$output" =~ "Error: 2 run(s) failed to cancel" ]]

  grep -q "process_run 111 18000" "$LOG_FILE"
  grep -q "process_run 222 18000" "$LOG_FILE"
}

@test "process_all_runs skips runs with missing fields" {
  runs_stream=$(
    printf '%s\n' \
      '{"id": 333, "queued_at": "2025-03-01T05:00:00Z"}' \
      '{"id": "", "queued_at": "2025-03-01T06:00:00Z"}' \
      '{"id": 444, "queued_at": ""}' \
      '{"id": 555, "queued_at": "2025-03-01T07:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  # Exit code should be 0 (success)
  [ "$status" -eq 0 ]

  grep -q "process_run 333 18000" "$LOG_FILE"
  grep -q "process_run 555 18000" "$LOG_FILE"

  # Ensure skipped runs do NOT appear
  if grep -q "process_run 444" "$LOG_FILE"; then false; fi
  if grep -q 'process_run ""' "$LOG_FILE"; then false; fi
}

@test "process_all_runs prints queue age" {
  runs_stream='{"id": 999, "queued_at": "2025-03-10T09:00:00Z"}'

  run process_all_runs "$runs_stream"

  [[ "$output" =~ "Run 999 has been queued for 5h00m." ]]
}

@test "process_all_runs counts partial failures correctly" {
  # Create a mock that fails on second call only
  process_run() {
    echo "process_run $1 $2" >> "$LOG_FILE"

    if [[ "$1" == "222" ]]; then
      return 1
    else
      return 0
    fi
  }

  runs_stream=$(
    printf '%s\n' \
      '{"id": 111, "queued_at": "2025-02-01T03:00:00Z"}' \
      '{"id": 222, "queued_at": "2025-02-01T04:00:00Z"}' \
      '{"id": 333, "queued_at": "2025-02-01T05:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  # Exit code should be 1 (failure)
  [ "$status" -eq 1 ]

  # Output should contain error message showing 1 failure
  [[ "$output" =~ "Error: 1 run(s) failed to cancel" ]]
}
