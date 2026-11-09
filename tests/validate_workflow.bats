#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_workflow accepts an empty value (no filter)" {
  run validate_workflow ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_workflow accepts a missing argument" {
  run validate_workflow
  [ "$status" -eq 0 ]
}

@test "validate_workflow accepts a .yaml file name" {
  run validate_workflow "ci.yaml"
  [ "$status" -eq 0 ]
}

@test "validate_workflow accepts a .yml file name" {
  run validate_workflow "build-and_test.yml"
  [ "$status" -eq 0 ]
}

@test "validate_workflow accepts a numeric ID" {
  run validate_workflow "161335"
  [ "$status" -eq 0 ]
}

@test "validate_workflow rejects a path separator" {
  run validate_workflow ".github/workflows/ci.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "::error::WORKFLOW must be a workflow file name" ]]
  [[ "$output" =~ "(got '.github/workflows/ci.yaml')" ]]
}

@test "validate_workflow rejects path traversal" {
  run validate_workflow ".."
  [ "$status" -eq 1 ]
}

@test "validate_workflow rejects a single dot" {
  run validate_workflow "."
  [ "$status" -eq 1 ]
}

@test "validate_workflow rejects a display name with spaces" {
  run validate_workflow "My Workflow"
  [ "$status" -eq 1 ]
}

@test "validate_workflow rejects query string characters" {
  run validate_workflow "ci.yaml?status=all"
  [ "$status" -eq 1 ]
}

@test "validate_workflow rejects a shell injection attempt" {
  run validate_workflow 'ci.yaml;echo pwned'
  [ "$status" -eq 1 ]
}

@test "validate_workflow writes the error on stderr" {
  out=$(validate_workflow "a b" 2>/dev/null || true)
  [ -z "$out" ]
}
