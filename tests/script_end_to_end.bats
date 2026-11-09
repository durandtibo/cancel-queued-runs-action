#!/usr/bin/env bats
#
# End-to-end tests: run scripts/cancel.sh as a process with a fake gh.

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
  export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
  : > "$MOCK_GH_CALL_LOG"

  export MOCK_GH_RUNS="$MOCK_DIR/runs.json"
  # updated_at: 2020 is far older than any threshold (force-cancel tier)
  # 2999: in the future, never old enough
  cat > "$MOCK_GH_RUNS" << 'JSON'
{
  "workflow_runs": [
    {"id": 111, "created_at": "2020-01-01T00:00:00Z", "updated_at": "2020-01-01T00:00:00Z"},
    {"id": 222, "created_at": "2999-01-01T00:00:00Z", "updated_at": "2999-01-01T00:00:00Z"}
  ]
}
JSON

  # Runs that wait for an approval (status=waiting)
  export MOCK_GH_RUNS_WAITING="$MOCK_DIR/runs_waiting.json"
  cat > "$MOCK_GH_RUNS_WAITING" << 'JSON'
{
  "workflow_runs": [
    {"id": 333, "created_at": "2020-01-01T00:00:00Z", "updated_at": "2020-01-01T00:00:00Z"}
  ]
}
JSON

  # Fake gh: lists runs for GET requests, answers 202 to cancel POSTs
  cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_GH_CALL_LOG"

if [ "$1" = "auth" ]; then
  exit 0
fi

if [[ "$*" == *"-X POST"* ]]; then
  # Replay a recorded response (CRLF line endings), failing like gh does for
  # an HTTP error: response on stdout, message on stderr, exit code 1
  if [ -n "${MOCK_GH_POST_FIXTURE:-}" ]; then
    cat "$FIXTURE_DIR/$MOCK_GH_POST_FIXTURE"
    code=$(head -n1 "$FIXTURE_DIR/$MOCK_GH_POST_FIXTURE" | tr -d '\r' | awk '{print $2}')
    if [ "${code:0:1}" != "2" ]; then
      echo "gh: Error (HTTP $code)" >&2
      exit 1
    fi
    exit 0
  fi
  # Fail like gh does for an HTTP error: response on stdout, message on stderr
  if [ -n "${MOCK_GH_POST_CODE:-}" ]; then
    printf 'HTTP/2.0 %s Error\n\n{}\n' "$MOCK_GH_POST_CODE"
    echo "gh: Error (HTTP $MOCK_GH_POST_CODE)" >&2
    exit 1
  fi
  printf 'HTTP/2.0 202 Accepted\n\n{}\n'
  exit 0
fi

runs_file="$MOCK_GH_RUNS"
if [[ "$*" == *"status=waiting"* ]]; then
  runs_file="$MOCK_GH_RUNS_WAITING"
fi

filter=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--jq" ]; then filter="$2"; fi
  shift
done
jq -c "$filter" "$runs_file"
MOCK
  chmod +x "$MOCK_DIR/gh"

  export FIXTURE_DIR="$BATS_TEST_DIRNAME/fixtures"
  export REPO="myorg/myrepo"
  export GH_TOKEN="test-token"
  export MAX_AGE_HOURS=24
  unset MOCK_GH_POST_FIXTURE MAX_RETRIES RETRY_BASE_DELAY RETRY_MAX_DELAY DRY_RUN WORKFLOW STATUSES MOCK_GH_POST_CODE CANCEL_DELAY_SECONDS FAIL_ON_ERROR SUMMARY_MAX_RUNS RUNS_LISTING_LIMIT
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

posts() { grep -c -- "-X POST" "$MOCK_GH_CALL_LOG" || true; }

@test "end-to-end: cancels the old run and leaves the recent one alone" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 2 workflow run(s)." ]]
  [[ "$output" =~ "Force-cancelling run 111" ]]
  [[ ! "$output" =~ "Cancelling run 222" ]]
  [[ ! "$output" =~ "Force-cancelling run 222" ]]
  grep -q "/repos/myorg/myrepo/actions/runs/111/cancel" "$MOCK_GH_CALL_LOG"
  run grep -q "runs/222/" "$MOCK_GH_CALL_LOG"
  [ "$status" -ne 0 ]
}

@test "end-to-end: a dry run sends no cancel request at all" {
  export DRY_RUN=true

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dry run enabled" ]]
  [[ "$output" =~ "[dry-run] Would force-cancel run 111" ]]
  [ "$(posts)" -eq 0 ]
}

@test "end-to-end: an invalid input fails before any API call" {
  export REPO="not-valid"

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO must be in owner/name format" ]]
  [ ! -s "$MOCK_GH_CALL_LOG" ]
}

