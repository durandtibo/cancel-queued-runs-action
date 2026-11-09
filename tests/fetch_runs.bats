#!/usr/bin/env bats

setup() {
  # Ensure consistent test directory
  TEST_DIR="$BATS_TEST_DIRNAME"
  MOCK_DIR="$TEST_DIR/mocks"
  mkdir -p "$MOCK_DIR"

  # Absolute path for logs (macOS BATS sometimes changes CWD)
  export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
  echo -n > "$MOCK_GH_CALL_LOG"

  # Prepend mocks to PATH
  PATH="$MOCK_DIR:$PATH"

  export REPO="myorg/myrepo"
  unset WORKFLOW STATUSES

  # Create mock gh command
  # It applies the --jq filter to the JSON in $MOCK_GH_RESPONSE_FILE with the
  # real jq, like gh does, so that the filter used by fetch_runs is tested.
  export MOCK_GH_RESPONSE_FILE="$MOCK_DIR/response.json"
  cat > "$MOCK_GH_RESPONSE_FILE" << 'JSON'
{
  "workflow_runs": [
    {
      "id": 111,
      "created_at": "2025-01-01T09:00:00Z",
      "run_started_at": "2025-01-01T10:00:00Z",
      "updated_at": "2025-01-01T12:00:00Z"
    },
    {
      "id": 222,
      "created_at": "2025-01-01T11:00:00Z",
      "run_started_at": null,
      "updated_at": "2025-01-01T13:00:00Z"
    }
  ]
}
JSON

  cat > "$MOCK_DIR/gh" << EOF
#!/usr/bin/env bash

# Log request arguments
echo "\$@" >> "$MOCK_GH_CALL_LOG"

# Find the --jq filter, if any
filter=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--jq" ]; then
    filter="\$2"
  fi
  shift
done

if [ -n "\$filter" ]; then
  jq -c "\$filter" "$MOCK_GH_RESPONSE_FILE"
else
  cat "$MOCK_GH_RESPONSE_FILE"
fi
EOF

  chmod +x "$MOCK_DIR/gh"

  # Load the script under test
  # Use absolute path to avoid macOS BATS cwd issues
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}


@test "fetch_runs returns one JSON object per run with id and queued_at" {
  run fetch_runs

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(echo "$output" | head -n1 | jq -r '.id')" = "111" ]
  [ "$(echo "$output" | tail -n1 | jq -r '.id')" = "222" ]
}

@test "fetch_runs uses updated_at as queued_at" {
  run fetch_runs

  [ "$(echo "$output" | head -n1 | jq -r '.queued_at')" = "2025-01-01T12:00:00Z" ]
  [ "$(echo "$output" | tail -n1 | jq -r '.queued_at')" = "2025-01-01T13:00:00Z" ]
}

@test "fetch_runs does not use created_at or run_started_at" {
  run fetch_runs

  [[ ! "$output" =~ "2025-01-01T09:00:00Z" ]]
  [[ ! "$output" =~ "2025-01-01T10:00:00Z" ]]
  [[ ! "$output" =~ "2025-01-01T11:00:00Z" ]]
  [[ ! "$output" =~ "created_at" ]]
  [[ ! "$output" =~ "run_started_at" ]]
}

@test "fetch_runs returns nothing when there are no queued runs" {
  echo '{"workflow_runs": []}' > "$MOCK_GH_RESPONSE_FILE"

  run fetch_runs

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fetch_runs calls gh with correct arguments" {
  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"

  # REGEX matching is OK because BATS forces bash
  [[ "$log_contents" =~ api ]]
  [[ "$log_contents" =~ "-H" ]]
  [[ "$log_contents" =~ "Accept: application/vnd.github+json" ]]
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs?status=queued&per_page=100" ]]
  [[ "$log_contents" =~ "--paginate" ]]
  [[ "$log_contents" =~ "--jq" ]]
  [[ "$log_contents" =~ ".workflow_runs" ]]
}

@test "fetch_runs obeys REPO environment variable" {
  export REPO="otherorg/coolrepo"

  # Reset log
  echo -n > "$MOCK_GH_CALL_LOG"

  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"

  [[ "$log_contents" =~ "/repos/otherorg/coolrepo/actions/runs" ]]
}

@test "fetch_runs lists the runs of all the workflows by default" {
  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs?status=queued&per_page=100" ]]
  [[ ! "$log_contents" =~ "/workflows/" ]]
}

@test "fetch_runs lists only the runs of a workflow file name when WORKFLOW is set" {
  export WORKFLOW="ci.yaml"

  run fetch_runs

  [ "$status" -eq 0 ]
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/workflows/ci.yaml/runs?status=queued&per_page=100" ]]
}

@test "fetch_runs lists only the runs of a workflow ID when WORKFLOW is set" {
  export WORKFLOW="161335"

  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/workflows/161335/runs?status=queued&per_page=100" ]]
}

@test "fetch_runs returns the same fields with a workflow filter" {
  export WORKFLOW="ci.yaml"

  run fetch_runs

  [ "$(echo "$output" | head -n1 | jq -r '.id')" = "111" ]
  [ "$(echo "$output" | head -n1 | jq -r '.queued_at')" = "2025-01-01T10:00:00Z" ]
}

@test "fetch_runs lists only the queued runs by default" {
  run fetch_runs

  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 1 ]
  [[ "$(cat "$MOCK_GH_CALL_LOG")" =~ "status=queued&per_page=100" ]]
}

@test "fetch_runs makes one call per status" {
  export STATUSES="queued,waiting"

  run fetch_runs

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 2 ]
  grep -q "status=queued&per_page=100" "$MOCK_GH_CALL_LOG"
  grep -q "status=waiting&per_page=100" "$MOCK_GH_CALL_LOG"
}

@test "fetch_runs concatenates the runs of all the statuses" {
  export STATUSES="queued,waiting"

  run fetch_runs

  # the mock returns two runs per call
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 4 ]
}

@test "fetch_runs ignores spaces around the commas" {
  export STATUSES="queued, waiting"

  run fetch_runs

  grep -q "status=waiting&per_page=100" "$MOCK_GH_CALL_LOG"
}

@test "fetch_runs lists a duplicated status only once" {
  export STATUSES="queued,queued"

  run fetch_runs

  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 1 ]
}

@test "fetch_runs combines the statuses with the workflow filter" {
  export STATUSES="pending,requested"
  export WORKFLOW="ci.yaml"

  run fetch_runs

  grep -q "/actions/workflows/ci.yaml/runs?status=pending&per_page=100" "$MOCK_GH_CALL_LOG"
  grep -q "/actions/workflows/ci.yaml/runs?status=requested&per_page=100" "$MOCK_GH_CALL_LOG"
}

@test "fetch_runs makes no call and succeeds when STATUSES is empty" {
  export STATUSES=""

  run fetch_runs

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$MOCK_GH_CALL_LOG" ]
}
