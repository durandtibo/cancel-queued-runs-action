#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  export REPO="myorg/myrepo"
  DELETE_STUCK_RUNS=true
  NO_JOBS=true
  DELETE_RESPONSE="HTTP/2.0 204 No Content"

  run_has_no_jobs() { [ "$NO_JOBS" = "true" ]; }
  # A directory of the test directory, as BATS_TEST_TMPDIR is missing from old
  # bats (1.2.x, installed by apt on Ubuntu 22.04)
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  DELETED_FILE="$MOCK_DIR/deleted"
  rm -f "$DELETED_FILE"
  delete_run() { echo "$1" >> "$DELETED_FILE"; echo "$DELETE_RESPONSE"; }
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "delete_zombie_run deletes a run without job" {
  delete_zombie_run 123 "30h00m" >/dev/null

  [ "$PROCESS_RUN_OUTCOME" = "deleted" ]
  [ "$(cat "$DELETED_FILE")" = "123" ]
}

@test "delete_zombie_run returns 0 when the run is deleted" {
  run delete_zombie_run 123 "30h00m"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Run 123 deleted" ]] || false
}

@test "delete_zombie_run does nothing when DELETE_STUCK_RUNS is false" {
  DELETE_STUCK_RUNS=false

  run delete_zombie_run 123 "30h00m"

  [ "$status" -eq 1 ]
  [ ! -e "$DELETED_FILE" ]
}

@test "delete_zombie_run never deletes a run that has jobs" {
  NO_JOBS=false

  run delete_zombie_run 123 "30h00m"

  [ "$status" -eq 1 ]
  [ ! -e "$DELETED_FILE" ]
}

@test "delete_zombie_run treats a 404 as deleted" {
  DELETE_RESPONSE="HTTP/2.0 404 Not Found"

  delete_zombie_run 123 "30h00m" >/dev/null

  [ "$PROCESS_RUN_OUTCOME" = "deleted" ]
}

@test "delete_zombie_run reports a failed deletion" {
  DELETE_RESPONSE="HTTP/2.0 500 Internal Server Error"

  run delete_zombie_run 123 "30h00m"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Deletion failed for run 123" ]] || false
}

@test "delete_zombie_run sets the outcome failed when the deletion fails" {
  DELETE_RESPONSE="HTTP/2.0 500 Internal Server Error"

  delete_zombie_run 123 "30h00m" >/dev/null

  [ "$PROCESS_RUN_OUTCOME" = "failed" ]
}

@test "delete_zombie_run skips a run that GitHub refuses to delete (403)" {
  DELETE_RESPONSE="$(printf 'HTTP/2.0 403 Forbidden\n\n{"message":"Could not delete the workflow run"}')"

  delete_zombie_run 123 "30h00m" >/dev/null

  [ "$PROCESS_RUN_OUTCOME" = "skipped" ]
}

@test "delete_zombie_run explains a 403 with a single warning" {
  DELETE_RESPONSE="$(printf 'HTTP/2.0 403 Forbidden\n\n{"message":"Could not delete the workflow run"}')"

  run delete_zombie_run 123 "30h00m"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::Run 123 could not be deleted (HTTP 403: Could not delete the workflow run)" ]] || false
  [[ "$output" =~ "GitHub Support" ]] || false
  [[ ! "$output" =~ "Deletion failed" ]] || false
}

@test "delete_zombie_run still fails on a 500 error" {
  DELETE_RESPONSE="HTTP/2.0 500 Internal Server Error"

  delete_zombie_run 123 "30h00m" >/dev/null

  [ "$PROCESS_RUN_OUTCOME" = "failed" ]
}
