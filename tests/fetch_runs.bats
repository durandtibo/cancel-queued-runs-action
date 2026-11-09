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
  unset WORKFLOW STATUSES MOCK_GH_FAIL_PATTERN MOCK_GH_FAIL_TIMES MOCK_GH_FAIL_MESSAGE
  # the failures of the tests are HTTP 500, which is retried: tests about the
  # retries set their own value
  export MAX_RETRIES=0
  export RETRY_BASE_DELAY=5
  export RETRY_MAX_DELAY=60

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
all_args="\$*"

# Fail like gh does for an HTTP error when the arguments match the pattern
# The first MOCK_GH_FAIL_TIMES calls fail (all of them when it is unset)
if [ -n "\${MOCK_GH_FAIL_PATTERN:-}" ] && [[ "\$*" == *"\$MOCK_GH_FAIL_PATTERN"* ]]; then
  fails=\$(cat "$MOCK_DIR/fail_count" 2>/dev/null || echo 0)
  if [ -z "\${MOCK_GH_FAIL_TIMES:-}" ] || [ "\$fails" -lt "\$MOCK_GH_FAIL_TIMES" ]; then
    echo \$((fails + 1)) > "$MOCK_DIR/fail_count"
    echo "\${MOCK_GH_FAIL_MESSAGE:-gh: Server Error (HTTP 500)}" >&2
    exit 1
  fi
fi

# Find the --jq filter, if any
filter=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--jq" ]; then
    filter="\$2"
  fi
  shift
done

# Another response can be given for the status waiting
response_file="$MOCK_GH_RESPONSE_FILE"
if [ -n "\${MOCK_GH_RESPONSE_FILE_WAITING:-}" ] && [[ "\$all_args" == *"status=waiting"* ]]; then
  response_file="\$MOCK_GH_RESPONSE_FILE_WAITING"
fi

if [ -n "\$filter" ]; then
  jq -c "\$filter" "\$response_file"
else
  cat "\$response_file"
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

  [[ ! "$output" =~ "2025-01-01T09:00:00Z" ]] || false
  [[ ! "$output" =~ "2025-01-01T10:00:00Z" ]] || false
  [[ ! "$output" =~ "2025-01-01T11:00:00Z" ]] || false
  [[ ! "$output" =~ "created_at" ]] || false
  [[ ! "$output" =~ "run_started_at" ]] || false
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
  [[ "$log_contents" =~ api ]] || false
  [[ "$log_contents" =~ "-H" ]] || false
  [[ "$log_contents" =~ "Accept: application/vnd.github+json" ]] || false
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs?status=queued&per_page=100" ]] || false
  [[ "$log_contents" =~ "--paginate" ]] || false
  [[ "$log_contents" =~ "--jq" ]] || false
  [[ "$log_contents" =~ ".workflow_runs" ]] || false
}

@test "fetch_runs obeys REPO environment variable" {
  export REPO="otherorg/coolrepo"

  # Reset log
  echo -n > "$MOCK_GH_CALL_LOG"

  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"

  [[ "$log_contents" =~ "/repos/otherorg/coolrepo/actions/runs" ]] || false
}

@test "fetch_runs lists the runs of all the workflows by default" {
  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs?status=queued&per_page=100" ]] || false
  [[ ! "$log_contents" =~ "/workflows/" ]] || false
}

@test "fetch_runs lists only the runs of a workflow file name when WORKFLOW is set" {
  export WORKFLOW="ci.yaml"

  run fetch_runs

  [ "$status" -eq 0 ]
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/workflows/ci.yaml/runs?status=queued&per_page=100" ]] || false
}

@test "fetch_runs lists only the runs of a workflow ID when WORKFLOW is set" {
  export WORKFLOW="161335"

  run fetch_runs

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/workflows/161335/runs?status=queued&per_page=100" ]] || false
}

@test "fetch_runs returns the same fields with a workflow filter" {
  export WORKFLOW="ci.yaml"

  run fetch_runs

  [ "$(echo "$output" | head -n1 | jq -r '.id')" = "111" ]
  [ "$(echo "$output" | head -n1 | jq -r '.queued_at')" = "2025-01-01T12:00:00Z" ]
}

