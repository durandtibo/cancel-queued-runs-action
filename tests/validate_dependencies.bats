#!/usr/bin/env bats

setup() {
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  BIN_DIR="$MOCK_DIR/bin"
  mkdir -p "$BIN_DIR"
  ORIGINAL_PATH="$PATH"

  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"

  # Only the stubs of BIN_DIR are visible to command -v
  PATH="$BIN_DIR"
}

teardown() {
  PATH="$ORIGINAL_PATH"
  rm -rf "$MOCK_DIR"
}

make_stub() {
  printf '#!/bin/sh\n' > "$BIN_DIR/$1"
  PATH="$ORIGINAL_PATH" chmod +x "$BIN_DIR/$1"
}

@test "validate_dependencies succeeds when gh and jq are installed" {
  make_stub gh
  make_stub jq

  run validate_dependencies

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_dependencies fails when gh is missing" {
  make_stub jq

  run validate_dependencies

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Required command(s) not found: gh " ]]
}

@test "validate_dependencies fails when jq is missing" {
  make_stub gh

  run validate_dependencies

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::Required command(s) not found: jq " ]]
}

@test "validate_dependencies reports every missing command at once" {
  run validate_dependencies

  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found: gh jq " ]]
}

@test "validate_dependencies does not mention an installed command" {
  make_stub gh

  run validate_dependencies

  [[ ! "$output" =~ "not found: gh" ]]
  [[ ! "$output" =~ " gh jq" ]]
}

@test "validate_dependencies writes the error on stderr only" {
  out=$(validate_dependencies 2>/dev/null) || true

  [ -z "$out" ]
}

@test "validate_dependencies accepts a shell function" {
  make_stub jq
  gh() { :; }

  run validate_dependencies

  [ "$status" -eq 0 ]
}