@test "end-to-end: writes the outputs and the summary" {
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qx "found_count=2" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=1" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
  grep -qx "would_cancel_count=0" "$GITHUB_OUTPUT"
  grep -q "Cancelled | 1 |" "$GITHUB_STEP_SUMMARY"
}

@test "end-to-end: dry run reports would_cancel_count and no cancelled run" {
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"
  export DRY_RUN=true

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qx "cancelled_count=0" "$GITHUB_OUTPUT"
  grep -qx "would_cancel_count=1" "$GITHUB_OUTPUT"
}

@test "end-to-end: the workflow filter is used to list the runs" {
  export WORKFLOW="ci.yaml"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Only the runs of the workflow ci.yaml are considered." ]]
  grep -q "/repos/myorg/myrepo/actions/workflows/ci.yaml/runs" "$MOCK_GH_CALL_LOG"
  grep -q "/repos/myorg/myrepo/actions/runs/111/cancel" "$MOCK_GH_CALL_LOG"
}

@test "end-to-end: runs waiting for approval are ignored by default" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  run grep -q "status=waiting" "$MOCK_GH_CALL_LOG"
  [ "$status" -ne 0 ]
  run grep -q "runs/333/" "$MOCK_GH_CALL_LOG"
  [ "$status" -ne 0 ]
}

@test "end-to-end: runs waiting for approval are cancelled when requested" {
  export STATUSES="queued,waiting"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Run statuses considered: queued,waiting" ]]
  [[ "$output" =~ "Found 3 workflow run(s)." ]]
  grep -q "/repos/myorg/myrepo/actions/runs/111/cancel" "$MOCK_GH_CALL_LOG"
  grep -q "/repos/myorg/myrepo/actions/runs/333/cancel" "$MOCK_GH_CALL_LOG"
}

@test "end-to-end: a run that is no longer cancellable (409) gives a single warning" {
  export MOCK_GH_POST_CODE=409

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '::warning::')" -eq 1 ]
  [[ "$output" =~ "::warning::Run 111 could not be cancelled (HTTP 409)" ]]
}

@test "end-to-end: a real API error (500) still shows the gh message" {
  export MOCK_GH_POST_CODE=500

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::warning::gh api (cancel) failed for run 111: gh: Error (HTTP 500)" ]]
}

# Two runs old enough to be cancelled, and a fake sleep that records its argument
setup_two_old_runs() {
  cat > "$MOCK_GH_RUNS" << 'JSON'
{
  "workflow_runs": [
    {"id": 111, "created_at": "2020-01-01T00:00:00Z", "updated_at": "2020-01-01T00:00:00Z"},
    {"id": 112, "created_at": "2020-01-01T00:00:00Z", "updated_at": "2020-01-01T00:00:00Z"}
  ]
}
JSON
  export MOCK_SLEEP_LOG="$MOCK_DIR/sleep.log"
  : > "$MOCK_SLEEP_LOG"
  printf '#!/usr/bin/env bash\necho "$@" >> "$MOCK_SLEEP_LOG"\n' > "$MOCK_DIR/sleep"
  chmod +x "$MOCK_DIR/sleep"
}

@test "end-to-end: waits between the cancel requests when CANCEL_DELAY_SECONDS is set" {
  setup_two_old_runs
  export CANCEL_DELAY_SECONDS=7

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posts)" -eq 2 ]
  [ "$(cat "$MOCK_SLEEP_LOG")" = "7" ]
}

@test "end-to-end: does not wait between the cancel requests by default" {
  setup_two_old_runs

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posts)" -eq 2 ]
  [ ! -s "$MOCK_SLEEP_LOG" ]
}

@test "end-to-end: an invalid CANCEL_DELAY_SECONDS fails before any API call" {
  export CANCEL_DELAY_SECONDS=abc

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "CANCEL_DELAY_SECONDS must be a non-negative integer" ]] || false
  [ "$(posts)" -eq 0 ]
}

@test "end-to-end: a failed cancellation fails the step by default" {
  export MOCK_GH_POST_CODE=500

  run "$SCRIPT"

  [ "$status" -eq 1 ]
}

@test "end-to-end: a failed cancellation does not fail the step when FAIL_ON_ERROR is false" {
  export MOCK_GH_POST_CODE=500
  export FAIL_ON_ERROR=false
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qx "failed_count=1" "$GITHUB_OUTPUT"
  grep -qx "cancelled_count=0" "$GITHUB_OUTPUT"
}

@test "end-to-end: an invalid FAIL_ON_ERROR fails before any API call" {
  export FAIL_ON_ERROR=nope

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "FAIL_ON_ERROR must be 'true' or 'false'" ]] || false
  [ "$(posts)" -eq 0 ]
}

@test "end-to-end: the summary lists the cancelled run and not the recent one" {
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -q '^| \[111\](https://github.com/myorg/myrepo/actions/runs/111) | .* | Cancelled |$' "$GITHUB_STEP_SUMMARY"
  [ -z "$(grep 'runs/222' "$GITHUB_STEP_SUMMARY" || true)" ]
}

