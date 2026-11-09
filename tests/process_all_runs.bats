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
  [[ ! "$output" =~ "Error:" ]] || false

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
  [[ "$output" =~ "Error: 2 run(s) failed to cancel" ]] || false

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

  [[ "$output" =~ "Run 999 is 5h00m old." ]] || false
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
  [[ "$output" =~ "Error: 1 run(s) failed to cancel" ]] || false
}

@test "process_all_runs counts a run with an invalid timestamp as a failure" {
  compute_age_seconds() {
    if [[ "$1" == "garbage" ]]; then
      echo "::error::Invalid timestamp 'garbage'" >&2
      return 1
    fi
    echo 18000
  }

  runs_stream=$(
    printf '%s\n' \
      '{"id": 111, "queued_at": "2025-02-01T03:00:00Z"}' \
      '{"id": 222, "queued_at": "garbage"}'
  )

  run process_all_runs "$runs_stream"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Skipping run 222: cannot compute its age from 'garbage'" ]] || false
  [[ "$output" =~ "Error: 1 run(s) failed to cancel" ]] || false
}

@test "process_all_runs keeps processing the other runs after an invalid timestamp" {
  compute_age_seconds() {
    if [[ "$1" == "garbage" ]]; then
      return 1
    fi
    echo 18000
  }

  runs_stream=$(
    printf '%s\n' \
      '{"id": 111, "queued_at": "2025-02-01T03:00:00Z"}' \
      '{"id": 222, "queued_at": "garbage"}' \
      '{"id": 333, "queued_at": "2025-02-01T05:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  [ "$status" -eq 1 ]
  grep -q "process_run 111 18000" "$LOG_FILE"
  grep -q "process_run 333 18000" "$LOG_FILE"
  if grep -q "process_run 222" "$LOG_FILE"; then false; fi
}

@test "process_all_runs calls jq once whatever the number of runs" {
  real_jq=$(command -v jq)
  export JQ_CALL_LOG="$MOCK_DIR/jq_calls.log"
  : > "$JQ_CALL_LOG"
  cat > "$MOCK_DIR/jq" << MOCK
#!/usr/bin/env bash
echo call >> "$JQ_CALL_LOG"
exec "$real_jq" "\$@"
MOCK
  chmod +x "$MOCK_DIR/jq"
  PATH="$MOCK_DIR:$PATH"

  runs_stream=$(
    printf '%s\n' \
      '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "queued_at": "2025-01-01T02:00:00Z"}' \
      '{"id": 3, "queued_at": "2025-01-01T03:00:00Z"}' \
      '{"id": 4, "queued_at": "2025-01-01T04:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$JQ_CALL_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(grep -c '^process_run ' "$LOG_FILE")" -eq 4 ]
}

@test "process_all_runs skips runs whose fields are null or missing" {
  runs_stream=$(
    printf '%s\n' \
      '{"id": null, "queued_at": "2025-03-01T05:00:00Z"}' \
      '{"queued_at": "2025-03-01T05:00:00Z"}' \
      '{"id": 666, "queued_at": null}' \
      '{"id": 777}' \
      '{"id": 888, "queued_at": "2025-03-01T07:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^process_run ' "$LOG_FILE")" -eq 1 ]
  grep -q "process_run 888 18000" "$LOG_FILE"
}

@test "process_all_runs does not shift fields when the id is empty" {
  runs_stream=$(
    printf '%s\n' \
      '{"id": "", "queued_at": "2025-03-01T06:00:00Z"}' \
      '{"id": 555, "queued_at": "2025-03-01T07:00:00Z"}'
  )

  run process_all_runs "$runs_stream"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^process_run ' "$LOG_FILE")" -eq 1 ]
  grep -q "process_run 555 18000" "$LOG_FILE"
}

@test "process_all_runs does nothing with an empty stream" {
  run process_all_runs ""

  [ "$status" -eq 0 ]
  [ ! -s "$LOG_FILE" ]
}

@test "process_all_runs fails with an error when the stream is not valid JSON" {
  run process_all_runs "this is not json"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Cannot parse the list of runs" ]] || false
  [ ! -s "$LOG_FILE" ]
}

@test "process_all_runs counts the runs as failed when the stream is not valid JSON" {
  status=0
  process_all_runs "this is not json" > /dev/null 2>&1 || status=$?

  [ "$status" -eq 1 ]
  [ "$FAILED_COUNT" -eq 1 ]
  [ "$CANCELLED_COUNT" -eq 0 ]
}

@test "process_all_runs counts every line of an invalid stream as a failed run" {
  status=0
  process_all_runs "$(printf '%s\n' '{"id": 1,' '{"id": 2,' 'garbage')" > /dev/null 2>&1 || status=$?

  [ "$status" -eq 1 ]
  [ "$FAILED_COUNT" -eq 3 ]
}

@test "process_all_runs processes every run even if process_run reads stdin" {
  process_run() {
    echo "process_run $1 $2" >> "$LOG_FILE"
    cat > /dev/null
    return 0
  }

  runs_stream=$(
    printf '%s\n' \
      '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "queued_at": "2025-01-01T02:00:00Z"}' \
      '{"id": 3, "queued_at": "2025-01-01T03:00:00Z"}'
  )

  # stdin is /dev/null: only the runs read from the stream must be seen
  run process_all_runs "$runs_stream" < /dev/null

  [ "$status" -eq 0 ]
  [ "$(grep -c '^process_run ' "$LOG_FILE")" -eq 3 ]
}

# --------------------------------------------------------
# Counters
# --------------------------------------------------------

# process_run mock that sets the outcome according to the run id:
# 1xx cancelled, 2xx skipped, 3xx would-cancel, 4xx noop, 5xx failed
outcome_process_run() {
  echo "process_run $1 $2" >> "$LOG_FILE"
  case "$1" in
    1*) PROCESS_RUN_OUTCOME="cancelled" ;;
    2*) PROCESS_RUN_OUTCOME="skipped" ;;
    3*) PROCESS_RUN_OUTCOME="would-cancel" ;;
    4*) PROCESS_RUN_OUTCOME="noop" ;;
    5*) PROCESS_RUN_OUTCOME="failed"; return 1 ;;
  esac
  return 0
}

