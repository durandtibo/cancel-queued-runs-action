#!/usr/bin/env bats

setup() {
  # Source the script under test
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "format_age formats zero seconds" {
  result=$(format_age 0)
  [ "$result" = "0h00m" ]
}

@test "format_age drops the seconds below one minute" {
  result=$(format_age 59)
  [ "$result" = "0h00m" ]
}

@test "format_age formats minutes with a leading zero" {
  result=$(format_age 300)
  [ "$result" = "0h05m" ]
}

@test "format_age formats exactly one hour" {
  result=$(format_age 3600)
  [ "$result" = "1h00m" ]
}

@test "format_age formats hours and minutes" {
  result=$(format_age $((24 * 3600 + 59 * 60)))
  [ "$result" = "24h59m" ]
}

@test "format_age formats ages of several thousand hours" {
  result=$(format_age $((7558 * 3600 + 12 * 60)))
  [ "$result" = "7558h12m" ]
}

@test "format_age formats a negative age as zero" {
  result=$(format_age -3700)
  [ "$result" = "0h00m" ]
}
