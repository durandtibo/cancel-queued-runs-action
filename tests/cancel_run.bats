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

  # Create mock gh command
  cat > "$MOCK_DIR/gh" << EOF
#!/usr/bin/env bash

# Log request arguments
echo "\$@" >> "$MOCK_GH_CALL_LOG"

# Return a fake response depending on the test
if [[ "$@" =~ cancel ]]; then
    echo "HTTP/1.1 202 Accepted"
    echo "Content-Type: application/json"
    echo
    echo "{}"
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

#----------------------------
# Test cancel_run with empty run ID
#----------------------------
@test "cancel_run with empty run ID still calls gh" {
  run cancel_run ""

  [ "$status" -eq 0 ]

  log_contents="$(cat "$MOCK_GH_CALL_LOG")"

  [[ "$log_contents" =~ "/repos/myorg/myrepo/actions/runs//cancel" ]]
}