@test "fetch_runs lists only the queued runs by default" {
  run fetch_runs

  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 1 ]
  [[ "$(cat "$MOCK_GH_CALL_LOG")" =~ "status=queued&per_page=100" ]] || false
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
  export MOCK_GH_RESPONSE_FILE_WAITING="$MOCK_DIR/response_waiting.json"
  echo '{"workflow_runs": [{"id": 333, "updated_at": "2025-01-01T14:00:00Z"}]}' > "$MOCK_GH_RESPONSE_FILE_WAITING"

  run fetch_runs

  # two runs for queued, one for waiting
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
  echo "$output" | grep -q '"id":111'
  echo "$output" | grep -q '"id":222'
  echo "$output" | grep -q '"id":333'
}

@test "fetch_runs prints a run listed under two statuses only once" {
  export STATUSES="queued,waiting"
  export MOCK_GH_RESPONSE_FILE_WAITING="$MOCK_DIR/response_waiting.json"
  # run 222 changed its status between the two calls and is listed again
  echo '{"workflow_runs": [{"id": 222, "updated_at": "2025-01-01T13:00:00Z"}, {"id": 333, "updated_at": "2025-01-01T14:00:00Z"}]}' > "$MOCK_GH_RESPONSE_FILE_WAITING"

  run fetch_runs

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
  [ "$(echo "$output" | grep -c '"id":222')" -eq 1 ]
}

@test "fetch_runs keeps the order of the listing when it removes duplicates" {
  export STATUSES="queued,waiting"
  export MOCK_GH_RESPONSE_FILE_WAITING="$MOCK_DIR/response_waiting.json"
  echo '{"workflow_runs": [{"id": 333, "updated_at": "2025-01-01T14:00:00Z"}, {"id": 111, "updated_at": "2025-01-01T12:00:00Z"}]}' > "$MOCK_GH_RESPONSE_FILE_WAITING"

  run fetch_runs

  [ "$(echo "$output" | sed -n 1p | jq -r .id)" = "111" ]
  [ "$(echo "$output" | sed -n 2p | jq -r .id)" = "222" ]
  [ "$(echo "$output" | sed -n 3p | jq -r .id)" = "333" ]
}

@test "fetch_runs prints each run once when the same status is given twice" {
  export STATUSES="queued,queued"

  run fetch_runs

  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
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

@test "fetch_runs fails when the gh call fails" {
  export MOCK_GH_FAIL_PATTERN="status=queued"

  run fetch_runs

  [ "$status" -eq 1 ]
}

@test "fetch_runs fails when the gh call of the first status fails and the next one succeeds" {
  export STATUSES="queued,waiting"
  export MOCK_GH_FAIL_PATTERN="status=queued"

  run fetch_runs

  [ "$status" -eq 1 ]
}

@test "fetch_runs fails when the gh call of the last status fails" {
  export STATUSES="queued,waiting"
  export MOCK_GH_FAIL_PATTERN="status=waiting"

  run fetch_runs

  [ "$status" -eq 1 ]
}

@test "fetch_runs stops at the first failing status" {
  export STATUSES="queued,waiting"
  export MOCK_GH_FAIL_PATTERN="status=queued"

  run fetch_runs

  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 1 ]
}

@test "fetch_runs warns when the number of runs of a status reaches the limit" {
  RUNS_LISTING_LIMIT=2

  err=$(fetch_runs 2>&1 >/dev/null)

  [[ "$err" == *"::warning::2 runs were listed for the status 'queued'"* ]] || false
}