@test "process_all_runs counts each outcome" {
  process_run() { outcome_process_run "$@"; }

  runs_stream=$(
    printf '%s\n' \
      '{"id": 101, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 102, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 201, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 301, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 302, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 303, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 401, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 501, "queued_at": "2025-01-01T01:00:00Z"}'
  )

  process_all_runs "$runs_stream" > /dev/null || true

  [ "$CANCELLED_COUNT" -eq 2 ]
  [ "$SKIPPED_COUNT" -eq 1 ]
  [ "$WOULD_CANCEL_COUNT" -eq 3 ]
  [ "$FAILED_COUNT" -eq 1 ]
}

@test "process_all_runs does not count runs that need no action" {
  process_run() { outcome_process_run "$@"; }

  process_all_runs '{"id": 401, "queued_at": "2025-01-01T01:00:00Z"}' > /dev/null

  [ "$CANCELLED_COUNT" -eq 0 ]
  [ "$SKIPPED_COUNT" -eq 0 ]
  [ "$WOULD_CANCEL_COUNT" -eq 0 ]
  [ "$FAILED_COUNT" -eq 0 ]
}

@test "process_all_runs counts a run with an invalid timestamp as failed" {
  process_run() { outcome_process_run "$@"; }
  compute_age_seconds() { return 1; }

  process_all_runs '{"id": 101, "queued_at": "garbage"}' > /dev/null 2>&1 || true

  [ "$FAILED_COUNT" -eq 1 ]
  [ "$CANCELLED_COUNT" -eq 0 ]
}

@test "process_all_runs does not count skipped invalid entries" {
  process_run() { outcome_process_run "$@"; }

  process_all_runs '{"id": "", "queued_at": "2025-01-01T01:00:00Z"}' > /dev/null

  [ "$CANCELLED_COUNT" -eq 0 ]
  [ "$FAILED_COUNT" -eq 0 ]
}

@test "process_all_runs resets the counters at each call" {
  process_run() { outcome_process_run "$@"; }
  CANCELLED_COUNT=7
  FAILED_COUNT=7

  process_all_runs '{"id": 101, "queued_at": "2025-01-01T01:00:00Z"}' > /dev/null

  [ "$CANCELLED_COUNT" -eq 1 ]
  [ "$FAILED_COUNT" -eq 0 ]
}

@test "process_all_runs reports the number of failures in the error message" {
  process_run() { outcome_process_run "$@"; }

  run process_all_runs "$(printf '%s\n' \
    '{"id": 501, "queued_at": "2025-01-01T01:00:00Z"}' \
    '{"id": 502, "queued_at": "2025-01-01T01:00:00Z"}')"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Error: 2 run(s) failed to cancel" ]] || false
}

# --------------------------------------------------------
# Runs recorded for the summary
# --------------------------------------------------------

# process_run that sets the outcome according to the run id
mock_outcomes() {
  process_run() {
    case "$1" in
    1) PROCESS_RUN_OUTCOME="cancelled" ;;
    2) PROCESS_RUN_OUTCOME="skipped" ;;
    3) PROCESS_RUN_OUTCOME="would-cancel" ;;
    4) PROCESS_RUN_OUTCOME="noop" ;;
    5) PROCESS_RUN_OUTCOME="failed"; return 1 ;;
    esac
    return 0
  }
}

