#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "is_rate_limited is true for HTTP 429" {
  run is_rate_limited "$(printf 'HTTP/2.0 429 Too Many Requests\n\n{}')"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is true for HTTP 403 with a Retry-After header" {
  run is_rate_limited "$(printf 'HTTP/2.0 403 Forbidden\nRetry-After: 60\n\n{}')"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is true for HTTP 403 with an exhausted quota" {
  run is_rate_limited "$(printf 'HTTP/2.0 403 Forbidden\nX-Ratelimit-Remaining: 0\nX-Ratelimit-Reset: 1700000000\n\n{}')"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited handles CRLF line endings in headers" {
  run is_rate_limited "$(printf 'HTTP/2.0 403 Forbidden\r\nX-Ratelimit-Remaining: 0\r\n\r\n{}')"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is true for HTTP 403 with a secondary rate limit message" {
  run is_rate_limited "$(printf 'HTTP/2.0 403 Forbidden\n\n{"message":"You have exceeded a secondary rate limit."}')"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is false for a plain 403 permission error" {
  run is_rate_limited "$(printf 'HTTP/2.0 403 Forbidden\nX-Ratelimit-Remaining: 4999\n\n{"message":"Resource not accessible by integration"}')"
  [ "$status" -eq 1 ]
}

@test "is_rate_limited is false for 403 with remaining quota starting with 0-like digits" {
  run is_rate_limited "$(printf 'HTTP/2.0 403 Forbidden\nX-Ratelimit-Remaining: 0123\n\n{}')"
  [ "$status" -eq 1 ]
}

@test "is_rate_limited is false for 202" {
  run is_rate_limited "$(printf 'HTTP/2.0 202 Accepted\n\n{}')"
  [ "$status" -eq 1 ]
}

@test "is_rate_limited is false for 500 even if the body mentions a rate limit" {
  run is_rate_limited "$(printf 'HTTP/2.0 500 Internal Server Error\n\n{"message":"rate limit"}')"
  [ "$status" -eq 1 ]
}

@test "is_rate_limited is false for 409" {
  run is_rate_limited "$(printf 'HTTP/2.0 409 Conflict\n\n{}')"
  [ "$status" -eq 1 ]
}

@test "is_rate_limited is false for an empty response" {
  run is_rate_limited ""
  [ "$status" -eq 1 ]
}
