#!/usr/bin/env bats

# Load the function under test
setup() {
  # Absolute path to the script defining to_unix_ts
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

#----------------------------
# Test valid timestamps
#----------------------------
@test "to_unix_ts converts a known ISO 8601 timestamp to correct Unix timestamp" {
  # Example timestamp: 2025-01-15T10:30:00Z
  # Known Unix timestamp for this date: 1736987400 (UTC)
  result=$(to_unix_ts "2025-01-15T10:30:00Z")

  # Ensure it is numeric
  [[ "$result" =~ ^[0-9]+$ ]]

  # For portability, test approximate value
  # Convert back to ISO string via date
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS date
    iso=$(date -u -r "$result" +"%Y-%m-%dT%H:%M:%SZ")
  else
    # Linux date
    iso=$(date -u -d "@$result" +"%Y-%m-%dT%H:%M:%SZ")
  fi

  [ "$iso" = "2025-01-15T10:30:00Z" ]
}

#----------------------------
# Test empty input
#----------------------------
@test "to_unix_ts with empty string returns 0 or fails gracefully" {
  result=$(to_unix_ts "")
  [ "$result" -eq 0 ]
}

#----------------------------
# Test invalid input
#----------------------------
@test "to_unix_ts with invalid timestamp returns error code" {
  run to_unix_ts "not-a-date"
  # It should fail (non-zero exit code)
  [ "$status" -ne 0 ]
}

@test "to_unix_ts prints an ::error:: message with the invalid timestamp" {
  run to_unix_ts "not-a-date"

  [ "$status" -eq 1 ]
  [[ "$output" == "::error::Invalid timestamp 'not-a-date' (expected format: YYYY-MM-DDTHH:MM:SSZ)" ]]
}

@test "to_unix_ts prints nothing on stdout for an invalid timestamp" {
  out=$(to_unix_ts "not-a-date" 2>/dev/null || true)

  [ -z "$out" ]
}

@test "to_unix_ts rejects trailing characters" {
  run to_unix_ts "2025-01-15T10:30:00Zjunk"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid timestamp" ]]
}

@test "to_unix_ts rejects a timestamp without the Z suffix" {
  run to_unix_ts "2025-01-15T10:30:00"

  [ "$status" -eq 1 ]
}

@test "to_unix_ts rejects a timestamp with a UTC offset" {
  run to_unix_ts "2025-01-15T10:30:00+01:00"

  [ "$status" -eq 1 ]
}

@test "to_unix_ts rejects a timestamp with a space instead of T" {
  run to_unix_ts "2025-01-15 10:30:00Z"

  [ "$status" -eq 1 ]
}

@test "to_unix_ts rejects a date with an impossible month" {
  run to_unix_ts "2025-13-45T00:00:00Z"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
}

@test "to_unix_ts rejects an impossible time" {
  run to_unix_ts "2025-01-01T25:61:61Z"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]]
}

#----------------------------
# Test boundary: Unix epoch
#----------------------------
@test "to_unix_ts converts epoch 1970-01-01T00:00:00Z correctly" {
  result=$(to_unix_ts "1970-01-01T00:00:00Z")
  [ "$result" -eq 0 ]
}

#----------------------------
# Test leap day
#----------------------------
@test "to_unix_ts converts leap day correctly" {
  result=$(to_unix_ts "2024-02-29T12:34:56Z")
  # Convert back to ISO string to verify
  if [[ "$(uname)" == "Darwin" ]]; then
    iso=$(date -u -r "$result" +"%Y-%m-%dT%H:%M:%SZ")
  else
    iso=$(date -u -d "@$result" +"%Y-%m-%dT%H:%M:%SZ")
  fi
  [ "$iso" = "2024-02-29T12:34:56Z" ]
}
