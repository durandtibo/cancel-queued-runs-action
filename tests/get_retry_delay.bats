#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  RETRY_BASE_DELAY=5

  # Fixed clock for the X-RateLimit-Reset computation
  date() { echo 1000; }
}

@test "get_retry_delay uses the Retry-After header" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\nRetry-After: 42\n\n{}')" 1)
  [ "$result" -eq 42 ]
}

@test "get_retry_delay reads headers case-insensitively" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\nretry-after: 17\n\n{}')" 1)
  [ "$result" -eq 17 ]
}

@test "get_retry_delay handles CRLF line endings" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\r\nRetry-After: 9\r\n\r\n{}')" 1)
  [ "$result" -eq 9 ]
}

@test "get_retry_delay prefers Retry-After over the reset header" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 403 Forbidden\nRetry-After: 7\nX-Ratelimit-Remaining: 0\nX-Ratelimit-Reset: 1500\n\n{}')" 1)
  [ "$result" -eq 7 ]
}

@test "get_retry_delay waits until the reset time when the quota is exhausted" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 403 Forbidden\nX-Ratelimit-Remaining: 0\nX-Ratelimit-Reset: 1030\n\n{}')" 1)
  # 30 seconds to the reset, plus one second of margin
  [ "$result" -eq 31 ]
}

@test "get_retry_delay ignores the reset time when quota remains" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\nX-Ratelimit-Remaining: 10\nX-Ratelimit-Reset: 5000\n\n{}')" 1)
  [ "$result" -eq 5 ]
}

@test "get_retry_delay returns at least 1 second when the reset time is in the past" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 403 Forbidden\nX-Ratelimit-Remaining: 0\nX-Ratelimit-Reset: 100\n\n{}')" 1)
  [ "$result" -eq 1 ]
}

@test "get_retry_delay returns at least 1 second for Retry-After: 0" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\nRetry-After: 0\n\n{}')" 1)
  [ "$result" -eq 1 ]
}

@test "get_retry_delay truncates a fractional Retry-After" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\nRetry-After: 2.7\n\n{}')" 1)
  [ "$result" -eq 2 ]
}

@test "get_retry_delay falls back to an exponential backoff" {
  response="$(printf 'HTTP/2.0 429 Too Many Requests\n\n{}')"

  [ "$(get_retry_delay "$response" 1)" -eq 5 ]
  [ "$(get_retry_delay "$response" 2)" -eq 10 ]
  [ "$(get_retry_delay "$response" 3)" -eq 20 ]
}

@test "get_retry_delay does not cap the delay" {
  result=$(get_retry_delay "$(printf 'HTTP/2.0 429 Too Many Requests\nRetry-After: 3600\n\n{}')" 1)
  [ "$result" -eq 3600 ]
}

# Recorded-style responses of gh api -i (CRLF line endings), see tests/fixtures
fixture() { cat "$BATS_TEST_DIRNAME/fixtures/$1"; }

@test "get_retry_delay reads the Retry-After header of a recorded secondary rate limit" {
  result=$(get_retry_delay "$(fixture response_403_secondary_rate_limit.http)" 1)
  [ "$result" -eq 30 ]
}

@test "get_retry_delay reads the Retry-After header of a recorded 429 response" {
  result=$(get_retry_delay "$(fixture response_429.http)" 1)
  [ "$result" -eq 60 ]
}

@test "get_retry_delay uses the reset time of a recorded exhausted primary rate limit" {
  # the clock is 1000 and the fixture resets at 1030: 30 seconds + 1
  result=$(get_retry_delay "$(fixture response_403_primary_rate_limit.http)" 1)
  [ "$result" -eq 31 ]
}

@test "get_retry_delay falls back to the backoff for a recorded response without delay" {
  result=$(get_retry_delay "$(fixture response_500.http)" 3)
  [ "$result" -eq 20 ]
}

@test "get_retry_delay does not use the reset time when the quota is not exhausted" {
  # 4986 requests remain: the reset header must be ignored
  result=$(get_retry_delay "$(fixture response_403_forbidden.http)" 1)
  [ "$result" -eq 5 ]
}