@test "fetch_runs does not warn below the limit" {
  RUNS_LISTING_LIMIT=3

  err=$(fetch_runs 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "fetch_runs does not warn with the default limit" {
  err=$(fetch_runs 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "fetch_runs warns for the status that reached the limit only" {
  export STATUSES="queued,waiting"
  RUNS_LISTING_LIMIT=2
  # waiting returns a single run, so only queued reaches the limit
  cat > "$MOCK_DIR/gh" << MOCK
#!/usr/bin/env bash
filter=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--jq" ]; then filter="\$2"; fi
  if [[ "\$1" == *"status=waiting"* ]]; then waiting=1; fi
  shift
done
if [ -n "\${waiting:-}" ]; then
  jq -c '.workflow_runs[:1][] | {id: .id, queued_at: .updated_at}' "$MOCK_GH_RESPONSE_FILE"
else
  jq -c "\$filter" "$MOCK_GH_RESPONSE_FILE"
fi
MOCK

  err=$(fetch_runs 2>&1 >/dev/null)

  echo "$err" | grep -q "status 'queued'"
  [ "$(echo "$err" | grep -c "status 'waiting'" || true)" -eq 0 ]
}

@test "fetch_runs still prints every run when the limit is reached" {
  RUNS_LISTING_LIMIT=2

  out=$(fetch_runs 2>/dev/null)

  [ "$(echo "$out" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "fetch_runs does not warn when nothing is listed" {
  RUNS_LISTING_LIMIT=1
  echo '{"workflow_runs": []}' > "$MOCK_GH_RESPONSE_FILE"

  err=$(fetch_runs 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "fetch_runs sets LISTING_TRUNCATED when the number of runs reaches the limit" {
  RUNS_LISTING_LIMIT=2

  fetch_runs >/dev/null 2>&1

  [ "$LISTING_TRUNCATED" = "true" ]
}

@test "fetch_runs does not set LISTING_TRUNCATED below the limit" {
  RUNS_LISTING_LIMIT=3

  fetch_runs >/dev/null 2>&1

  [ "$LISTING_TRUNCATED" = "false" ]
}

@test "fetch_runs resets LISTING_TRUNCATED from a previous call" {
  LISTING_TRUNCATED=true

  fetch_runs >/dev/null 2>&1

  [ "$LISTING_TRUNCATED" = "false" ]
}

@test "fetch_runs sets LISTING_TRUNCATED when only one of the statuses reaches the limit" {
  export STATUSES="queued,waiting"
  export MOCK_GH_RESPONSE_FILE_WAITING="$MOCK_DIR/response_waiting.json"
  echo '{"workflow_runs": [{"id": 333, "updated_at": "2025-01-01T14:00:00Z"}]}' > "$MOCK_GH_RESPONSE_FILE_WAITING"
  RUNS_LISTING_LIMIT=2

  fetch_runs >/dev/null 2>&1

  [ "$LISTING_TRUNCATED" = "true" ]
}

# --------------------------------------------------------
# Retries of the listing
# --------------------------------------------------------

@test "fetch_runs retries a listing that fails with a transient error" {
  export MAX_RETRIES=3
  sleep() { :; }
  export MOCK_GH_FAIL_PATTERN="status=queued"
  export MOCK_GH_FAIL_TIMES=2

  run fetch_runs

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '"id"')" -eq 2 ]
  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 3 ]
}

@test "fetch_runs fails when a transient error lasts longer than the retries" {
  export MAX_RETRIES=2
  sleep() { :; }
  export MOCK_GH_FAIL_PATTERN="status=queued"

  run fetch_runs

  [ "$status" -eq 1 ]
  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 3 ]
}

@test "fetch_runs does not retry an error that is not transient" {
  export MAX_RETRIES=3
  sleep() { echo "slept" >> "$MOCK_DIR/sleep.log"; }
  export MOCK_GH_FAIL_PATTERN="status=queued"
  export MOCK_GH_FAIL_MESSAGE="gh: Not Found (HTTP 404)"

  run fetch_runs

  [ "$status" -eq 1 ]
  [ "$(wc -l < "$MOCK_GH_CALL_LOG" | tr -d ' ')" -eq 1 ]
  [ ! -e "$MOCK_DIR/sleep.log" ]
}

@test "fetch_runs retries each status on its own" {
  export MAX_RETRIES=3
  sleep() { :; }
  export STATUSES="queued,waiting"
  export MOCK_GH_FAIL_PATTERN="status=waiting"
  export MOCK_GH_FAIL_TIMES=1

  run fetch_runs

  [ "$status" -eq 0 ]
  [ "$(grep -c 'status=queued' "$MOCK_GH_CALL_LOG")" -eq 1 ]
  [ "$(grep -c 'status=waiting' "$MOCK_GH_CALL_LOG")" -eq 2 ]
}

@test "fetch_runs sets LISTING_TRUNCATED after a retry" {
  export MAX_RETRIES=3
  sleep() { :; }
  export MOCK_GH_FAIL_PATTERN="status=queued"
  export MOCK_GH_FAIL_TIMES=1
  RUNS_LISTING_LIMIT=2

  fetch_runs > /dev/null 2>&1

  [ "$LISTING_TRUNCATED" = "true" ]
}
