#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "is_skippable_status accepts 404" {
  run is_skippable_status 404

  [ "$status" -eq 0 ]
}

@test "is_skippable_status accepts 409" {
  run is_skippable_status 409

  [ "$status" -eq 0 ]
}

@test "is_skippable_status rejects 202" {
  run is_skippable_status 202

  [ "$status" -eq 1 ]
}

@test "is_skippable_status rejects 403" {
  run is_skippable_status 403

  [ "$status" -eq 1 ]
}

@test "is_skippable_status rejects 500" {
  run is_skippable_status 500

  [ "$status" -eq 1 ]
}

@test "is_skippable_status rejects an empty status" {
  run is_skippable_status ""

  [ "$status" -eq 1 ]
}

@test "is_skippable_status rejects a missing argument" {
  run is_skippable_status

  [ "$status" -eq 1 ]
}

@test "is_skippable_status does not match a longer code" {
  run is_skippable_status 4040

  [ "$status" -eq 1 ]
}

@test "is_skippable_status prints nothing" {
  run is_skippable_status 404

  [ -z "$output" ]
}
