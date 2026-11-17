#!/usr/bin/env bats
#
# The whole script as a process, with the fake gh: the flow, the outputs on every
# path, the summary, the exit codes. The rules themselves (threshold, dry run,
# 404 and 409, fail-on-error, validation) are pinned in the files of each function.

load helpers/common

H=3600

setup() {
  setup_fake_gh
  export GITHUB_STEP_SUMMARY="$WORK/summary.md"
  : >"$GITHUB_STEP_SUMMARY"
}

@test "the five outputs are set when nothing is eligible" {
  list_queued
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_of eligible-count)" = "0" ]
  [ "$(output_of cancelled-count)" = "0" ]
  [ "$(output_of skipped-count)" = "0" ]
  [ "$(output_of failed-count)" = "0" ]
  [ "$(output_of cancelled-run-ids)" = "[]" ]
}

@test "outputs of a real run: the counts add up and the ids are listed oldest first" {
  list_queued 1:$((30 * H)) 2:$((50 * H)) 3:$((40 * H)) 4:$((26 * H)) 5:60
  answer_post 1 202; answer_post 2 202; answer_post 3 404 "Not Found"; answer_post 4 500 "Server Error"
  FAIL_ON_ERROR=false run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_of eligible-count)" = "4" ]
  [ "$(output_of cancelled-count)" = "2" ]
  [ "$(output_of skipped-count)" = "1" ]
  [ "$(output_of failed-count)" = "1" ]
  [ "$(output_of cancelled-run-ids)" = "[2,1]" ]
}

@test "outputs are all set, with zeros, when the listing fails" {
  add_rule GET '*' 500 '{"message":"Server Error"}'
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(output_of eligible-count)" = "0" ]
  [ "$(output_of cancelled-count)" = "0" ]
  [ "$(output_of skipped-count)" = "0" ]
  [ "$(output_of failed-count)" = "0" ]
  [ "$(output_of cancelled-run-ids)" = "[]" ]
  [[ "$output" == *"::error::Cannot list the workflow runs of myorg/myrepo"* ]] || false
}

