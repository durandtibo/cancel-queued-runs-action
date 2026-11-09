#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  MAX_AGE_HOURS=24
}

@test "is_old_enough accepts an age above MAX_AGE_HOURS" {
  run is_old_enough $((25 * 3600))

  [ "$status" -eq 0 ]
}

@test "is_old_enough rejects an age below MAX_AGE_HOURS" {
  run is_old_enough $((23 * 3600))

  [ "$status" -eq 1 ]
}

@test "is_old_enough rejects an age of exactly MAX_AGE_HOURS" {
  run is_old_enough $((24 * 3600))

  [ "$status" -eq 1 ]
}

@test "is_old_enough accepts an age one second above MAX_AGE_HOURS" {
  run is_old_enough $((24 * 3600 + 1))

  [ "$status" -eq 0 ]
}

@test "is_old_enough keeps the minutes of a partial hour" {
  run is_old_enough $((24 * 3600 + 30 * 60))

  [ "$status" -eq 0 ]
}

@test "is_old_enough rejects an age of 0" {
  run is_old_enough 0

  [ "$status" -eq 1 ]
}

@test "is_old_enough rejects a negative age" {
  run is_old_enough -5

  [ "$status" -eq 1 ]
}

@test "is_old_enough follows MAX_AGE_HOURS" {
  MAX_AGE_HOURS=1

  run is_old_enough $((2 * 3600))

  [ "$status" -eq 0 ]
}

@test "is_old_enough prints nothing" {
  run is_old_enough $((25 * 3600))

  [ -z "$output" ]
}

@test "is_old_enough agrees with process_run on the threshold" {
  # process_run cancels (or would cancel) a run when its age is above
  # MAX_AGE_HOURS: the two must not disagree
  DRY_RUN=true
  FORCE_BUFFER_HOURS=3

  for age in $((24 * 3600 - 1)) $((24 * 3600)) $((24 * 3600 + 1)); do
    process_run 1 "$age" > /dev/null
    if is_old_enough "$age"; then
      [ "$PROCESS_RUN_OUTCOME" = "would-cancel" ]
    else
      [ "$PROCESS_RUN_OUTCOME" = "noop" ]
    fi
  done
}
