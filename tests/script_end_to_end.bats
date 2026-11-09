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
  # 2020: far older than any threshold (force-cancel tier)
  # 2999: in the future, never old enough
  cat > "$MOCK_GH_RUNS" << 'JSON'
{
  "workflow_runs": [
    {"id": 111, "created_at": "2020-01-01T00:00:00Z", "run_started_at": "2020-01-01T00:00:00Z"},
    {"id": 222, "created_at": "2999-01-01T00:00:00Z", "run_started_at": "2999-01-01T00:00:00Z"}
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
  printf 'HTTP/2.0 202 Accepted\n\n{}\n'
  exit 0
fi

filter=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--jq" ]; then filter="$2"; fi
  shift
done
jq -c "$filter" "$MOCK_GH_RUNS"
MOCK
  chmod +x "$MOCK_DIR/gh"

  export REPO="myorg/myrepo"
  export GH_TOKEN="test-token"
  export MAX_AGE_HOURS=24
  unset DRY_RUN
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

posts() { grep -c -- "-X POST" "$MOCK_GH_CALL_LOG" || true; }

@test "end-to-end: cancels the old run and leaves the recent one alone" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 2 queued workflow run(s)." ]]
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