@test "no output is written for an invalid input, which fails before any call" {
  MAX_AGE_HOURS=abc run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "the runs are cancelled oldest first, with a pause of one second between requests" {
  list_queued 1:$((30 * H)) 2:$((50 * H)) 3:$((40 * H))
  answer_post 1 202; answer_post 2 202; answer_post 3 202
  run "$SCRIPT"
  [ "$(grep -oE 'runs/[0-9]+/cancel' "$FAKE_GH_LOG" | tr -dc '0-9\n' | tr '\n' ' ')" = "2 3 1 " ]
  [ "$(cat "$WORK/sleeps.txt")" = $'1\n1' ]
}

@test "the listing is limited to the runs created before the cutoff" {
  list_queued
  run "$SCRIPT"
  grep -qE -- '-f created=<20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' "$FAKE_GH_LOG"
}

@test "a run listed under two statuses is cancelled once" {
  export STATUSES="queued,waiting"
  ts=$(ago $((30 * H)))
  add_rule GET '*' 200 "{\"workflow_runs\":[{\"id\":1,\"created_at\":\"$ts\",\"updated_at\":\"$ts\"}]}"
  answer_post 1 202
  run "$SCRIPT"
  [ "$(posted_to 1)" -eq 1 ]
  [ "$(output_of eligible-count)" = "1" ]
}

@test "a failure is a non-zero exit with an error, and the outputs are written first" {
  list_queued 1:$((30 * H))
  answer_post 1 500 "Server Error"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::1 run(s) could not be cancelled"* ]] || false
  [ "$(output_of failed-count)" = "1" ]
}

@test "fail_on_error false: a warning and a success" {
  list_queued 1:$((30 * H))
  answer_post 1 500 "Server Error"
  FAIL_ON_ERROR=false run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title=Cancellation failed::1 run(s) could not be cancelled"* ]] || false
}

@test "a rate limit stops the execution: the other runs are failed, not sent" {
  list_queued 1:$((50 * H)) 2:$((40 * H)) 3:$((30 * H))
  answer_post 1 202; answer_post 2 429 "Too Many Requests"; answer_post 3 202
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(output_of cancelled-count)" = "1" ]
  [ "$(output_of failed-count)" = "2" ]
  [ "$(posted_to 3)" -eq 0 ]
}

@test "the summary is written with the counts" {
  list_queued 1:$((30 * H))
  answer_post 1 202
  run "$SCRIPT"
  grep -qx '| 1 | 1 | 0 | 0 |' "$GITHUB_STEP_SUMMARY"
}

@test "the script can be sourced without running anything" {
  run bash -c 'source "$1"; echo sourced' _ "$SCRIPT"
  [ "$output" = "sourced" ]
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "the script uses only bash, gh and jq: no date, no temporary file" {
  ! grep -nE '(^|[^a-z_])date( |$)|mktemp' "$SCRIPT" || false
}

# A PATH with the fake gh and nothing else: bash is called by its path, jq is missing
only_gh_path() {
  mkdir -p "$WORK/only_gh"
  ln -s "$BATS_TEST_DIRNAME/helpers/fake_gh" "$WORK/only_gh/gh"
  echo "$WORK/only_gh"
}

@test "a missing jq stops the script with exit 1, a message and no request" {
  list_queued 1:$((30 * H))
  run env PATH="$(only_gh_path)" /bin/bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Required command not found: jq"* ]] || false
  [ ! -s "$FAKE_GH_LOG" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "a missing gh stops the script with exit 1 and a message" {
  mkdir -p "$WORK/empty"
  run env PATH="$WORK/empty" /bin/bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Required command not found: gh"* ]] || false
}

@test "an invalid input exits 1 with one error and no output" {
  MAX_AGE_HOURS=abc run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::MAX_AGE_HOURS"* ]] || false
  [ ! -s "$GITHUB_OUTPUT" ]
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "max-age-hours 87600 is accepted and 87601 is refused before any request" {
  list_queued
  MAX_AGE_HOURS=87600 run "$SCRIPT"
  [ "$status" -eq 0 ]
  : >"$FAKE_GH_LOG"
  MAX_AGE_HOURS=87601 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::MAX_AGE_HOURS"* ]] || false
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "fail-on-error false does not hide a failure to list the runs" {
  add_rule GET '*' 500 '{"message":"Server Error"}'
  FAIL_ON_ERROR=false run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(posted)" -eq 0 ]
  [ "$(output_of eligible-count)" = "0" ]
}

@test "a dry run lists the eligible runs in the summary, oldest first, and cancels none" {
  list_queued 1:$((30 * H)) 2:$((50 * H)) 3:60
  DRY_RUN=true run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(posted)" -eq 0 ]
  [ "$(output_of cancelled-run-ids)" = "[]" ]
  [ "$(grep '^- \[' "$GITHUB_STEP_SUMMARY" | sed -E 's/^- \[([0-9]+)\].*/\1/' | tr '\n' ' ')" = "2 1 " ]
}

@test "a real run lists only the cancelled runs in the summary, not the skipped ones" {
  list_queued 1:$((30 * H)) 2:$((50 * H))
  answer_post 1 202; answer_post 2 404 "Not Found"
  run "$SCRIPT"
  [ "$(grep -c '^- \[' "$GITHUB_STEP_SUMMARY")" -eq 1 ]
  grep -qF -- '- [1](' "$GITHUB_STEP_SUMMARY"
}

@test "the log line shows the runs found whatever their age, before the eligible ones" {
  add_rule GET '*actions/runs*status=queued*per_page=1 *' 200 '{"total_count":4}'
  list_queued 1:60 2:120
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Found: 4, eligible: 0, cancelled: 0, skipped: 0, failed: 0"* ]] || false
}

@test "the log line shows a dash for the found runs when the count is not available" {
  list_queued
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Found: -, eligible: 0,"* ]] || false
}
