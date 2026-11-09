#!/usr/bin/env bats

setup() {
  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "compute_age_seconds returns correct age in seconds" {
    queued_at="2025-01-01T10:00:00Z"
    now="2025-01-01T13:30:00Z"

    result=$(compute_age_seconds "$queued_at" "$now")
    [ "$result" -eq 12600 ]
}

@test "compute_age_seconds returns 0 if now is same as queued_at" {
    ts="2025-01-01T10:00:00Z"
    result=$(compute_age_seconds "$ts" "$ts")
    [ "$result" -eq 0 ]
}

@test "compute_age_seconds returns -1 if queued_at timestamp is empty" {
    result=$(compute_age_seconds "" "2025-01-01T13:30:00Z")
    [ "$result" -eq -1 ]
}

@test "compute_age_seconds works with default now (current UTC time)" {
    # Use a queued_at timestamp in the past
    queued_at=$(date -u -v -2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    result=$(compute_age_seconds "$queued_at")
    # Should be roughly 2 hours, allow some slack for timing
    [ "$result" -ge 7200 ]
    [ "$result" -lt 7260 ]
}

@test "compute_age_seconds returns correct age (1 second difference)" {
    queued_at="2025-01-01T10:00:00Z"
    now="2025-01-01T10:00:01Z"

    result=$(compute_age_seconds "$queued_at" "$now")
    [ "$result" -eq 1 ]
}

@test "compute_age_seconds returns correct age (1 minute difference)" {
    queued_at="2025-01-01T10:00:00Z"
    now="2025-01-01T10:01:00Z"

    result=$(compute_age_seconds "$queued_at" "$now")
    [ "$result" -eq 60 ]
}

@test "compute_age_seconds keeps the minutes of a partial hour (1h01 difference)" {
    queued_at="2025-01-01T10:00:00Z"
    now="2025-01-01T11:01:00Z"

    result=$(compute_age_seconds "$queued_at" "$now")
    [ "$result" -eq 3660 ]
}

@test "compute_age_seconds does not truncate to whole hours (24h59 difference)" {
    queued_at="2025-01-01T00:00:00Z"
    now="2025-01-02T00:59:00Z"

    result=$(compute_age_seconds "$queued_at" "$now")
    [ "$result" -eq $((24 * 3600 + 59 * 60)) ]
}

@test "compute_age_seconds returns a negative value if the timestamp is in the future" {
    queued_at="2025-01-01T11:00:00Z"
    now="2025-01-01T10:00:00Z"

    result=$(compute_age_seconds "$queued_at" "$now")
    [ "$result" -eq -3600 ]
}

@test "compute_age_seconds fails when queued_at is invalid" {
    run compute_age_seconds "not-a-date" "2025-01-01T10:00:00Z"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "::error::Invalid timestamp 'not-a-date'" ]]
}

@test "compute_age_seconds fails when now is invalid" {
    run compute_age_seconds "2025-01-01T10:00:00Z" "not-a-date"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "::error::Invalid timestamp 'not-a-date'" ]]
}

@test "compute_age_seconds prints no age when a timestamp is invalid" {
    out=$(compute_age_seconds "not-a-date" "2025-01-01T10:00:00Z" 2>/dev/null || true)

    [ -z "$out" ]
}

# --------------------------------------------------------
# Boundaries: calendar edges and time zones
# --------------------------------------------------------

@test "compute_age_seconds counts one second across the end of a year" {
  result=$(compute_age_seconds "2024-12-31T23:59:59Z" "2025-01-01T00:00:00Z")

  [ "$result" -eq 1 ]
}

@test "compute_age_seconds counts the 29th of February of a leap year" {
  result=$(compute_age_seconds "2024-02-28T12:00:00Z" "2024-03-01T12:00:00Z")

  [ "$result" -eq 172800 ]
}

@test "compute_age_seconds has no 29th of February in a common year" {
  result=$(compute_age_seconds "2025-02-28T12:00:00Z" "2025-03-01T12:00:00Z")

  [ "$result" -eq 86400 ]
}

@test "compute_age_seconds counts a full year" {
  result=$(compute_age_seconds "2025-01-01T00:00:00Z" "2026-01-01T00:00:00Z")

  [ "$result" -eq 31536000 ]
}

@test "compute_age_seconds works after 2038, the end of 32-bit timestamps" {
  result=$(compute_age_seconds "2038-01-19T03:14:07Z" "2038-01-19T03:14:09Z")

  [ "$result" -eq 2 ]
}

@test "compute_age_seconds is not affected by the local time zone on a day with a DST change (New York)" {
  # 2025-03-09 only has 23 hours in New York, but 24 in UTC
  export TZ="America/New_York"

  result=$(compute_age_seconds "2025-03-09T00:00:00Z" "2025-03-10T00:00:00Z")

  [ "$result" -eq 86400 ]
}

@test "compute_age_seconds is not affected by the local time zone on a day with a DST change (Paris)" {
  # 2025-10-26 has 25 hours in Paris, but 24 in UTC
  export TZ="Europe/Paris"

  result=$(compute_age_seconds "2025-10-26T00:00:00Z" "2025-10-27T00:00:00Z")

  [ "$result" -eq 86400 ]
}

@test "compute_age_seconds gives the same age in every time zone" {
  a=$(TZ="Pacific/Auckland" compute_age_seconds "2025-06-01T10:00:00Z" "2025-06-01T13:30:00Z")
  b=$(TZ="America/Los_Angeles" compute_age_seconds "2025-06-01T10:00:00Z" "2025-06-01T13:30:00Z")

  [ "$a" -eq 12600 ]
  [ "$b" -eq 12600 ]
}

@test "compute_age_seconds falls back to the current time when now is empty" {
  # an empty second argument falls back to the current time: it is not -1
  result=$(compute_age_seconds "2025-01-01T00:00:00Z" "")

  [ "$result" -gt 0 ]
}
