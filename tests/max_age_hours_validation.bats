#!/usr/bin/env bats

# Test MAX_AGE_HOURS validation
# Note: Duplication is intentional here as the source command needs specific
# handling with environment variables that doesn't work well with helper functions

setup() {
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

@test "script accepts valid positive integer MAX_AGE_HOURS" {
  export MAX_AGE_HOURS=10
  export REPO="test/repo"
  export GH_TOKEN="test-token"
  
  # Source should succeed
  run bash -c "source $SCRIPT_PATH 2>&1; echo 'success'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "success" ]]
}

@test "script rejects non-numeric MAX_AGE_HOURS" {
  export MAX_AGE_HOURS="abc"
  export REPO="test/repo"
  export GH_TOKEN="test-token"
  
  run bash -c "source $SCRIPT_PATH 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
  [[ "$output" =~ "abc" ]]
}

@test "script rejects zero MAX_AGE_HOURS" {
  export MAX_AGE_HOURS=0
  export REPO="test/repo"
  export GH_TOKEN="test-token"
  
  run bash -c "source $SCRIPT_PATH 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
  [[ "$output" =~ "0" ]]
}

@test "script rejects negative MAX_AGE_HOURS" {
  export MAX_AGE_HOURS=-5
  export REPO="test/repo"
  export GH_TOKEN="test-token"
  
  run bash -c "source $SCRIPT_PATH 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
}

@test "script rejects floating point MAX_AGE_HOURS" {
  export MAX_AGE_HOURS="3.5"
  export REPO="test/repo"
  export GH_TOKEN="test-token"
  
  run bash -c "source $SCRIPT_PATH 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "MAX_AGE_HOURS must be a positive integer" ]]
  [[ "$output" =~ "3.5" ]]
}

@test "script uses default MAX_AGE_HOURS of 24 when not set" {
  unset MAX_AGE_HOURS
  export REPO="test/repo"
  export GH_TOKEN="test-token"
  
  # Source and check the value
  run bash -c "source $SCRIPT_PATH 2>&1; echo MAX_AGE_HOURS=\$MAX_AGE_HOURS"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "MAX_AGE_HOURS=24" ]]
}
