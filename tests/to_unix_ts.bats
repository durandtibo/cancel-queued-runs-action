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
  [[ "$result" =~ ^[0-9]+$ ]] || false

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
  [[ "$output" == "::error::Invalid timestamp 'not-a-date' (expected format: YYYY-MM-DDTHH:MM:SSZ)" ]] || false
}

@test "to_unix_ts prints nothing on stdout for an invalid timestamp" {
  out=$(to_unix_ts "not-a-date" 2>/dev/null || true)

  [ -z "$out" ]
}

@test "to_unix_ts rejects trailing characters" {
  run to_unix_ts "2025-01-15T10:30:00Zjunk"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid timestamp" ]] || false
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
  [[ "$output" =~ "::error::" ]] || false
}

@test "to_unix_ts rejects an impossible time" {
  run to_unix_ts "2025-01-01T25:61:61Z"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::" ]] || false
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

#----------------------------
# Number of date processes
#----------------------------

# Emulates GNU date, which accepts -d: it answers a fixed timestamp and logs
# its arguments, one line per call
mock_gnu_date() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export DATE_CALLS="$MOCK_DIR/date_calls.log"
  : > "$DATE_CALLS"
  date() {
    echo "$*" >> "$DATE_CALLS"
    echo 1736937000
  }
}

@test "to_unix_ts starts a single date process with GNU date" {
  mock_gnu_date

  to_unix_ts "2025-01-15T10:30:00Z" > /dev/null

  [ "$(wc -l < "$DATE_CALLS" | tr -d ' ')" -eq 1 ]
  rm -rf "$MOCK_DIR"
}

@test "to_unix_ts prints what GNU date answers" {
  mock_gnu_date

  result=$(to_unix_ts "2025-01-15T10:30:00Z")

  [ "$result" = "1736937000" ]
  rm -rf "$MOCK_DIR"
}

@test "to_unix_ts asks GNU date for UTC" {
  mock_gnu_date

  to_unix_ts "2025-01-15T10:30:00Z" > /dev/null

  [[ "$(cat "$DATE_CALLS")" == "-u -d 2025-01-15T10:30:00Z +%s" ]] || false
  rm -rf "$MOCK_DIR"
}

@test "to_unix_ts starts no date process for an empty timestamp" {
  mock_gnu_date

  to_unix_ts "" > /dev/null

  [ ! -s "$DATE_CALLS" ]
  rm -rf "$MOCK_DIR"
}

@test "to_unix_ts starts no date process for an invalid timestamp" {
  mock_gnu_date

  to_unix_ts "garbage" > /dev/null 2>&1 || true

  [ ! -s "$DATE_CALLS" ]
  rm -rf "$MOCK_DIR"
}

# Emulates BSD date, which rejects -d: it answers a fixed timestamp only to -j
# and logs its arguments, one line per call
mock_bsd_date() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export DATE_CALLS="$MOCK_DIR/date_calls.log"
  : > "$DATE_CALLS"
  date() {
    echo "$*" >> "$DATE_CALLS"
    if [[ " $* " == *" -d "* ]]; then
      return 1
    fi
    echo 1736937000
  }
}

@test "to_unix_ts prints what BSD date answers" {
  mock_bsd_date

  result=$(to_unix_ts "2025-01-15T10:30:00Z")

  [ "$result" = "1736937000" ]
  rm -rf "$MOCK_DIR"
}

@test "to_unix_ts asks BSD date for UTC" {
  mock_bsd_date

  to_unix_ts "2025-01-15T10:30:00Z" > /dev/null

  [[ "$(tail -n 1 "$DATE_CALLS")" == "-j -u -f %Y-%m-%dT%H:%M:%SZ 2025-01-15T10:30:00Z +%s" ]] || false
  rm -rf "$MOCK_DIR"
}
