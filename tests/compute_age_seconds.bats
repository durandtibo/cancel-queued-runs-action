#!/usr/bin/env bats

setup() {
  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "compute_age_seconds returns correct age in seconds" {
    updated="2025-01-01T10:00:00Z"
    now="2025-01-01T13:30:00Z"

    result=$(compute_age_seconds "$updated" "$now")
    [ "$result" -eq 12600 ]
}

@test "compute_age_seconds returns 0 if now is same as updated" {
    ts="2025-01-01T10:00:00Z"
    result=$(compute_age_seconds "$ts" "$ts")
    [ "$result" -eq 0 ]
}

@test "compute_age_seconds returns -1 if updated timestamp is empty" {
    result=$(compute_age_seconds "" "2025-01-01T13:30:00Z")
    [ "$result" -eq -1 ]
}

@test "compute_age_seconds works with default now (current UTC time)" {
    # Use a updated timestamp in the past
    updated=$(date -u -v -2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    result=$(compute_age_seconds "$updated")
    # Should be roughly 2 hours, allow some slack for timing
    [ "$result" -ge 7200 ]
    [ "$result" -lt 7260 ]
}

@test "compute_age_seconds returns correct age (1 second difference)" {
    updated="2025-01-01T10:00:00Z"
    now="2025-01-01T10:00:01Z"

    result=$(compute_age_seconds "$updated" "$now")
    [ "$result" -eq 1 ]
}

@test "compute_age_seconds returns correct age (1 minute difference)" {
    updated="2025-01-01T10:00:00Z"
    now="2025-01-01T10:01:00Z"

    result=$(compute_age_seconds "$updated" "$now")
    [ "$result" -eq 60 ]
}

@test "compute_age_seconds keeps the minutes of a partial hour (1h01 difference)" {
    updated="2025-01-01T10:00:00Z"
    now="2025-01-01T11:01:00Z"

    result=$(compute_age_seconds "$updated" "$now")
    [ "$result" -eq 3660 ]
}

@test "compute_age_seconds does not truncate to whole hours (24h59 difference)" {
    updated="2025-01-01T00:00:00Z"
    now="2025-01-02T00:59:00Z"

    result=$(compute_age_seconds "$updated" "$now")
    [ "$result" -eq $((24 * 3600 + 59 * 60)) ]
}

@test "compute_age_seconds returns a negative value if the timestamp is in the future" {
    updated="2025-01-01T11:00:00Z"
    now="2025-01-01T10:00:00Z"

    result=$(compute_age_seconds "$updated" "$now")
    [ "$result" -eq -3600 ]
}
