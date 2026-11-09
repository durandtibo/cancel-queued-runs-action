#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR/tmp"
  export TMPDIR="$MOCK_DIR/tmp"
  export GH_LOG="$MOCK_DIR/gh_calls.log"
  export SLEEP_LOG="$MOCK_DIR/sleep.log"
  : > "$GH_LOG"
  : > "$SLEEP_LOG"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  WORK_DIR=""
  BRANCH=""
  EVENT=""
  MAX_RETRIES=3
  RETRY_BASE_DELAY=5
  RETRY_MAX_DELAY=60

  # The first MOCK_FAILS calls fail with MOCK_ERROR on stderr (and print a
  # partial page first when MOCK_PARTIAL is set), the next ones succeed
  gh() {
    echo "$*" >> "$GH_LOG"
    local calls
    calls=$(wc -l < "$GH_LOG" | tr -d ' ')
    if [ "$calls" -le "${MOCK_FAILS:-0}" ]; then
      if [ -n "${MOCK_PARTIAL:-}" ]; then
        echo '{"id":1,"queued_at":"2025-01-01T00:00:00Z"}'
      fi
      echo "${MOCK_ERROR:-gh: Server Error (HTTP 500)}" >&2
      return 1
    fi
    if [ -n "${MOCK_WARNING:-}" ]; then
      echo "$MOCK_WARNING" >&2
    fi
    if [ -z "${MOCK_EMPTY:-}" ]; then
      echo '{"id":1,"queued_at":"2025-01-01T00:00:00Z"}'
      echo '{"id":2,"queued_at":"2025-01-02T00:00:00Z"}'
    fi
  }

  sleep() { echo "$1" >> "$SLEEP_LOG"; }
}

teardown() {
  rm -rf "$MOCK_DIR"
}

gh_calls() { wc -l < "$GH_LOG" | tr -d ' '; }

# --------------------------------------------------------
# Success
# --------------------------------------------------------

@test "list_runs_of_status prints one run per line" {
  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(echo "$output" | head -n1)" = '{"id":1,"queued_at":"2025-01-01T00:00:00Z"}' ]
}

@test "list_runs_of_status prints nothing when there is no run" {
  export MOCK_EMPTY=1

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list_runs_of_status asks for the status, 100 runs per page and all the pages" {
  list_runs_of_status "/repos/o/r/actions/runs" waiting > /dev/null

  [[ "$(cat "$GH_LOG")" == *"/repos/o/r/actions/runs?status=waiting&per_page=100"* ]] || false
  [[ "$(cat "$GH_LOG")" == *"--paginate"* ]] || false
}

@test "list_runs_of_status uses the path it is given" {
  list_runs_of_status "/repos/o/r/actions/workflows/ci.yaml/runs" queued > /dev/null

  [[ "$(cat "$GH_LOG")" == *"/repos/o/r/actions/workflows/ci.yaml/runs?status=queued"* ]] || false
}

@test "list_runs_of_status makes a single call when it succeeds" {
  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [ "$(gh_calls)" -eq 1 ]
  [ ! -s "$SLEEP_LOG" ]
}

@test "list_runs_of_status forwards what gh writes on stderr when it succeeds" {
  export MOCK_WARNING="gh: a warning"

  err=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2>&1 > /dev/null)

  [ "$err" = "gh: a warning" ]
}

@test "list_runs_of_status is silent when gh is" {
  err=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2>&1 > /dev/null)

  [ -z "$err" ]
}

# --------------------------------------------------------
# Retries
# --------------------------------------------------------

@test "list_runs_of_status retries after a transient error and succeeds" {
  export MOCK_FAILS=1

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 0 ]
  [ "$(gh_calls)" -eq 2 ]
}

