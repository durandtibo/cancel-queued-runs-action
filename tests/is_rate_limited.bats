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

# Recorded-style responses of gh api -i (CRLF line endings), see tests/fixtures
fixture() { cat "$BATS_TEST_DIRNAME/fixtures/$1"; }

@test "is_rate_limited is true for a recorded 429 response" {
  run is_rate_limited "$(fixture response_429.http)"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is true for a recorded secondary rate limit (403 with Retry-After)" {
  run is_rate_limited "$(fixture response_403_secondary_rate_limit.http)"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is true for a recorded exhausted primary rate limit (403)" {
  run is_rate_limited "$(fixture response_403_primary_rate_limit.http)"
  [ "$status" -eq 0 ]
}

@test "is_rate_limited is false for a recorded 403 for a missing permission" {
  # it has X-Ratelimit-Remaining: 4986, which is not an exhausted quota
  run is_rate_limited "$(fixture response_403_forbidden.http)"
  [ "$status" -eq 1 ]
}

@test "is_rate_limited is false for the other recorded responses" {
  for name in response_202.http response_202_http11.http response_404.http response_409.http response_500.http; do
    run is_rate_limited "$(fixture "$name")"
    [ "$status" -eq 1 ] || { echo "rate limited: $name"; false; }
  done
}
