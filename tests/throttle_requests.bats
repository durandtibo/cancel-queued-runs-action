#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export SLEEP_LOG="$MOCK_DIR/sleep.log"
  : > "$SLEEP_LOG"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"

  sleep() { echo "$1" >> "$SLEEP_LOG"; }
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "throttle_requests does not wait before the first request" {
  CANCEL_DELAY_SECONDS=2

  throttle_requests

  [ ! -s "$SLEEP_LOG" ]
}

@test "throttle_requests waits before the second request" {
  CANCEL_DELAY_SECONDS=2

  throttle_requests
  throttle_requests

  [ "$(cat "$SLEEP_LOG")" = "2" ]
}

@test "throttle_requests waits before every request after the first one" {
  CANCEL_DELAY_SECONDS=3

  throttle_requests
  throttle_requests
  throttle_requests
  throttle_requests

  [ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 3 ]
}

@test "throttle_requests never waits when the delay is 0" {
  CANCEL_DELAY_SECONDS=0

  throttle_requests
  throttle_requests
  throttle_requests

  [ ! -s "$SLEEP_LOG" ]
}

@test "throttle_requests does not wait by default" {
  throttle_requests
  throttle_requests

  [ ! -s "$SLEEP_LOG" ]
}

@test "throttle_requests records that a request is sent" {
  [ "$REQUEST_SENT" = "false" ]

  throttle_requests

  [ "$REQUEST_SENT" = "true" ]
}

@test "throttle_requests waits again after the requests were reset" {
  CANCEL_DELAY_SECONDS=2

  throttle_requests
  reset_counters
  throttle_requests

  [ ! -s "$SLEEP_LOG" ]
}

@test "throttle_requests prints nothing" {
  CANCEL_DELAY_SECONDS=2
  throttle_requests

  out=$(throttle_requests 2>&1)

  [ -z "$out" ]
}
