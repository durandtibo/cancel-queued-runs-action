#!/usr/bin/env bats

setup() {
  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

#----------------------------
# Test 202 status
#----------------------------
@test "log_status prints accepted message for 202" {
  run log_status 202 12345

  # Function should succeed
  [ "$status" -eq 0 ]

  # Output contains the accepted message
  [[ "$output" == "✅ Status code: 202 - Cancellation request accepted for run 12345" ]]
}

#----------------------------
# Test 500 status
#----------------------------
@test "log_status prints internal error for 500" {
  run log_status 500 67890

  [ "$status" -eq 0 ]
  [[ "$output" == "❌ Status code: 500 - Internal error for run 67890" ]]
}

#----------------------------
# Test unknown status
#----------------------------
@test "log_status prints generic error for unknown status" {
  run log_status 404 99999

  [ "$status" -eq 0 ]
  [[ "$output" == "❌ Status code: 404 for run 99999" ]]
}

#----------------------------
# Test empty status
#----------------------------
@test "log_status handles empty status gracefully" {
  run log_status "" 55555

  [ "$status" -eq 0 ]
  [[ "$output" == "❌ Status code:  for run 55555" ]]
}

#----------------------------
# Test empty run ID
#----------------------------
@test "log_status handles empty run ID gracefully" {
  run log_status 202 ""

  [ "$status" -eq 0 ]
  [[ "$output" == "✅ Status code: 202 - Cancellation request accepted for run " ]]
}
