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

@test "action cases: a failure case says what happens to the outputs, a success case does not" {
  run jq -e 'all(.[]; if .expect == "failure" then (.outputs == "unset" or .outputs == "zero") else (has("outputs") | not) end)' "$CASES"
  [ "$status" -eq 0 ]
}

@test "action cases: every input and output rule is covered: each input has a case, each validated input an invalid case" {
  local input
  for input in repo max-age-hours statuses workflow branch event force-cancel-buffer-hours fail-on-error dry-run; do
    jq -e --arg i "$input" 'any(.[]; .inputs | has($i))' "$CASES" >/dev/null || { echo "no case sets $input" >&2; false; }
  done
  for input in repo max-age-hours statuses workflow branch event force-cancel-buffer-hours fail-on-error dry-run; do
    jq -e --arg i "$input" 'any(.[]; .expect == "failure" and .outputs == "unset" and (.inputs | has($i)))' "$CASES" >/dev/null ||
      { echo "no invalid case for $input" >&2; false; }
  done
}
