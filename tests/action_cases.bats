#!/usr/bin/env bats
#
# The cases of the action tests (levels 2 and 3) are data: tests/action_cases.json.

CASES="$BATS_TEST_DIRNAME/action_cases.json"

@test "action cases: the file is a JSON array with unique ids" {
  run jq -e 'type == "array" and length > 0 and (map(.id) | length == (unique | length))' "$CASES"
  [ "$status" -eq 0 ]
}

@test "action cases: every case has an id, inputs, an expectation and a released flag" {
  run jq -e 'all(.[]; (.id | type == "string") and (.inputs | type == "object")
    and (.expect == "success" or .expect == "failure") and (.released | type == "boolean"))' "$CASES"
  [ "$status" -eq 0 ]
}

@test "action cases: every input named by a case exists in action.yaml" {
  local input
  for input in $(jq -r '[.[].inputs | keys[]] | unique[]' "$CASES"); do
    grep -q "^  ${input}:" "$BATS_TEST_DIRNAME/../action.yaml" || {
      echo "unknown input: $input" >&2
      false
    }
  done
}
