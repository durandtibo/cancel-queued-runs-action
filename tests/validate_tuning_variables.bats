#!/usr/bin/env bats

setup() {
  unset MAX_RETRIES RETRY_BASE_DELAY RETRY_MAX_DELAY RUNS_LISTING_LIMIT SUMMARY_MAX_RUNS
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_tuning_variables accepts the default values" {
  run validate_tuning_variables

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_tuning_variables accepts a large MAX_RETRIES" {
  MAX_RETRIES=100000

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 1 for MAX_RETRIES" {
  MAX_RETRIES=1

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 0 for MAX_RETRIES" {
  MAX_RETRIES=0

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables rejects a negative value for MAX_RETRIES" {
  MAX_RETRIES=-1

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got '-1')" ]
}

@test "validate_tuning_variables rejects a decimal value for MAX_RETRIES" {
  MAX_RETRIES=1.5

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got '1.5')" ]
}

@test "validate_tuning_variables rejects a non numeric value for MAX_RETRIES" {
  MAX_RETRIES=abc

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got 'abc')" ]
}

@test "validate_tuning_variables rejects a leading zero for MAX_RETRIES" {
  MAX_RETRIES=08

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got '08')" ]
}

@test "validate_tuning_variables rejects a value with spaces for MAX_RETRIES" {
  MAX_RETRIES="1 2"

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got '1 2')" ]
}

@test "validate_tuning_variables rejects an empty MAX_RETRIES" {
  MAX_RETRIES=""

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got '')" ]
}

@test "validate_tuning_variables accepts a large SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=100000

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 1 for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=1

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 0 for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=0

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables rejects a negative value for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=-1

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::SUMMARY_MAX_RUNS must be a non-negative integer (got '-1')" ]
}

@test "validate_tuning_variables rejects a decimal value for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=1.5

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::SUMMARY_MAX_RUNS must be a non-negative integer (got '1.5')" ]
}

@test "validate_tuning_variables rejects a non numeric value for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=abc

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::SUMMARY_MAX_RUNS must be a non-negative integer (got 'abc')" ]
}

@test "validate_tuning_variables rejects a leading zero for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=08

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::SUMMARY_MAX_RUNS must be a non-negative integer (got '08')" ]
}

@test "validate_tuning_variables rejects a value with spaces for SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS="1 2"

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::SUMMARY_MAX_RUNS must be a non-negative integer (got '1 2')" ]
}

@test "validate_tuning_variables rejects an empty SUMMARY_MAX_RUNS" {
  SUMMARY_MAX_RUNS=""

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::SUMMARY_MAX_RUNS must be a non-negative integer (got '')" ]
}

@test "validate_tuning_variables accepts a large RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=100000

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 1 for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=1

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables rejects 0 for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=0

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got '0')" ]
}

@test "validate_tuning_variables rejects a negative value for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=-1

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got '-1')" ]
}

@test "validate_tuning_variables rejects a decimal value for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=1.5

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got '1.5')" ]
}

@test "validate_tuning_variables rejects a non numeric value for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=abc

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got 'abc')" ]
}

@test "validate_tuning_variables rejects a leading zero for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=08

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got '08')" ]
}

@test "validate_tuning_variables rejects a value with spaces for RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY="1 2"

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got '1 2')" ]
}

@test "validate_tuning_variables rejects an empty RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=""

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_BASE_DELAY must be a positive integer (got '')" ]
}

@test "validate_tuning_variables accepts a large RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=100000

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 1 for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=1

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables rejects 0 for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=0

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got '0')" ]
}

@test "validate_tuning_variables rejects a negative value for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=-1

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got '-1')" ]
}

@test "validate_tuning_variables rejects a decimal value for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=1.5

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got '1.5')" ]
}

@test "validate_tuning_variables rejects a non numeric value for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=abc

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got 'abc')" ]
}

@test "validate_tuning_variables rejects a leading zero for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=08

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got '08')" ]
}

@test "validate_tuning_variables rejects a value with spaces for RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY="1 2"

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got '1 2')" ]
}

@test "validate_tuning_variables rejects an empty RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=""

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RETRY_MAX_DELAY must be a positive integer (got '')" ]
}

@test "validate_tuning_variables accepts a large RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=100000

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables accepts 1 for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=1

  run validate_tuning_variables

  [ "$status" -eq 0 ]
}

@test "validate_tuning_variables rejects 0 for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=0

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got '0')" ]
}

@test "validate_tuning_variables rejects a negative value for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=-1

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got '-1')" ]
}

@test "validate_tuning_variables rejects a decimal value for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=1.5

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got '1.5')" ]
}

@test "validate_tuning_variables rejects a non numeric value for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=abc

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got 'abc')" ]
}

@test "validate_tuning_variables rejects a leading zero for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=08

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got '08')" ]
}

@test "validate_tuning_variables rejects a value with spaces for RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT="1 2"

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got '1 2')" ]
}

@test "validate_tuning_variables rejects an empty RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=""

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::RUNS_LISTING_LIMIT must be a positive integer (got '')" ]
}

@test "validate_tuning_variables reports every invalid variable" {
  MAX_RETRIES=abc
  RETRY_MAX_DELAY=0

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
  echo "$output" | grep -q "MAX_RETRIES must be a non-negative integer (got 'abc')"
  echo "$output" | grep -q "RETRY_MAX_DELAY must be a positive integer (got '0')"
}

@test "validate_tuning_variables reports the errors as ::error:: annotations" {
  MAX_RETRIES=abc

  run validate_tuning_variables

  [[ "$output" =~ ^::error:: ]] || false
}

@test "validate_tuning_variables writes the errors on stderr only" {
  MAX_RETRIES=abc

  stdout=$(validate_tuning_variables 2>/dev/null || true)

  [ -z "$stdout" ]
}

@test "validate_tuning_variables rejects a variable that was unset after the script was sourced" {
  unset MAX_RETRIES

  run validate_tuning_variables

  [ "$status" -eq 1 ]
  [ "$output" = "::error::MAX_RETRIES must be a non-negative integer (got '')" ]
}
