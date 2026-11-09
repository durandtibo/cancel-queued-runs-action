#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

# --------------------------------------------------------
# Transient errors
# --------------------------------------------------------

@test "is_transient_error accepts HTTP 429" {
  run is_transient_error "gh: Too Many Requests (HTTP 429)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts HTTP 500" {
  run is_transient_error "gh: Server Error (HTTP 500)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts HTTP 502" {
  run is_transient_error "gh: Bad Gateway (HTTP 502)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts HTTP 503" {
  run is_transient_error "gh: Service Unavailable (HTTP 503)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts HTTP 504" {
  run is_transient_error "gh: Server Error (HTTP 504)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts the message that gh writes for a non-JSON error body" {
  run is_transient_error "HTTP 502: 502 Bad Gateway (https://api.github.com/repos/o/r/actions/runs?status=queued)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts an HTTP 403 that mentions a rate limit" {
  run is_transient_error "gh: API rate limit exceeded for user ID 1. (HTTP 403)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts an HTTP 403 from the secondary rate limit" {
  run is_transient_error "gh: You have exceeded a secondary rate limit. (HTTP 403)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts an HTTP 403 from the abuse detection" {
  run is_transient_error "gh: You have triggered an abuse detection mechanism. (HTTP 403)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error ignores the case of the rate limit message" {
  run is_transient_error "gh: API RATE LIMIT exceeded (HTTP 403)"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts a timeout" {
  run is_transient_error 'Get "https://api.github.com/repos/o/r/actions/runs": net/http: TLS handshake timeout'

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts a connection reset" {
  run is_transient_error "read tcp 10.0.0.1:443: connection reset by peer"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts an unexpected EOF" {
  run is_transient_error "Get https://api.github.com: unexpected EOF"

  [ "$status" -eq 0 ]
}

@test "is_transient_error accepts a message with the newlines of gh replaced by spaces" {
  run is_transient_error "gh: Server Error (HTTP 500)  "

  [ "$status" -eq 0 ]
}

# --------------------------------------------------------
# Errors that are not transient
# --------------------------------------------------------

@test "is_transient_error rejects HTTP 401" {
  run is_transient_error "gh: Bad credentials (HTTP 401)"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects an HTTP 403 without rate limit (missing permission)" {
  run is_transient_error "gh: Resource not accessible by integration (HTTP 403)"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects HTTP 404" {
  run is_transient_error "gh: Not Found (HTTP 404)"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects HTTP 422" {
  run is_transient_error "gh: Validation Failed (HTTP 422)"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects HTTP 501 (not implemented)" {
  run is_transient_error "gh: Not Implemented (HTTP 501)"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects a status that only starts like a transient one" {
  run is_transient_error "gh: Error (HTTP 5000)"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects a rate limit text without a 403" {
  run is_transient_error "gh: Not Found (HTTP 404) rate limit"

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects an empty message" {
  run is_transient_error ""

  [ "$status" -eq 1 ]
}

@test "is_transient_error rejects a call without argument" {
  run is_transient_error

  [ "$status" -eq 1 ]
}

@test "is_transient_error prints nothing" {
  run is_transient_error "gh: Server Error (HTTP 500)"

  [ -z "$output" ]
}
