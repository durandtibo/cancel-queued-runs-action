#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "count_unparsed_runs counts the non-empty lines" {
  run count_unparsed_runs "$(printf '%s\n' 'a' '' 'b' 'c')"

  [ "$output" = "3" ]
}

@test "count_unparsed_runs returns 1 for an empty stream" {
  run count_unparsed_runs ""

  [ "$output" = "1" ]
}
