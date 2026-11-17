#!/usr/bin/env bats
#
# The five outputs ($GITHUB_OUTPUT) and the summary ($GITHUB_STEP_SUMMARY).

load helpers/common

setup() {
  setup_fake_gh
  # shellcheck source=../scripts/cancel.sh
  source "$SCRIPT"
  export GITHUB_STEP_SUMMARY="$WORK/summary.md"
  : >"$GITHUB_STEP_SUMMARY"
}

@test "write_outputs writes the five outputs, one per line" {
  write_outputs 5 2 1 2 '[101,102]'
  [ "$(cat "$GITHUB_OUTPUT")" = $'eligible-count=5\ncancelled-count=2\nskipped-count=1\nfailed-count=2\ncancelled-run-ids=[101,102]' ]
}

@test "write_outputs appends to the file" {
  echo "other=1" >"$GITHUB_OUTPUT"
  write_outputs 0 0 0 0 '[]'
  [ "$(head -n 1 "$GITHUB_OUTPUT")" = "other=1" ]
  [ "$(output_of cancelled-run-ids)" = "[]" ]
}

@test "write_outputs does nothing without GITHUB_OUTPUT" {
  unset GITHUB_OUTPUT
  run write_outputs 1 1 0 0 '[1]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the ids are valid JSON on one line, readable with fromJSON" {
  write_outputs 2 2 0 0 '[7,8]'
  [ "$(output_of cancelled-run-ids | jq -c .)" = "[7,8]" ]
}

@test "write_summary writes one table with the four counts" {
  write_summary 5 2 1 2 '[101,102]'
  grep -qx '| Eligible | Cancelled | Skipped | Failed |' "$GITHUB_STEP_SUMMARY"
  grep -qx '| 5 | 2 | 1 | 2 |' "$GITHUB_STEP_SUMMARY"
  [ "$(grep -c '^| ' "$GITHUB_STEP_SUMMARY")" -eq 3 ]
}

@test "write_summary names the repository and the age" {
  write_summary 0 0 0 0 '[]'
  grep -q 'myorg/myrepo' "$GITHUB_STEP_SUMMARY"
  grep -q '24 hours' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary links the cancelled runs" {
  write_summary 2 2 0 0 '[101,102]'
  grep -qF -- '- [101](https://github.com/myorg/myrepo/actions/runs/101)' "$GITHUB_STEP_SUMMARY"
  grep -qF -- '- [102](https://github.com/myorg/myrepo/actions/runs/102)' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary uses GITHUB_SERVER_URL for the links" {
  GITHUB_SERVER_URL=https://ghe.example.com write_summary 1 1 0 0 '[101]'
  grep -qF 'https://ghe.example.com/myorg/myrepo/actions/runs/101' "$GITHUB_STEP_SUMMARY"
}

@test "write_summary lists at most 50 runs" {
  write_summary 60 60 0 0 "$(jq -nc '[range(1; 61)]')"
  [ "$(grep -c '^- \[' "$GITHUB_STEP_SUMMARY")" -eq 50 ]
}

@test "write_summary lists no run when none was cancelled" {
  write_summary 3 0 3 0 '[]'
  ! grep -q '^- \[' "$GITHUB_STEP_SUMMARY" || false
}

@test "write_summary says that a dry run cancelled nothing" {
  DRY_RUN=true write_summary 3 0 0 0 '[]'
  grep -qi 'dry run' "$GITHUB_STEP_SUMMARY"
  : >"$GITHUB_STEP_SUMMARY"
  write_summary 3 0 0 0 '[]'
  ! grep -qi 'dry run' "$GITHUB_STEP_SUMMARY" || false
}

@test "write_summary appends and does nothing without GITHUB_STEP_SUMMARY" {
  echo "before" >"$GITHUB_STEP_SUMMARY"
  write_summary 0 0 0 0 '[]'
  [ "$(head -n 1 "$GITHUB_STEP_SUMMARY")" = "before" ]
  unset GITHUB_STEP_SUMMARY
  run write_summary 0 0 0 0 '[]'
  [ "$status" -eq 0 ]
}

@test "write_summary lists the runs of a dry run under 'Would cancel', with no cancelled run" {
  DRY_RUN=true write_summary 2 0 0 0 '[101,102]'
  grep -qx 'Would cancel:' "$GITHUB_STEP_SUMMARY"
  grep -qF -- '- [101](https://github.com/myorg/myrepo/actions/runs/101)' "$GITHUB_STEP_SUMMARY"
  ! grep -q '^Cancelled:' "$GITHUB_STEP_SUMMARY" || false
}

@test "write_summary lists the runs of a real run under 'Cancelled'" {
  write_summary 1 1 0 0 '[101]'
  grep -qx 'Cancelled:' "$GITHUB_STEP_SUMMARY"
}
