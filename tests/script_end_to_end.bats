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

  export REPO="myorg/myrepo"
  export GH_TOKEN="test-token"
  export MAX_AGE_HOURS=24
  unset DRY_RUN WORKFLOW STATUSES MOCK_GH_POST_CODE CANCEL_DELAY_SECONDS FAIL_ON_ERROR
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
