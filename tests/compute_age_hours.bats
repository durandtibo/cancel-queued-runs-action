#!/usr/bin/env bats

setup() {
  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "compute_age_hours returns correct age in hours" {
    created="2025-01-01T10:00:00Z"
    now="2025-01-01T13:30:00Z"

    result=$(compute_age_hours "$created" "$now")
    [ "$result" -eq 3 ]
}

@test "compute_age_hours returns 0 if now is same as created" {
    ts="2025-01-01T10:00:00Z"
    result=$(compute_age_hours "$ts" "$ts")
    [ "$result" -eq 0 ]
}

@test "compute_age_hours returns -1 if created timestamp is empty" {
    result=$(compute_age_hours "" "2025-01-01T13:30:00Z")
    [ "$result" -eq -1 ]
}

@test "compute_age_hours works with default now (current UTC time)" {
    # Use a created timestamp in the past
    created=$(date -u -v -2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    result=$(compute_age_hours "$created")
    [ "$result" -ge 1 ]  # Should be roughly 2 hours, allow >=1 for timing
}

@test "compute_age_hours returns correct age in hours (1 second difference)" {
    created="2025-01-01T10:00:00Z"
    now="2025-01-01T10:00:01Z"

    result=$(compute_age_hours "$created" "$now")
    [ "$result" -eq 0 ]
}

@test "compute_age_hours returns correct age in hours (1 minute difference)" {
    created="2025-01-01T10:00:00Z"
    now="2025-01-01T10:01:00Z"

    result=$(compute_age_hours "$created" "$now")
    [ "$result" -eq 0 ]
}

@test "compute_age_hours returns correct age in hours (1h01 difference)" {
    created="2025-01-01T10:00:00Z"
    now="2025-01-01T11:01:00Z"

    result=$(compute_age_hours "$created" "$now")
    [ "$result" -eq 1 ]
}
