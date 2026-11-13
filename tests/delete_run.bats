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

@test "delete_run sends a DELETE request to the run" {
  MOCK_STDOUT="HTTP/2.0 204 No Content" run delete_run 123

  [ "$status" -eq 0 ]
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "-X DELETE" ]] || false
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/123" ]] || false
}

@test "delete_run prints the HTTP response" {
  MOCK_STDOUT="HTTP/2.0 204 No Content" run delete_run 123

  [[ "$output" =~ "HTTP/2.0 204 No Content" ]] || false
}

@test "delete_run fails when the run ID is empty" {
  run delete_run ""

  [ "$status" -eq 1 ]
  [[ "$output" =~ "run_id is empty" ]] || false
}

@test "delete_run forwards the error of gh as a warning" {
  MOCK_STDERR="connection refused" MOCK_EXIT=1 run delete_run 123

  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::gh api (delete) failed for run 123: connection refused" ]] || false
}

@test "delete_run does not warn for a 404 response" {
  MOCK_STDOUT="HTTP/2.0 404 Not Found" MOCK_STDERR="gh: Not Found (HTTP 404)" MOCK_EXIT=1 run delete_run 123

  [[ ! "$output" =~ "::warning::" ]] || false
}
