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
