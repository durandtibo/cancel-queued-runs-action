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

# Determine response for cancel endpoints
if [[ "$@" =~ cancel ]]; then
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
  source "$BATS_TEST_DIRNAME/../scripts/cancel2.sh"
}


teardown() {
  rm -rf "$MOCK_DIR"
}

#----------------------------
# Test cancel_run calls gh correctly
#----------------------------
@test "cancel_run calls gh API with correct arguments" {
  run cancel_run 12345

  # The function should succeed
  [ "$status" -eq 0 ]

  # Check that the gh call was logged
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"

  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/12345/cancel" ]]
  [[ "$log_contents" =~ "-X" ]]
  [[ "$log_contents" =~ "POST" ]]
  [[ "$log_contents" =~ "-H" ]]
  [[ "$log_contents" =~ "Accept: application/vnd.github+json" ]]
}

@test "cancel_run calls gh API and returns 202 mock response" {
  # Call the function
  run cancel_run 12345

  # Check the exit status
  [ "$status" -eq 0 ]

  # Flexible regex to match HTTP version + 202 Accepted
  [[ "$output" =~ HTTP/[0-9.]+\ 202\ Accepted ]]

  # Check gh call was logged correctly
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/12345/cancel" ]]
}

@test "cancel_run calls gh API and handles 500 mock response" {
  # Set mock to 500
  export MOCK_RESPONSE=500

  run cancel_run 67890
  [ "$status" -eq 0 ]

  # Flexible regex to match HTTP version + 500 Internal Server Error
  [[ "$output" =~ HTTP/[0-9.]+\ 500\ Internal\ Server\ Error ]]

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/67890/cancel" ]]
}

#----------------------------
# Test cancel_run with empty run ID
#----------------------------
@test "cancel_run fails if run_id is empty" {
  run cancel_run ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"run_id is empty"* ]]
}
