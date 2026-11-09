#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_branch accepts an empty value (no filter)" {
  run validate_branch ""

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_branch accepts a missing argument (no filter)" {
  run validate_branch

  [ "$status" -eq 0 ]
}

@test "validate_branch accepts main" {
  run validate_branch main

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_branch accepts a branch with a slash" {
  run validate_branch "feat/my-feature"

  [ "$status" -eq 0 ]
}

@test "validate_branch accepts a branch with dots, underscores and digits" {
  run validate_branch "release-1.2_rc3"

  [ "$status" -eq 0 ]
}

@test "validate_branch accepts a branch with non-ASCII characters" {
  run validate_branch "feat/café"

  [ "$status" -eq 0 ]
}

@test "validate_branch accepts a branch that only starts like a ref" {
  run validate_branch "refs-fix"

  [ "$status" -eq 0 ]
}

@test "validate_branch accepts a branch of 255 characters" {
  branch=$(printf 'a%.0s' $(seq 1 255))

  run validate_branch "$branch"

  [ "$status" -eq 0 ]
}

@test "validate_branch rejects a branch of 256 characters" {
  branch=$(printf 'a%.0s' $(seq 1 256))

  run validate_branch "$branch"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::BRANCH must be a branch name of at most 255 characters" ]] || false
}

@test "validate_branch rejects a full ref and suggests the branch name" {
  run validate_branch "refs/heads/main"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::BRANCH must be a branch name, not a ref: use 'main' instead of 'refs/heads/main'" ]] || false
}

@test "validate_branch rejects a pull request ref" {
  run validate_branch "refs/pull/12/merge"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "not a ref" ]] || false
}

@test "validate_branch rejects a value with a space" {
  run validate_branch "my branch"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "(got 'my branch')" ]] || false
}

@test "validate_branch rejects a value with a tab" {
  run validate_branch $'main\tdev'

  [ "$status" -eq 1 ]
}

@test "validate_branch rejects a value with a newline" {
  run validate_branch $'main\ndev'

  [ "$status" -eq 1 ]
}

@test "validate_branch rejects a value with a trailing space" {
  run validate_branch "main "

  [ "$status" -eq 1 ]
}

@test "validate_branch rejects a value with a control character" {
  run validate_branch $'ma\x01in'

  [ "$status" -eq 1 ]
}

@test "validate_branch writes the error on stderr" {
  out=$(validate_branch "my branch" 2>/dev/null) || true

  [ -z "$out" ]
}
