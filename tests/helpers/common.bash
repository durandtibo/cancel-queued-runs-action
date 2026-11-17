# Shared helpers of the bats tests: the fake gh and a fake sleep on the PATH.
#
# setup_fake_gh creates a table (the rules of tests/helpers/fake_gh), a log of
# the gh calls and a log of the sleeps, and sets the inputs of the script to
# valid defaults. Time is never mocked: the functions take it as an argument,
# and the tests of the whole script build their timestamps with ago.

setup_fake_gh() {
  WORK="$BATS_TEST_TMPDIR"
  mkdir -p "$WORK/bin"
  ln -s "$BATS_TEST_DIRNAME/helpers/fake_gh" "$WORK/bin/gh"
  printf '#!/usr/bin/env bash\necho "$@" >>"$BATS_TEST_TMPDIR/sleeps.txt"\n' >"$WORK/bin/sleep"
  chmod +x "$WORK/bin/sleep"
  export PATH="$WORK/bin:$PATH"
  export FAKE_GH_LOG="$WORK/gh_calls.txt"
  export FAKE_GH_TABLE="$WORK/table.txt"
  export GITHUB_OUTPUT="$WORK/github_output"
  SLEEPS="$WORK/sleeps.txt"
  : >"$FAKE_GH_LOG" && : >"$FAKE_GH_TABLE" && : >"$GITHUB_OUTPUT" && : >"$SLEEPS"
  unset GITHUB_STEP_SUMMARY GITHUB_TOKEN
  export REPO="myorg/myrepo" GH_TOKEN="test-token" MAX_AGE_HOURS=24
  unset DRY_RUN FAIL_ON_ERROR STATUSES WORKFLOW BRANCH EVENT FORCE_BUFFER_HOURS
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/cancel.sh"
}

# add_rule METHOD GLOB CODE BODY: a rule of the fake gh (the first match wins)
add_rule() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$FAKE_GH_TABLE"; }

# answer_post ID CODE [MESSAGE]: the answer of /cancel and /force-cancel of a run
answer_post() { add_rule POST "*runs/$1/*" "$2" "{\"message\":\"${3:-}\"}"; }

# ago SECONDS: ISO 8601 UTC time that long ago (jq, the same on GNU and BSD)
ago() { jq -nr --argjson s "$1" 'now - $s | floor | todate'; }

# list_queued ID:SECONDS_AGO...: the queued runs that the fake API lists, each
# created and updated that long ago
list_queued() {
  local entries="" spec ts
  for spec in "$@"; do
    ts=$(ago "${spec#*:}")
    entries="${entries:+$entries,}{\"id\":${spec%%:*},\"created_at\":\"$ts\",\"updated_at\":\"$ts\"}"
  done
  add_rule GET '*actions/runs*status=queued*' 200 "{\"workflow_runs\":[$entries]}"
}

posted() { grep -cE -- '(-X|--method) POST' "$FAKE_GH_LOG" || true; }
posted_to() { grep -E -- '(-X|--method) POST' "$FAKE_GH_LOG" | grep -c "runs/$1/" || true; }
output_of() { grep "^$1=" "$GITHUB_OUTPUT" | tail -n 1 | cut -d= -f2-; }
