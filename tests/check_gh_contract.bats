#!/usr/bin/env bats
#
# dev/check_gh_contract.sh with the fake gh: it passes on "(HTTP 404)" and fails otherwise.

load helpers/common

setup() {
  setup_fake_gh
  CHECK="$BATS_TEST_DIRNAME/../dev/check_gh_contract.sh"
  export GITHUB_REPOSITORY="myorg/myrepo"
}

@test "check_gh_contract passes when a POST to a missing run answers 404, and posts to run 1" {
  run "$CHECK"
  [ "$status" -eq 0 ]
  [ "$(posted_to 1)" -eq 1 ]
}

@test "check_gh_contract fails when gh does not write the HTTP code" {
  add_rule POST '*' 500 '{"message":"Server Error"}'
  run "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"* ]] || false
}

@test "check_gh_contract fails when the request succeeds" {
  add_rule POST '*' 202 '{}'
  run "$CHECK"
  [ "$status" -eq 1 ]
}

@test "check_gh_contract needs GITHUB_REPOSITORY" {
  run env -u GITHUB_REPOSITORY "$CHECK"
  [ "$status" -ne 0 ]
}
