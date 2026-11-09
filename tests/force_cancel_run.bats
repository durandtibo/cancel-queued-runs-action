#!/usr/bin/env bats

setup() {
  # ----------------------------
  # Directories
  # ----------------------------
  # Use absolute paths for mocks/logs (macOS BATS can change CWD)
  TEST_DIR="$BATS_TEST_DIRNAME"
  MOCK_DIR="$TEST_DIR/mocks"
  mkdir -p "$MOCK_DIR"

  # Log file for captured gh calls
  export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
  printf "" > "$MOCK_GH_CALL_LOG"

  # Prepend mocks to PATH so the function uses our fake gh
  export PATH="$MOCK_DIR:$PATH"

  # ----------------------------
  # Environment variables
  # ----------------------------
  export REPO="myorg/myrepo"
  export MOCK_RESPONSE=202  # default mock response

  # ----------------------------
  # Create mock gh command
  # ----------------------------
  cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash

# Log all arguments
echo "$@" >> "$MOCK_GH_CALL_LOG"

# Simulate a gh failure (e.g., network or authentication error)
if [ -n "$MOCK_STDERR" ]; then
    echo "$MOCK_STDERR" >&2
    exit 1
fi

# Determine response for force-cancel endpoints
if [[ "$@" =~ force-cancel ]]; then
    if [ "$MOCK_RESPONSE" = "202" ]; then
        # Use flexible HTTP version to be OS-agnostic
        echo "HTTP/2.0 202 Accepted"
        echo "Content-Type: application/json"
        echo
        echo "{}"
    else
        echo "HTTP/2.0 500 Internal Server Error"
        echo "Content-Type: application/json"
        echo
        echo '{"message":"internal error"}'
    fi
fi
exit 0
EOF

  chmod +x "$MOCK_DIR/gh"

  # ----------------------------
  # Source the functions under test
  # ----------------------------
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}


teardown() {
  rm -rf "$MOCK_DIR"
}

#----------------------------
# Test force_cancel_run calls gh correctly
#----------------------------
@test "force_cancel_run calls gh API with correct arguments" {
  run force_cancel_run 12345

  # The function should succeed
  [ "$status" -eq 0 ]

  # Check that the gh call was logged
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"

  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/12345/force-cancel" ]] || false
  [[ "$log_contents" =~ "-X" ]] || false
  [[ "$log_contents" =~ "POST" ]] || false
  [[ "$log_contents" =~ "-H" ]] || false
  [[ "$log_contents" =~ "Accept: application/vnd.github+json" ]] || false
}

@test "force_cancel_run calls gh API and returns 202 mock response" {
  # Call the function
  run force_cancel_run 12345

  # Check the exit status
  [ "$status" -eq 0 ]

  # Flexible regex to match HTTP version + 202 Accepted
  [[ "$output" =~ HTTP/[0-9.]+\ 202\ Accepted ]] || false

  # Check gh call was logged correctly
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/12345/force-cancel" ]] || false
}

@test "force_cancel_run calls gh API and handles 500 mock response" {
  # Set mock to 500
  export MOCK_RESPONSE=500

  run force_cancel_run 67890
  [ "$status" -eq 0 ]

  # Flexible regex to match HTTP version + 500 Internal Server Error
  [[ "$output" =~ HTTP/[0-9.]+\ 500\ Internal\ Server\ Error ]] || false

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/67890/force-cancel" ]] || false
}

#----------------------------
# Test force_cancel_run with empty run ID
#----------------------------
@test "force_cancel_run fails if run_id is empty" {
  run force_cancel_run ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"run_id is empty"* ]] || false
}

#----------------------------
# Test force_cancel_run surfaces gh errors
#----------------------------
@test "force_cancel_run forwards gh stderr as a warning on stderr" {
  export MOCK_STDERR="gh: Bad credentials (HTTP 401)"

  err=$(force_cancel_run 12345 2>&1 >/dev/null)

  [[ "$err" == *"::warning::"* ]] || false
  [[ "$err" == *"force-cancel"* ]] || false
  [[ "$err" == *"run 12345"* ]] || false
  [[ "$err" == *"Bad credentials (HTTP 401)"* ]] || false
}

@test "force_cancel_run prints nothing on stdout and succeeds when gh fails without a response" {
  export MOCK_STDERR="gh: network unreachable"

  run force_cancel_run 12345

  out=$(force_cancel_run 12345 2>/dev/null)
  [ "$status" -eq 0 ]
  [ -z "$out" ]
}

@test "force_cancel_run does not print a warning when gh succeeds" {
  err=$(force_cancel_run 12345 2>&1 >/dev/null)

  [ -z "$err" ]
}

@test "force_cancel_run does not leave temporary files behind" {
  export TMPDIR="$BATS_TEST_DIRNAME/mocks/tmp"
  mkdir -p "$TMPDIR"
  export MOCK_STDERR="gh: boom"

  force_cancel_run 12345 >/dev/null 2>&1

  [ -z "$(ls -A "$TMPDIR")" ]
}

#----------------------------
# Test force_cancel_run retries rate limited requests
#----------------------------
@test "force_cancel_run delegates to post_run_endpoint_with_retry" {
  post_run_endpoint_with_retry() { echo "delegated: $*"; }

  run force_cancel_run 12345

  [ "$status" -eq 0 ]
  [ "$output" = "delegated: 12345 force-cancel" ]
}
