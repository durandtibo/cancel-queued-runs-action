#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export CALL_LOG="$MOCK_DIR/calls.log"
  export SLEEP_LOG="$MOCK_DIR/sleeps.log"
  : > "$CALL_LOG"
  : > "$SLEEP_LOG"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  MAX_RETRIES=3
  RETRY_BASE_DELAY=5
  RETRY_MAX_DELAY=60

  # Never really sleep: record the requested delay
  sleep() { echo "$1" >> "$SLEEP_LOG"; }

  # Mock post_run_endpoint: answers with the responses of $MOCK_RESPONSES
  # (one per call, separated by "|"), the last one being repeated.
  # "R" stands for a rate limited response, "ROK" for 202, "E500" for 500, "F403" for a plain 403.
  post_run_endpoint() {
    echo "$1 $2" >> "$CALL_LOG"
    local n
    n=$(wc -l < "$CALL_LOG" | tr -d ' ')
    local IFS='|'
    local -a seq=($MOCK_RESPONSES)
    local idx=$((n - 1))
    if [ "$idx" -ge "${#seq[@]}" ]; then idx=$((${#seq[@]} - 1)); fi
    case "${seq[$idx]}" in
      R) printf 'HTTP/2.0 429 Too Many Requests\n\n{}\n' ;;
      R10) printf 'HTTP/2.0 429 Too Many Requests\nRetry-After: 10\n\n{}\n' ;;
      R300) printf 'HTTP/2.0 429 Too Many Requests\nRetry-After: 300\n\n{}\n' ;;
      ROK) printf 'HTTP/2.0 202 Accepted\n\n{}\n' ;;
      E500) printf 'HTTP/2.0 500 Internal Server Error\n\n{}\n' ;;
      F403) printf 'HTTP/2.0 403 Forbidden\n\n{"message":"Resource not accessible"}\n' ;;
      EMPTY) ;;
    esac
  }
}

teardown() {
  rm -rf "$MOCK_DIR"
}

calls() { wc -l < "$CALL_LOG" | tr -d ' '; }
sleeps() { wc -l < "$SLEEP_LOG" | tr -d ' '; }

@test "post_run_endpoint_with_retry does not retry a successful request" {
  export MOCK_RESPONSES="ROK"

  run post_run_endpoint_with_retry 123 cancel

  [ "$status" -eq 0 ]
  [[ "$output" =~ "202 Accepted" ]]
  [ "$(calls)" -eq 1 ]
  [ "$(sleeps)" -eq 0 ]
}

@test "post_run_endpoint_with_retry passes the run id and the action" {
  export MOCK_RESPONSES="ROK"

  run post_run_endpoint_with_retry 123 force-cancel

  [ "$(cat "$CALL_LOG")" = "123 force-cancel" ]
}

@test "post_run_endpoint_with_retry retries a rate limited request until it succeeds" {
  export MOCK_RESPONSES="R|R|ROK"

  run post_run_endpoint_with_retry 123 cancel

  [ "$status" -eq 0 ]
  [[ "$output" =~ "202 Accepted" ]]
  [ "$(calls)" -eq 3 ]
  # Exponential backoff: 5s then 10s
  [ "$(cat "$SLEEP_LOG" | tr '\n' ' ')" = "5 10 " ]
}

@test "post_run_endpoint_with_retry waits for the Retry-After delay" {
  export MOCK_RESPONSES="R10|ROK"

  run post_run_endpoint_with_retry 123 cancel

  [ "$(cat "$SLEEP_LOG")" = "10" ]
}

@test "post_run_endpoint_with_retry warns before retrying" {
  export MOCK_RESPONSES="R10|ROK"

  run post_run_endpoint_with_retry 123 cancel

  [[ "$output" =~ "::warning::Rate limited on run 123 (cancel), retrying in 10s (retry 1/3)" ]]
}

@test "post_run_endpoint_with_retry gives up after MAX_RETRIES retries" {
  export MOCK_RESPONSES="R"

  run post_run_endpoint_with_retry 123 cancel

  [ "$status" -eq 0 ]
  # 1 initial attempt + 3 retries
  [ "$(calls)" -eq 4 ]
  [ "$(sleeps)" -eq 3 ]
  [[ "$output" =~ "giving up" ]]
  # the last (rate limited) response is returned to the caller
  [[ "$output" =~ "429 Too Many Requests" ]]
}

@test "post_run_endpoint_with_retry does not retry when MAX_RETRIES is 0" {
  export MOCK_RESPONSES="R"
  MAX_RETRIES=0

  run post_run_endpoint_with_retry 123 cancel

  [ "$(calls)" -eq 1 ]
  [ "$(sleeps)" -eq 0 ]
  [[ "$output" =~ "429 Too Many Requests" ]]
}

@test "post_run_endpoint_with_retry does not wait longer than RETRY_MAX_DELAY" {
  export MOCK_RESPONSES="R300"

  run post_run_endpoint_with_retry 123 cancel

  [ "$(calls)" -eq 1 ]
  [ "$(sleeps)" -eq 0 ]
  [[ "$output" =~ "giving up" ]]
}

@test "post_run_endpoint_with_retry waits exactly RETRY_MAX_DELAY if required" {
  export MOCK_RESPONSES="R10|ROK"
  RETRY_MAX_DELAY=10

  run post_run_endpoint_with_retry 123 cancel

  [ "$(cat "$SLEEP_LOG")" = "10" ]
}

@test "post_run_endpoint_with_retry does not retry a plain 403" {
  export MOCK_RESPONSES="F403"

  run post_run_endpoint_with_retry 123 cancel

  [ "$(calls)" -eq 1 ]
  [ "$(sleeps)" -eq 0 ]
  [[ "$output" =~ "403 Forbidden" ]]
}

@test "post_run_endpoint_with_retry does not retry a 500" {
  export MOCK_RESPONSES="E500"

  run post_run_endpoint_with_retry 123 cancel

  [ "$(calls)" -eq 1 ]
  [ "$(sleeps)" -eq 0 ]
}

@test "post_run_endpoint_with_retry does not retry an empty response" {
  export MOCK_RESPONSES="EMPTY"

  run post_run_endpoint_with_retry 123 cancel

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(calls)" -eq 1 ]
}
