#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "get_response_message prints the message of the JSON body" {
  run get_response_message $'HTTP/2.0 409 Conflict\r\nContent-Type: application/json\r\n\r\n{"message":"Cannot cancel"}'

  [ "$output" = "Cannot cancel" ]
}

@test "get_response_message prints nothing when the body has no message" {
  run get_response_message $'HTTP/2.0 409 Conflict\n\n{}'

  [ -z "$output" ]
}

@test "get_response_message prints nothing when the body is not JSON" {
  run get_response_message $'HTTP/2.0 409 Conflict\n\nnot json'

  [ -z "$output" ]
  [ "$status" -eq 0 ]
}

@test "get_response_message prints nothing for an empty response" {
  run get_response_message ""

  [ -z "$output" ]
  [ "$status" -eq 0 ]
}
