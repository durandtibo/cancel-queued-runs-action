#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  REPO="myorg/myrepo"
  MAX_AGE_HOURS=24
  DRY_RUN=false
  CANCELLED_COUNT=3
  SKIPPED_COUNT=2
  FAILED_COUNT=1
  WOULD_CANCEL_COUNT=4
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "write_summary writes the repository and the maximum age" {
  run write_summary 10

  [ "$status" -eq 0 ]
  grep -q 'Repository: `myorg/myrepo`, maximum queue age: 24 hours' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary writes a table with the counters" {
  run write_summary 10

  grep -q '^| Runs found | 10 |$' "$GITHUB_STEP_SUMMARY"
  grep -q '^| Cancelled | 3 |$' "$GITHUB_STEP_SUMMARY"
  grep -q '^| Would be cancelled (dry run) | 4 |$' "$GITHUB_STEP_SUMMARY"
  grep -q '^| Skipped (no longer cancellable) | 2 |$' "$GITHUB_STEP_SUMMARY"
  grep -q '^| Failed | 1 |$' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary has a plain title for a real run" {
  run write_summary 10

  grep -qx '### Cancel stale workflow runs' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary says that nothing was cancelled in dry run" {
  DRY_RUN=true

  run write_summary 10

  grep -q 'dry run, nothing was cancelled' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary appends to the file instead of overwriting it" {
  echo "previous content" > "$GITHUB_STEP_SUMMARY"

  run write_summary 10

  grep -qx "previous content" "$GITHUB_STEP_SUMMARY"
  grep -q "Runs found" "$GITHUB_STEP_SUMMARY"
}

@test "write_summary prints nothing on stdout" {
  run write_summary 10

  [ -z "$output" ]
}

@test "write_summary does nothing when GITHUB_STEP_SUMMARY is unset" {
  unset GITHUB_STEP_SUMMARY

  run write_summary 10

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "write_summary mentions the workflow filter" {
  WORKFLOW="ci.yaml"

  run write_summary 10

  grep -q 'Workflow: `ci.yaml`' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary does not mention a workflow without filter" {
  WORKFLOW=""

  run write_summary 10

  run grep -q "Workflow:" "$GITHUB_STEP_SUMMARY"
  [ "$status" -ne 0 ]
}

@test "write_summary does not say queued in the title or in the table" {
  STATUSES="queued,waiting"

  run write_summary 10

  [ -z "$(grep -i "queued runs" "$GITHUB_STEP_SUMMARY" || true)" ]
  [ -z "$(grep -iE '^###.*queued' "$GITHUB_STEP_SUMMARY" || true)" ]
}

@test "write_summary lists the statuses considered" {
  STATUSES="queued"

  run write_summary 10

  grep -qx 'Statuses considered: `queued`' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary lists several statuses" {
  STATUSES="queued,waiting"

  run write_summary 10

  grep -qx 'Statuses considered: `queued,waiting`' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary ignores the spaces of the statuses" {
  STATUSES="queued, waiting , pending"

  run write_summary 10

  grep -qx 'Statuses considered: `queued,waiting,pending`' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary uses a neutral title in dry run too" {
  DRY_RUN=true

  run write_summary 10

  grep -qx '### Cancel stale workflow runs (dry run, nothing was cancelled)' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary lists the runs that were acted on" {
  record_run 123 30h12m cancelled

  run write_summary 10

  grep -qF '| [123](https://github.com/myorg/myrepo/actions/runs/123) | 30h12m | Cancelled |' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary lists the runs after the counters table" {
  record_run 123 30h12m cancelled

  run write_summary 10

  [ "$(grep -n '^| Failed |' "$GITHUB_STEP_SUMMARY" | cut -d: -f1)" -lt "$(grep -n '^#### Runs' "$GITHUB_STEP_SUMMARY" | cut -d: -f1)" ]
}

@test "write_summary has no list of runs when no run was acted on" {
  run write_summary 10

  [ -z "$(grep 'Runs$' "$GITHUB_STEP_SUMMARY" | grep '####' || true)" ]
  [ -z "$(grep 'actions/runs' "$GITHUB_STEP_SUMMARY" || true)" ]
}

