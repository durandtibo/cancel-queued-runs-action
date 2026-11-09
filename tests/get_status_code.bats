#!/usr/bin/env bats

setup() {
  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "get_status_code extracts 202 from HTTP/1.1 response" {
  response="HTTP/1.1 202 Accepted
Content-Type: application/json
{}"

  result=$(get_status_code "$response")
  [ "$result" -eq 202 ]
}

@test "get_status_code extracts 500 from HTTP/1.1 response" {
  response="HTTP/1.1 500 Internal Server Error
Content-Type: application/json
{}"

  result=$(get_status_code "$response")
  [ "$result" -eq 500 ]
}

@test "get_status_code extracts 200 from HTTP/2 response" {
  response="HTTP/2 200 OK
Content-Type: application/json
{}"

  result=$(get_status_code "$response")
  [ "$result" -eq 200 ]
}

@test "get_status_code returns empty for empty response" {
  response=""
  result=$(get_status_code "$response")
  [ -z "$result" ]
}

# Recorded-style responses of gh api -i (CRLF line endings), see tests/fixtures
fixture() { cat "$BATS_TEST_DIRNAME/fixtures/$1"; }

@test "get_status_code reads 202 from a complete response with CRLF line endings" {
  [ "$(get_status_code "$(fixture response_202.http)")" = "202" ]
}

@test "get_status_code reads the code of an HTTP/1.1 status line" {
  [ "$(get_status_code "$(fixture response_202_http11.http)")" = "202" ]
}

@test "get_status_code reads 404 from a complete response" {
  [ "$(get_status_code "$(fixture response_404.http)")" = "404" ]
}

@test "get_status_code reads 409 from a complete response" {
  [ "$(get_status_code "$(fixture response_409.http)")" = "409" ]
}

@test "get_status_code reads 429 from a complete response" {
  [ "$(get_status_code "$(fixture response_429.http)")" = "429" ]
}

@test "get_status_code reads 500 from a complete response" {
  [ "$(get_status_code "$(fixture response_500.http)")" = "500" ]
}

@test "get_status_code reads 403 from the three kinds of 403 response" {
  [ "$(get_status_code "$(fixture response_403_forbidden.http)")" = "403" ]
  [ "$(get_status_code "$(fixture response_403_secondary_rate_limit.http)")" = "403" ]
  [ "$(get_status_code "$(fixture response_403_primary_rate_limit.http)")" = "403" ]
}

@test "get_status_code does not leave a carriage return after the code" {
  # a status line without reason phrase ends right after the code
  [ "$(get_status_code "$(printf 'HTTP/2.0 202\r\n\r\n{}')")" = "202" ]
}
