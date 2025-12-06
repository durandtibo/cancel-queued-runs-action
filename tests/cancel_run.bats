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
  export MOCK_RESPONSE=202

  # Create mock gh command
  cat > "$MOCK_DIR/gh" << EOF
#!/usr/bin/env bash

# Log request arguments
echo "\$@" >> "$MOCK_GH_CALL_LOG"

# Return a fake response depending on the test
if [[ "$@" =~ cancel ]]; then
    if [ "$MOCK_RESPONSE" = "202" ]; then
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

  # Source the function under test
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
  response=$(run cancel_run 12345)
  [[ "$response" =~ "HTTP/2.0 202 Accepted" ]]

  # Check gh call was logged correctly
  log_contents="$(cat "$MOCK_GH_CALL_LOG")"
  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs/12345/cancel" ]]
}

@test "cancel_run calls gh API and handles 500 mock response" {
  export MOCK_RESPONSE=500

  response=$(run cancel_run 67890)
  [[ "$response" =~ "HTTP/2.0 500 Internal Server Error" ]]

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