@test "list_runs_of_status prints the runs of the successful attempt only" {
  export MOCK_FAILS=1

  out=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2> /dev/null)

  [ "$(echo "$out" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "list_runs_of_status does not print the pages received before a failure" {
  export MOCK_FAILS=1
  export MOCK_PARTIAL=1

  out=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2> /dev/null)

  [ "$(echo "$out" | grep -c '"id":1')" -eq 1 ]
  [ "$(echo "$out" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "list_runs_of_status waits RETRY_BASE_DELAY before the first retry" {
  export MOCK_FAILS=1

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1

  [ "$(cat "$SLEEP_LOG")" = "5" ]
}

@test "list_runs_of_status doubles the delay at each retry" {
  export MOCK_FAILS=3

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1

  [ "$(tr '\n' ' ' < "$SLEEP_LOG")" = "5 10 20 " ]
}

@test "list_runs_of_status starts from RETRY_BASE_DELAY" {
  RETRY_BASE_DELAY=2
  export MOCK_FAILS=2

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1

  [ "$(tr '\n' ' ' < "$SLEEP_LOG")" = "2 4 " ]
}

@test "list_runs_of_status does not wait longer than RETRY_MAX_DELAY" {
  RETRY_MAX_DELAY=8
  export MOCK_FAILS=3

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1

  [ "$(tr '\n' ' ' < "$SLEEP_LOG")" = "5 8 8 " ]
}

@test "list_runs_of_status warns before each retry" {
  export MOCK_FAILS=2

  err=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2>&1 > /dev/null)

  [[ "$err" == *"::warning::Listing the runs with the status 'queued' failed (gh: Server Error (HTTP 500) ), retrying in 5s (retry 1/3)"* ]] || false
  [[ "$err" == *"retrying in 10s (retry 2/3)"* ]] || false
}

@test "list_runs_of_status retries a rate limit" {
  export MOCK_FAILS=1
  export MOCK_ERROR="gh: API rate limit exceeded (HTTP 403)"

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 0 ]
  [ "$(gh_calls)" -eq 2 ]
}

# --------------------------------------------------------
# Failures
# --------------------------------------------------------

@test "list_runs_of_status fails after MAX_RETRIES retries" {
  export MOCK_FAILS=99

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 1 ]
  [ "$(gh_calls)" -eq 4 ]
}

@test "list_runs_of_status makes MAX_RETRIES + 1 calls at most" {
  MAX_RETRIES=1
  export MOCK_FAILS=99

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1 || true

  [ "$(gh_calls)" -eq 2 ]
}

@test "list_runs_of_status does not retry when MAX_RETRIES is 0" {
  MAX_RETRIES=0
  export MOCK_FAILS=99

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 1 ]
  [ "$(gh_calls)" -eq 1 ]
  [ ! -s "$SLEEP_LOG" ]
}

@test "list_runs_of_status does not wait after the last attempt" {
  export MOCK_FAILS=99

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1 || true

  [ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 3 ]
}

@test "list_runs_of_status says that it gives up" {
  export MOCK_FAILS=99

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [[ "$output" == *"::warning::Listing the runs with the status 'queued' failed with a transient error, giving up (max 3 retries)"* ]] || false
}

@test "list_runs_of_status forwards the error of gh when it gives up" {
  export MOCK_FAILS=99

  err=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2>&1 > /dev/null || true)

  [[ "$err" == *$'\ngh: Server Error (HTTP 500)' ]] || false
}

@test "list_runs_of_status prints nothing on stdout when it fails" {
  export MOCK_FAILS=99
  export MOCK_PARTIAL=1

  out=$(list_runs_of_status "/repos/o/r/actions/runs" queued 2> /dev/null || true)

  [ -z "$out" ]
}

@test "list_runs_of_status does not retry an error that is not transient" {
  export MOCK_FAILS=99
  export MOCK_ERROR="gh: Not Found (HTTP 404)"

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 1 ]
  [ "$(gh_calls)" -eq 1 ]
  [ ! -s "$SLEEP_LOG" ]
}

@test "list_runs_of_status does not retry a missing permission" {
  export MOCK_FAILS=99
  export MOCK_ERROR="gh: Resource not accessible by integration (HTTP 403)"

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 1 ]
  [ "$(gh_calls)" -eq 1 ]
}

