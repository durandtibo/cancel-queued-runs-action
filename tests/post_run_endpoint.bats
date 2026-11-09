#!/usr/bin/env bats

setup() {
  # Use absolute paths for mocks/logs (macOS BATS can change CWD)
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"

  export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
  : > "$MOCK_GH_CALL_LOG"
  export PATH="$MOCK_DIR:$PATH"

  export REPO="myorg/myrepo"

  # Mock gh: logs the arguments, can fail with a stderr message or an HTTP
  # error (stdout response + exit code 1, like the real gh for non-2xx codes)
  cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_GH_CALL_LOG"

if [ -n "$MOCK_STDERR" ]; then
    echo "$MOCK_STDERR" >&2
fi

if [ -n "$MOCK_NO_STDOUT" ]; then
    :
elif [ -n "$MOCK_STDOUT" ]; then
    printf '%s\n' "$MOCK_STDOUT"
else
    printf 'HTTP/2.0 202 Accepted\n\n{}\n'
fi
exit "${MOCK_EXIT:-0}"
MOCK
  chmod +x "$MOCK_DIR/gh"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "post_run_endpoint posts to the requested endpoint of the run" {
  run post_run_endpoint 12345 cancel

  [ "$status" -eq 0 ]
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "-X POST" ]]
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/12345/cancel" ]]
  [[ "$log_contents" =~ "-i" ]]
}

@test "post_run_endpoint supports the force-cancel endpoint" {
  run post_run_endpoint 12345 force-cancel

  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_GH_CALL_LOG")" =~ "/repos/myorg/myrepo/actions/runs/12345/force-cancel" ]]
}

@test "post_run_endpoint prints the HTTP response on stdout" {
  run post_run_endpoint 12345 cancel

  [[ "${lines[0]}" == "HTTP/2.0 202 Accepted" ]]
}

@test "post_run_endpoint keeps the response of an HTTP error and succeeds" {
  export MOCK_STDOUT="HTTP/2.0 409 Conflict"
  export MOCK_EXIT=1

  run post_run_endpoint 12345 cancel

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "HTTP/2.0 409 Conflict" ]]
}

@test "post_run_endpoint warns on stderr with the gh error message" {
  export MOCK_STDERR="gh: Server Error (HTTP 500)"
  export MOCK_STDOUT="HTTP/2.0 500 Internal Server Error"
  export MOCK_EXIT=1

  err=$(post_run_endpoint 12345 cancel 2>&1 >/dev/null)

  [[ "$err" == "::warning::gh api (cancel) failed for run 12345: gh: Server Error (HTTP 500) " ]]
}

@test "post_run_endpoint does not warn about a 404 response" {
  export MOCK_STDERR="gh: Not Found (HTTP 404)"
  export MOCK_STDOUT="HTTP/2.0 404 Not Found"
  export MOCK_EXIT=1

  err=$(post_run_endpoint 12345 cancel 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "post_run_endpoint does not warn about a 409 response" {
  export MOCK_STDERR="gh: Conflict (HTTP 409)"
  export MOCK_STDOUT="HTTP/2.0 409 Conflict"
  export MOCK_EXIT=1

  err=$(post_run_endpoint 12345 force-cancel 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "post_run_endpoint still prints the response of a 409 on stdout" {
  export MOCK_STDERR="gh: Conflict (HTTP 409)"
  export MOCK_STDOUT="HTTP/2.0 409 Conflict"
  export MOCK_EXIT=1

  out=$(post_run_endpoint 12345 cancel 2>/dev/null)

  [[ "$out" == "HTTP/2.0 409 Conflict" ]]
}

@test "post_run_endpoint warns about a 403 response" {
  export MOCK_STDERR="gh: Resource not accessible by integration (HTTP 403)"
  export MOCK_STDOUT="HTTP/2.0 403 Forbidden"
  export MOCK_EXIT=1

  err=$(post_run_endpoint 12345 cancel 2>&1 >/dev/null)

  [[ "$err" == *"::warning::gh api (cancel) failed for run 12345"* ]]
  [[ "$err" == *"HTTP 403"* ]]
}

@test "post_run_endpoint warns when gh fails without any response" {
  export MOCK_STDERR="gh: network unreachable"
  export MOCK_NO_STDOUT=1
  export MOCK_EXIT=1

  err=$(post_run_endpoint 12345 cancel 2>&1 >/dev/null)

  [[ "$err" == *"::warning::gh api (cancel) failed for run 12345: gh: network unreachable"* ]]
}

@test "post_run_endpoint does not mix the warning with the response on stdout" {
  export MOCK_STDERR="gh: Not Found (HTTP 404)"
  export MOCK_STDOUT="HTTP/2.0 404 Not Found"
  export MOCK_EXIT=1

  out=$(post_run_endpoint 12345 cancel 2>/dev/null)

  [[ "$out" == "HTTP/2.0 404 Not Found" ]]
}

@test "post_run_endpoint prints nothing on stdout when gh fails without a response" {
  export MOCK_STDERR="gh: network unreachable"
  export MOCK_NO_STDOUT=1
  export MOCK_EXIT=1

  out=$(post_run_endpoint 12345 cancel 2>/dev/null)

  [ -z "$out" ]
}

@test "post_run_endpoint reports a missing gh command" {
  PATH="/usr/bin:/bin"
  rm -f "$MOCK_DIR/gh"
  command -v gh >/dev/null 2>&1 && skip "gh is installed in a system directory"

  err=$(post_run_endpoint 12345 cancel 2>&1 >/dev/null)

  [[ "$err" == *"::warning::"* ]]
}

@test "post_run_endpoint is silent when gh succeeds" {
  err=$(post_run_endpoint 12345 cancel 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "post_run_endpoint does not leave temporary files behind" {
  export TMPDIR="$MOCK_DIR/tmp"
  mkdir -p "$TMPDIR"
  export MOCK_STDERR="gh: boom"
  export MOCK_EXIT=1

  post_run_endpoint 12345 cancel >/dev/null 2>&1

  [ -z "$(ls -A "$TMPDIR")" ]
}
