#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "validate_repo accepts owner/name" {
  run validate_repo "octocat/hello-world"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate_repo accepts dots, underscores, hyphens and digits" {
  run validate_repo "my-org_1/my.repo_2-x"
  [ "$status" -eq 0 ]
}

@test "validate_repo accepts a name that starts with a dot" {
  run validate_repo "octocat/.github"
  [ "$status" -eq 0 ]
}

@test "validate_repo rejects an empty value" {
  run validate_repo ""
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::REPO is required (owner/name)" ]] || false
}

@test "validate_repo rejects a missing argument" {
  run validate_repo
  [ "$status" -eq 1 ]
  [[ "$output" =~ "REPO is required" ]] || false
}

@test "validate_repo rejects a name without owner" {
  run validate_repo "hello-world"
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::REPO must be in owner/name format (got 'hello-world')" ]] || false
}

@test "validate_repo rejects a trailing slash" {
  run validate_repo "octocat/"
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects a leading slash" {
  run validate_repo "/hello-world"
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects more than two path components" {
  run validate_repo "octocat/hello/world"
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects whitespace" {
  run validate_repo "octocat/hello world"
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects a full URL" {
  run validate_repo "https://github.com/octocat/hello-world"
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects path traversal in the name" {
  run validate_repo "octocat/.."
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects path traversal in the owner" {
  run validate_repo "../hello-world"
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects a single dot component" {
  run validate_repo "octocat/."
  [ "$status" -eq 1 ]
}

@test "validate_repo rejects query string characters" {
  run validate_repo "octocat/hello?status=all"
  [ "$status" -eq 1 ]
}

@test "validate_repo writes the error on stderr" {
  out=$(validate_repo "bad" 2>/dev/null || true)
  [ -z "$out" ]
}
