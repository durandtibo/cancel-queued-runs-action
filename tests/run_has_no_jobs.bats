#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
  : > "$MOCK_GH_CALL_LOG"
  export PATH="$MOCK_DIR:$PATH"
  export REPO="myorg/myrepo"

  # Mock gh: logs the arguments, prints MOCK_STDOUT, can fail
  cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_GH_CALL_LOG"
if [ -n "$MOCK_STDERR" ]; then
  echo "$MOCK_STDERR" >&2
fi
if [ -n "$MOCK_STDOUT" ]; then
  printf '%s
' "$MOCK_STDOUT"
fi
exit "${MOCK_EXIT:-0}"
MOCK
  chmod +x "$MOCK_DIR/gh"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "run_has_no_jobs succeeds when the run has 0 job" {
  MOCK_STDOUT=0 run run_has_no_jobs 123

  [ "$status" -eq 0 ]
}

@test "run_has_no_jobs fails when the run has jobs" {
  MOCK_STDOUT=2 run run_has_no_jobs 123

  [ "$status" -eq 1 ]
}

@test "run_has_no_jobs fails when the API call fails" {
  MOCK_STDOUT=0 MOCK_EXIT=1 run run_has_no_jobs 123

  [ "$status" -eq 1 ]
}

@test "run_has_no_jobs fails when the answer is empty" {
  run run_has_no_jobs 123

  [ "$status" -eq 1 ]
}

@test "run_has_no_jobs reads the jobs of the run with a GET request" {
  MOCK_STDOUT=0 run run_has_no_jobs 123

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "--method GET" ]] || false
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/123/jobs" ]] || false
}