@test "list_runs_of_status reports the error of gh at once when it is not transient" {
  export MOCK_FAILS=99
  export MOCK_ERROR="gh: Not Found (HTTP 404)"

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$output" = "gh: Not Found (HTTP 404)" ]
}

# --------------------------------------------------------
# Temporary files
# --------------------------------------------------------

@test "list_runs_of_status removes its temporary file when it succeeds" {
  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "list_runs_of_status removes its temporary file when it fails" {
  export MOCK_FAILS=99

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1 || true

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "list_runs_of_status removes its temporary file when the error is not transient" {
  export MOCK_FAILS=99
  export MOCK_ERROR="gh: Not Found (HTTP 404)"

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1 || true

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "list_runs_of_status creates its temporary file with make_temp_file" {
  make_temp_file() {
    echo called >> "$MOCK_DIR/make_temp_file.log"
    mktemp "$MOCK_DIR/stderr.XXXXXX"
  }

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [ "$(wc -l < "$MOCK_DIR/make_temp_file.log" | tr -d ' ')" -eq 1 ]
}

@test "list_runs_of_status fails when it cannot create its temporary file" {
  make_temp_file() { return 1; }

  run list_runs_of_status "/repos/o/r/actions/runs" queued

  [ "$status" -eq 1 ]
  [ "$(gh_calls)" -eq 0 ]
}

# --------------------------------------------------------
# Filters
# --------------------------------------------------------

@test "list_runs_of_status sends a GET request" {
  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [[ "$(cat "$GH_LOG")" == *"--method GET"* ]] || false
}

@test "list_runs_of_status sends no filter by default" {
  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [[ "$(cat "$GH_LOG")" != *"-f "* ]] || false
  [[ "$(cat "$GH_LOG")" != *"branch="* ]] || false
  [[ "$(cat "$GH_LOG")" != *"event="* ]] || false
}

@test "list_runs_of_status filters on the branch" {
  BRANCH="main"

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [[ "$(cat "$GH_LOG")" == *"-f branch=main"* ]] || false
  [[ "$(cat "$GH_LOG")" != *"event="* ]] || false
}

@test "list_runs_of_status filters on the event" {
  EVENT="schedule"

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [[ "$(cat "$GH_LOG")" == *"-f event=schedule"* ]] || false
  [[ "$(cat "$GH_LOG")" != *"branch="* ]] || false
}

@test "list_runs_of_status filters on the branch and the event together" {
  BRANCH="main"
  EVENT="push"

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  [[ "$(cat "$GH_LOG")" == *"-f branch=main -f event=push"* ]] || false
}

@test "list_runs_of_status keeps the status and the paging with a filter" {
  BRANCH="main"

  list_runs_of_status "/repos/o/r/actions/runs" waiting > /dev/null

  [[ "$(cat "$GH_LOG")" == *"/repos/o/r/actions/runs?status=waiting&per_page=100"* ]] || false
  [[ "$(cat "$GH_LOG")" == *"--paginate"* ]] || false
}

@test "list_runs_of_status passes a branch with a slash as one argument" {
  BRANCH="feat/my-feature"
  gh() { printf '%s\n' "$@" > "$MOCK_DIR/args.txt"; }

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  grep -qxF "branch=feat/my-feature" "$MOCK_DIR/args.txt"
}

@test "list_runs_of_status passes a hostile branch as one argument, not as a parameter" {
  BRANCH='main&event=schedule'
  gh() { printf '%s\n' "$@" > "$MOCK_DIR/args.txt"; }

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null

  grep -qxF 'branch=main&event=schedule' "$MOCK_DIR/args.txt"
  [ "$(grep -c '^event=' "$MOCK_DIR/args.txt" || true)" -eq 0 ]
}

@test "list_runs_of_status keeps the filters when it retries" {
  BRANCH="main"
  export MOCK_FAILS=1

  list_runs_of_status "/repos/o/r/actions/runs" queued > /dev/null 2>&1

  [ "$(grep -c -- '-f branch=main' "$GH_LOG")" -eq 2 ]
}
