#!/usr/bin/env bats
#
# Tests of dev/mutation_check.sh, which breaks scripts/cancel.sh on purpose and
# requires the tests to notice.

setup() {
  CHECK="$BATS_TEST_DIRNAME/../dev/mutation_check.sh"
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
  mkdir -p "$MOCK_DIR"
  export MUTANTS_FILE="$MOCK_DIR/mutants.txt"
  # a bats run inside a bats test must not inherit the state of the outer run
  unset BATS_TEST_FILENAME BATS_TEST_NAME BATS_TMPDIR BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_TEST_TMPDIR
}

teardown() {
  rm -rf "$MOCK_DIR"
  rm -f "$BATS_TEST_DIRNAME/broken_baseline.bats"
}

@test "mutation_check detects a mutation that breaks the tests of a function" {
  printf '%s\n' 'format_age: no clamp@@format_age.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' > "$MUTANTS_FILE"

  run "$CHECK"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "killed    format_age: no clamp" ]] || false
  [[ "$output" =~ "1 of 1 mutation(s) detected." ]] || false
}

@test "mutation_check fails when a mutation survives" {
  # only a comment changes: no test can notice
  printf '%s\n' 'comment@@format_age.bats@@s/^# Cancel Queued Workflow Runs$/# Changed/' > "$MUTANTS_FILE"

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "SURVIVED  comment" ]] || false
  [[ "$output" =~ "1 mutation(s) survived" ]] || false
}

@test "mutation_check fails when the expression does not change the script" {
  printf '%s\n' 'nothing@@format_age.bats@@s/this text does not exist/x/' > "$MUTANTS_FILE"

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "OUTDATED  nothing" ]] || false
}

@test "mutation_check fails when the mutated script is not valid bash" {
  printf '%s\n' 'syntax@@format_age.bats@@s/^format_age\(\) \{$/format_age() {{{/' > "$MUTANTS_FILE"

  run "$CHECK"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "INVALID   syntax" ]] || false
}

@test "mutation_check ignores the comments and the empty lines" {
  printf '%s\n' '# a comment' '' 'format_age: no clamp@@format_age.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' > "$MUTANTS_FILE"

  run "$CHECK"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "1 of 1 mutation(s) detected." ]] || false
}

@test "mutation_check only runs the mutations that match the filter" {
  printf '%s\n' \
    'format_age: no clamp@@format_age.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' \
    'other: nothing@@format_age.bats@@s/this text does not exist/x/' > "$MUTANTS_FILE"

  run "$CHECK" "format_age"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "1 of 1 mutation(s) detected." ]] || false
}

@test "mutation_check does not modify the script" {
  printf '%s\n' 'format_age: no clamp@@format_age.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' > "$MUTANTS_FILE"
  before=$(cksum < "$BATS_TEST_DIRNAME/../scripts/cancel.sh")

  run "$CHECK"

  [ "$(cksum < "$BATS_TEST_DIRNAME/../scripts/cancel.sh")" = "$before" ]
}

@test "mutation_check does not leave temporary directories" {
  export TMPDIR="$MOCK_DIR/tmp"
  mkdir -p "$TMPDIR"
  printf '%s\n' 'format_age: no clamp@@format_age.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' > "$MUTANTS_FILE"

  run "$CHECK"

  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "mutation_check fails when the tests do not pass without the mutation" {
  printf '%s\n' 'format_age: no clamp@@format_age.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' > "$MUTANTS_FILE"
  # a test file that fails on the unmutated script
  cp "$BATS_TEST_DIRNAME/format_age.bats" "$BATS_TEST_DIRNAME/broken_baseline.bats"
  printf '%s\n' '@test "always fails" {' '  false' '}' >> "$BATS_TEST_DIRNAME/broken_baseline.bats"
  printf '%s\n' 'x: baseline@@broken_baseline.bats@@s/\[ "\$seconds" -lt 0 \]/[ "$seconds" -lt -999999999 ]/' > "$MUTANTS_FILE"

  run "$CHECK"
  rm -f "$BATS_TEST_DIRNAME/broken_baseline.bats"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "does not pass on the unmutated script" ]] || false
}
