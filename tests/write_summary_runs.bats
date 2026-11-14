#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  REPO="myorg/myrepo"
  unset GITHUB_SERVER_URL
}

@test "write_summary_runs prints nothing when no run was recorded" {
  run write_summary_runs

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "write_summary_runs prints a table with a header" {
  record_run 123 30h12m cancelled

  run write_summary_runs

  [ "$status" -eq 0 ]
  echo "$output" | grep -qx '#### Runs'
  echo "$output" | grep -qx '| Run | Age | Result |'
  echo "$output" | grep -qx '| --- | --- | --- |'
}

@test "write_summary_runs links each run to its page" {
  record_run 123 30h12m cancelled

  run write_summary_runs

  echo "$output" | grep -qxF '| [123](https://github.com/myorg/myrepo/actions/runs/123) | 30h12m | Cancelled |'
}

@test "write_summary_runs uses GITHUB_SERVER_URL for the links" {
  export GITHUB_SERVER_URL="https://github.example.com"
  record_run 123 30h12m cancelled

  run write_summary_runs

  echo "$output" | grep -qF '(https://github.example.com/myorg/myrepo/actions/runs/123)'
}

@test "write_summary_runs lists the runs in the order they were recorded" {
  record_run 1 5h00m cancelled
  record_run 2 6h00m skipped
  record_run 3 7h00m failed

  run write_summary_runs

  [ "$(echo "$output" | grep -n '\[1\]' | cut -d: -f1)" -lt "$(echo "$output" | grep -n '\[2\]' | cut -d: -f1)" ]
  [ "$(echo "$output" | grep -n '\[2\]' | cut -d: -f1)" -lt "$(echo "$output" | grep -n '\[3\]' | cut -d: -f1)" ]
}

@test "write_summary_runs describes every outcome" {
  record_run 1 5h00m cancelled
  record_run 2 5h00m would-cancel
  record_run 3 5h00m skipped
  record_run 4 unknown failed

  run write_summary_runs

  echo "$output" | grep -q '| 5h00m | Cancelled |'
  echo "$output" | grep -q '| 5h00m | Would be cancelled (dry run) |'
  echo "$output" | grep -q '| 5h00m | Skipped (cannot be cancelled or deleted) |'
  echo "$output" | grep -q '| unknown | Failed |'
}

@test "write_summary_runs lists at most SUMMARY_MAX_RUNS runs" {
  SUMMARY_MAX_RUNS=2
  record_run 1 5h00m cancelled
  record_run 2 5h00m cancelled
  record_run 3 5h00m cancelled
  record_run 4 5h00m cancelled

  run write_summary_runs

  echo "$output" | grep -q 'runs/1)'
  echo "$output" | grep -q 'runs/2)'
  [ -z "$(echo "$output" | grep 'runs/3)' || true)" ]
  [ -z "$(echo "$output" | grep 'runs/4)' || true)" ]
}

@test "write_summary_runs tells how many runs are not shown" {
  SUMMARY_MAX_RUNS=2
  record_run 1 5h00m cancelled
  record_run 2 5h00m cancelled
  record_run 3 5h00m cancelled
  record_run 4 5h00m cancelled
  record_run 5 5h00m cancelled

  run write_summary_runs

  echo "$output" | grep -qx '3 more run(s) are not listed here, see the logs of the step.'
}

@test "write_summary_runs does not mention hidden runs when all are shown" {
  SUMMARY_MAX_RUNS=3
  record_run 1 5h00m cancelled
  record_run 2 5h00m cancelled
  record_run 3 5h00m cancelled

  run write_summary_runs

  [ -z "$(echo "$output" | grep 'more run' || true)" ]
}

@test "write_summary_runs shows 50 runs by default" {
  [ "$SUMMARY_MAX_RUNS" -eq 50 ]
}

@test "write_summary_runs lists one more run than the limit minus one" {
  SUMMARY_MAX_RUNS=2
  record_run 1 5h00m cancelled
  record_run 2 5h00m cancelled

  run write_summary_runs

  echo "$output" | grep -q 'runs/2)'
  [ -z "$(echo "$output" | grep 'more run' || true)" ]
}
