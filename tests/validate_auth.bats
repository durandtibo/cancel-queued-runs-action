#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export MOCK_GH_CALL_LOG="$MOCK_DIR/gh_calls.txt"
  : > "$MOCK_GH_CALL_LOG"
  export PATH="$MOCK_DIR:$PATH"

  # Mock gh: "gh auth status" succeeds unless MOCK_AUTH_STATUS=1
  cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_GH_CALL_LOG"
exit "${MOCK_AUTH_STATUS:-0}"
MOCK
  chmod +x "$MOCK_DIR/gh"

  unset GH_TOKEN GITHUB_TOKEN
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "validate_auth succeeds when GH_TOKEN is set" {
  export GH_TOKEN="token"
  export MOCK_AUTH_STATUS=1

  run validate_auth

  [ "$status" -eq 0 ]
}

@test "validate_auth succeeds when GITHUB_TOKEN is set" {
  export GITHUB_TOKEN="token"
  export MOCK_AUTH_STATUS=1

  run validate_auth

  [ "$status" -eq 0 ]
}

@test "validate_auth does not call gh when a token is set" {
  export GH_TOKEN="token"

  run validate_auth

  [ ! -s "$MOCK_GH_CALL_LOG" ]
}

@test "validate_auth succeeds without a token when gh is logged in" {
  export MOCK_AUTH_STATUS=0

  run validate_auth

  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_GH_CALL_LOG")" =~ "auth status" ]] || false
}

@test "validate_auth fails without a token when gh is not logged in" {
  export MOCK_AUTH_STATUS=1

  run validate_auth

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::No GitHub credentials found" ]] || false
}

@test "validate_auth fails when GH_TOKEN is empty and gh is not logged in" {
  export GH_TOKEN=""
  export MOCK_AUTH_STATUS=1

  run validate_auth

  [ "$status" -eq 1 ]
  [[ "$output" =~ "No GitHub credentials found" ]] || false
}
