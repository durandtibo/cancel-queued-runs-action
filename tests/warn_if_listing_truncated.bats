#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "warn_if_listing_truncated has a default limit of 1000" {
  [ "$RUNS_LISTING_LIMIT" -eq 1000 ]
}

@test "warn_if_listing_truncated warns when the limit is reached" {
  RUNS_LISTING_LIMIT=1000

  run warn_if_listing_truncated queued 1000

  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::1000 runs were listed for the status 'queued'" ]]
}

@test "warn_if_listing_truncated warns when the limit is exceeded" {
  RUNS_LISTING_LIMIT=1000

  run warn_if_listing_truncated waiting 1200

  [[ "$output" =~ "::warning::1200 runs were listed for the status 'waiting'" ]]
}

@test "warn_if_listing_truncated does not warn just below the limit" {
  RUNS_LISTING_LIMIT=1000

  run warn_if_listing_truncated queued 999

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "warn_if_listing_truncated does not warn for an empty listing" {
  RUNS_LISTING_LIMIT=1000

  run warn_if_listing_truncated queued 0

  [ -z "$output" ]
}

@test "warn_if_listing_truncated uses RUNS_LISTING_LIMIT" {
  RUNS_LISTING_LIMIT=5

  run warn_if_listing_truncated queued 5

  [[ "$output" =~ "::warning::" ]]
}

@test "warn_if_listing_truncated writes the warning on stderr only" {
  RUNS_LISTING_LIMIT=1

  out=$(warn_if_listing_truncated queued 3 2>/dev/null)

  [ -z "$out" ]
}

@test "warn_if_listing_truncated tells that the action can be run again" {
  RUNS_LISTING_LIMIT=1

  run warn_if_listing_truncated queued 3

  [[ "$output" =~ "Run the action again" ]]
}

@test "warn_if_listing_truncated is not truncated by default" {
  [ "$LISTING_TRUNCATED" = "false" ]
}

@test "warn_if_listing_truncated sets LISTING_TRUNCATED when the limit is reached" {
  RUNS_LISTING_LIMIT=1000

  warn_if_listing_truncated queued 1000 2>/dev/null

  [ "$LISTING_TRUNCATED" = "true" ]
}

@test "warn_if_listing_truncated does not set LISTING_TRUNCATED below the limit" {
  RUNS_LISTING_LIMIT=1000

  warn_if_listing_truncated queued 999

  [ "$LISTING_TRUNCATED" = "false" ]
}

@test "warn_if_listing_truncated keeps LISTING_TRUNCATED true for a later status below the limit" {
  RUNS_LISTING_LIMIT=1000

  warn_if_listing_truncated queued 1000 2>/dev/null
  warn_if_listing_truncated waiting 3

  [ "$LISTING_TRUNCATED" = "true" ]
}
