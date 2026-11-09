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

# --------------------------------------------------------
# Boundaries
# --------------------------------------------------------

@test "format_age formats 59 minutes and 59 seconds as 0h59m" {
  [ "$(format_age 3599)" = "0h59m" ]
}

@test "format_age formats exactly 3600 seconds as 1h00m" {
  [ "$(format_age 3600)" = "1h00m" ]
}

@test "format_age formats 3601 seconds as 1h00m" {
  [ "$(format_age 3601)" = "1h00m" ]
}

@test "format_age formats one second below a day as 23h59m" {
  [ "$(format_age 86399)" = "23h59m" ]
}

@test "format_age formats exactly a day as 24h00m" {
  [ "$(format_age 86400)" = "24h00m" ]
}

@test "format_age formats a negative age of one second as 0h00m" {
  [ "$(format_age -1)" = "0h00m" ]
}

@test "format_age formats a very large negative age as 0h00m" {
  [ "$(format_age -9999999)" = "0h00m" ]
}