@test "end-to-end: the summary lists the runs that would be cancelled in a dry run" {
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
  export DRY_RUN=true

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -q 'runs/111) | .* | Would be cancelled (dry run) |$' "$GITHUB_STEP_SUMMARY"
}

@test "end-to-end: the summary lists a failed run" {
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
  export MOCK_GH_POST_CODE=500

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  grep -q 'runs/111) | .* | Failed |$' "$GITHUB_STEP_SUMMARY"
}

@test "end-to-end: the summary lists the runs of the link of GITHUB_SERVER_URL" {
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
  export GITHUB_SERVER_URL="https://ghe.example.com"

  run "$SCRIPT"

  grep -qF '(https://ghe.example.com/myorg/myrepo/actions/runs/111)' "$GITHUB_STEP_SUMMARY"
}

@test "end-to-end: the summary lists at most SUMMARY_MAX_RUNS runs" {
  setup_two_old_runs
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
  export SUMMARY_MAX_RUNS=1

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -q 'runs/111)' "$GITHUB_STEP_SUMMARY"
  [ -z "$(grep 'runs/112)' "$GITHUB_STEP_SUMMARY" || true)" ]
  grep -qx '1 more run(s) are not listed here, see the logs of the step.' "$GITHUB_STEP_SUMMARY"
}

@test "end-to-end: reports listing_truncated=false when the listing is complete" {
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qx "listing_truncated=false" "$GITHUB_OUTPUT"
}

@test "end-to-end: reports listing_truncated=true when the listing reaches the limit" {
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  export GITHUB_STEP_SUMMARY="$MOCK_DIR/summary.md"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  # the mock lists 2 runs: that is the limit here
  export RUNS_LISTING_LIMIT=2

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::2 runs were listed for the status 'queued'" ]] || false
  grep -qx "listing_truncated=true" "$GITHUB_OUTPUT"
  grep -q 'maximum that GitHub returns' "$GITHUB_STEP_SUMMARY"
}

# --------------------------------------------------------
# Recorded responses of gh api -i (CRLF line endings)
# Run 111 is old enough for the force-cancel tier: the cancel request, then
# the force-cancel request when the first one is not accepted.
# --------------------------------------------------------

@test "end-to-end: a recorded 202 response cancels the run with a single request" {
  export MOCK_GH_POST_FIXTURE=response_202.http

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Cancellation request accepted for run 111" ]] || false
  [ "$(posts)" -eq 1 ]
}

@test "end-to-end: a recorded 404 response skips the run without a force-cancel request" {
  export MOCK_GH_POST_FIXTURE=response_404.http
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posts)" -eq 1 ]
  grep -qx "skipped_count=1" "$GITHUB_OUTPUT"
  grep -qx "failed_count=0" "$GITHUB_OUTPUT"
}

@test "end-to-end: a recorded 409 response skips the run after the force-cancel request" {
  export MOCK_GH_POST_FIXTURE=response_409.http
  export GITHUB_OUTPUT="$MOCK_DIR/github_output"
  : > "$GITHUB_OUTPUT"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posts)" -eq 2 ]
  grep -qx "skipped_count=1" "$GITHUB_OUTPUT"
}

@test "end-to-end: a recorded 500 response fails the run" {
  export MOCK_GH_POST_FIXTURE=response_500.http

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Cancellation failed for run 111" ]] || false
}

@test "end-to-end: a recorded 403 for a missing permission fails without any retry" {
  export MOCK_GH_POST_FIXTURE=response_403_forbidden.http

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Status code: 403 for run 111" ]] || false
  [[ ! "$output" =~ "Rate limited" ]] || false
}

@test "end-to-end: a recorded 429 response that asks for a long wait is not retried" {
  export MOCK_GH_POST_FIXTURE=response_429.http
  export RETRY_MAX_DELAY=5

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Rate limited on run 111 (cancel), giving up (needs 60s" ]] || false
}

@test "end-to-end: a recorded secondary rate limit that asks for a long wait is not retried" {
  export MOCK_GH_POST_FIXTURE=response_403_secondary_rate_limit.http
  export RETRY_MAX_DELAY=5

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Rate limited on run 111 (cancel), giving up (needs 30s" ]] || false
}

@test "end-to-end: a recorded exhausted primary rate limit is retried once, then given up" {
  export MOCK_GH_POST_FIXTURE=response_403_primary_rate_limit.http
  # the reset time of the fixture is long past: the wait is the 1 second minimum
  export MAX_RETRIES=1

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Rate limited on run 111 (cancel), retrying in 1s (retry 1/1)" ]] || false
  [[ "$output" =~ "Rate limited on run 111 (cancel), giving up" ]] || false
}