@test "process_all_runs records the cancelled, skipped, would-cancel and failed runs" {
  mock_outcomes
  runs_stream=$(
    printf '%s\n' \
      '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 3, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 5, "queued_at": "2025-01-01T01:00:00Z"}'
  )

  process_all_runs "$runs_stream" >/dev/null || true

  printf '%s' "$RUN_RECORDS" | grep -qx "1|5h00m|cancelled"
  printf '%s' "$RUN_RECORDS" | grep -qx "2|5h00m|skipped"
  printf '%s' "$RUN_RECORDS" | grep -qx "3|5h00m|would-cancel"
  printf '%s' "$RUN_RECORDS" | grep -qx "5|5h00m|failed"
}

@test "process_all_runs does not record the runs that were left alone" {
  mock_outcomes
  runs_stream='{"id": 4, "queued_at": "2025-01-01T01:00:00Z"}'

  process_all_runs "$runs_stream" >/dev/null

  [ -z "$RUN_RECORDS" ]
}

@test "process_all_runs does not record a run when process_run sets no outcome" {
  runs_stream='{"id": 101, "queued_at": "2025-01-01T01:00:00Z"}'

  process_all_runs "$runs_stream" >/dev/null

  [ -z "$RUN_RECORDS" ]
}

@test "process_all_runs records a run with an invalid timestamp as failed" {
  compute_age_seconds() { return 1; }
  runs_stream='{"id": 77, "queued_at": "garbage"}'

  process_all_runs "$runs_stream" >/dev/null 2>&1 || true

  printf '%s' "$RUN_RECORDS" | grep -qx "77|unknown|failed"
}

@test "process_all_runs forgets the records of a previous call" {
  mock_outcomes
  record_run 999 1h00m cancelled
  runs_stream='{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}'

  process_all_runs "$runs_stream" >/dev/null

  [ -z "$(printf '%s' "$RUN_RECORDS" | grep '^999|' || true)" ]
  printf '%s' "$RUN_RECORDS" | grep -qx "1|5h00m|cancelled"
}


# --------------------------------------------------------
# Current time
# --------------------------------------------------------

# Replaces compute_age_seconds by a function that logs the timestamps it gets,
# and date by one that answers a different time at every call
mock_clock() {
  mkdir -p "$MOCK_DIR"
  AGE_LOG="$MOCK_DIR/age_calls.log"
  : > "$AGE_LOG"
  echo 0 > "$MOCK_DIR/clock"
  compute_age_seconds() {
    echo "$1 $2" >> "$AGE_LOG"
    echo 18000
  }
  date() {
    local n
    n=$(cat "$MOCK_DIR/clock")
    echo $((n + 1)) > "$MOCK_DIR/clock"
    printf '2030-01-01T00:00:%02dZ\n' "$n"
  }
}

@test "process_all_runs compares all the runs with the same current time" {
  mock_clock
  runs_stream=$(
    printf '%s\n' \
      '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "queued_at": "2025-01-01T02:00:00Z"}' \
      '{"id": 3, "queued_at": "2025-01-01T03:00:00Z"}'
  )

  process_all_runs "$runs_stream" > /dev/null

  [ "$(cut -d' ' -f2 "$AGE_LOG" | sort -u | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$AGE_LOG" | tr -d ' ')" -eq 3 ]
}

@test "process_all_runs reads the current time once for all the runs" {
  mock_clock
  runs_stream=$(
    printf '%s\n' \
      '{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}' \
      '{"id": 2, "queued_at": "2025-01-01T02:00:00Z"}'
  )

  process_all_runs "$runs_stream" > /dev/null

  [ "$(cat "$MOCK_DIR/clock")" -eq 1 ]
}

@test "process_all_runs gives the current time in the format of the GitHub API" {
  mock_clock
  runs_stream='{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}'

  process_all_runs "$runs_stream" > /dev/null

  [ "$(cut -d' ' -f2 "$AGE_LOG")" = "2030-01-01T00:00:00Z" ]
}

@test "process_all_runs reads the current time again at every call" {
  mock_clock
  runs_stream='{"id": 1, "queued_at": "2025-01-01T01:00:00Z"}'

  process_all_runs "$runs_stream" > /dev/null
  process_all_runs "$runs_stream" > /dev/null

  [ "$(cut -d' ' -f2 "$AGE_LOG" | sort -u | wc -l | tr -d ' ')" -eq 2 ]
}
