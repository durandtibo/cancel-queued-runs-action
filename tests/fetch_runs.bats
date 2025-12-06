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

# Simulate GitHub API response
cat <<JSON
{
  "workflow_runs": [
    { "id": 111, "created_at": "2025-01-01T10:00:00Z" },
    { "id": 222, "created_at": "2025-01-01T11:00:00Z" }
  ]
}
JSON
EOF

  chmod +x "$MOCK_DIR/gh"

  # Load the script under test
  # Use absolute path to avoid macOS BATS cwd issues
  source "$BATS_TEST_DIRNAME/../scripts/cancel2.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}


@test "fetch_runs returns structured workflow run JSON" {
  run fetch_runs

  # Portable grep usage (POSIX)
  echo "$output" | grep '"id": 111' >/dev/null
  echo "$output" | grep '"created_at": "2025-01-01T10:00:00Z"' >/dev/null

  echo "$output" | grep '"id": 222' >/dev/null
  echo "$output" | grep '"created_at": "2025-01-01T11:00:00Z"' >/dev/null
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
