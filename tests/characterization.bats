#!/usr/bin/env bats
#
# Characterization tests: scripts/cancel.sh is run as a process, with the fake
# gh of tests/helpers/fake_gh, and only what it does is asserted (the requests
# it sends, the exit code, the outputs), never its messages. They pin the five
# rules that must survive the refactoring of review/target_state.md: the age
# threshold, the dry run, 404 and 409, fail_on_error and the validation.

load helpers/common

setup() {
  setup_fake_gh
}

# --- the age threshold -------------------------------------------------------

@test "threshold: a run older than max age is cancelled" {
  list_queued 101:$((24 * 3600 + 120))
  answer_post 101 202

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posted_to 101)" -eq 1 ]
  [ "$(output_of cancelled-count)" = "1" ]
}

@test "threshold: a run younger than max age is not touched" {
  list_queued 101:$((24 * 3600 - 120))
  answer_post 101 202

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posted)" -eq 0 ]
  [ "$(output_of cancelled-count)" = "0" ]
}

@test "threshold: only the old runs of a mixed list are cancelled" {
  list_queued 101:$((30 * 3600)) 102:60 103:$((25 * 3600))
  answer_post 101 202
  answer_post 103 202

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posted_to 101)" -eq 1 ]
  [ "$(posted_to 102)" -eq 0 ]
  [ "$(posted_to 103)" -eq 1 ]
  [ "$(output_of eligible-count)" = "2" ]
  [ "$(output_of cancelled-count)" = "2" ]
}

@test "threshold: max_age_hours changes the cutoff" {
  list_queued 101:$((2 * 3600 + 120))
  answer_post 101 202
  export MAX_AGE_HOURS=3

  run "$SCRIPT"
  [ "$(posted)" -eq 0 ]

  export MAX_AGE_HOURS=1
  run "$SCRIPT"
  [ "$(posted_to 101)" -eq 1 ]
}

@test "threshold: an empty listing cancels nothing and succeeds" {
  list_queued

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posted)" -eq 0 ]
  [ "$(output_of eligible-count)" = "0" ]
}

@test "threshold: only the statuses that were asked for are listed" {
  list_queued 101:$((30 * 3600))
  answer_post 101 202

  run "$SCRIPT"

  grep -q 'status=queued' "$FAKE_GH_LOG"
  run grep -q 'status=waiting\|status=pending\|status=requested' "$FAKE_GH_LOG"
  [ "$status" -ne 0 ]
}

# --- the dry run -------------------------------------------------------------

@test "dry run: sends no request that writes" {
  list_queued 101:$((30 * 3600)) 102:$((26 * 3600))
  answer_post 101 202
  answer_post 102 202
  export DRY_RUN=true

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posted)" -eq 0 ]
}

@test "dry run: counts the runs that would be cancelled, and cancels none" {
  list_queued 101:$((30 * 3600)) 102:60
  export DRY_RUN=true

  run "$SCRIPT"

  [ "$(output_of eligible-count)" = "1" ]
  [ "$(output_of cancelled-count)" = "0" ]
}

# --- 404 and 409 -------------------------------------------------------------

@test "404: a run that is gone is skipped, not a failure" {
  list_queued 101:$((25 * 3600))
  answer_post 101 404 "Not Found"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(output_of skipped-count)" = "1" ]
  [ "$(output_of failed-count)" = "0" ]
  [ "$(output_of cancelled-count)" = "0" ]
}

@test "409: a run that cannot be cancelled is skipped, not a failure" {
  list_queued 101:$((25 * 3600))
  answer_post 101 409 "Cannot cancel a workflow run that is completed."

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(output_of skipped-count)" = "1" ]
  [ "$(output_of failed-count)" = "0" ]
}

@test "404: the next runs are still processed" {
  list_queued 101:$((30 * 3600)) 102:$((25 * 3600))
  answer_post 101 404 "Not Found"
  answer_post 102 202

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(posted_to 102)" -eq 1 ]
  [ "$(output_of cancelled-count)" = "1" ]
  [ "$(output_of skipped-count)" = "1" ]
}

# --- fail_on_error -----------------------------------------------------------

@test "fail_on_error: a run that cannot be cancelled fails the step by default" {
  list_queued 101:$((25 * 3600))
  answer_post 101 500 "Server Error"

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [ "$(output_of failed-count)" = "1" ]
}

@test "fail_on_error: false turns the failure into a success, the count stays" {
  list_queued 101:$((25 * 3600))
  answer_post 101 500 "Server Error"
  export FAIL_ON_ERROR=false

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(output_of failed-count)" = "1" ]
}

@test "fail_on_error: false does not hide a failure to list the runs" {
  printf 'GET|*actions/runs*status=queued*|500|{"message":"Server Error"}\n' >>"$FAKE_GH_TABLE"
  export FAIL_ON_ERROR=false MAX_RETRIES=0

  run "$SCRIPT"

  [ "$status" -eq 1 ]
  [ "$(posted)" -eq 0 ]
  [ "$(output_of eligible-count)" = "0" ]
}

# --- the validation ----------------------------------------------------------

# every invalid value fails before any API call
@test "validation: every invalid input fails before the first API call" {
  local pair name value
  for pair in \
    MAX_AGE_HOURS=abc MAX_AGE_HOURS=0 MAX_AGE_HOURS=-1 \
    FORCE_BUFFER_HOURS=-1 FORCE_BUFFER_HOURS=x \
    STATUSES=running \
    DRY_RUN=yes DRY_RUN=1 FAIL_ON_ERROR=no \
    REPO=not-valid REPO=a/b/c 'REPO=../x' \
    'WORKFLOW=a/b.yaml' 'WORKFLOW=a b.yaml'; do
    name="${pair%%=*}"
    value="${pair#*=}"
    : >"$FAKE_GH_LOG"
    run env "$name=$value" "$SCRIPT"
    if [ "$status" -ne 1 ]; then
      echo "$pair: exit $status instead of 1" >&2
      false
    fi
    if [ -s "$FAKE_GH_LOG" ]; then
      echo "$pair: gh was called" >&2
      false
    fi
  done
}

@test "validation: valid values are accepted" {
  local pair name value
  for pair in MAX_AGE_HOURS=1 FORCE_BUFFER_HOURS=0 STATUSES=queued,waiting \
    DRY_RUN=false DRY_RUN=true FAIL_ON_ERROR=false WORKFLOW=ci.yaml WORKFLOW=123; do
    name="${pair%%=*}"
    value="${pair#*=}"
    printf 'GET|*|200|{"workflow_runs":[]}\n' >"$FAKE_GH_TABLE"
    run env "$name=$value" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
      echo "$pair: exit $status instead of 0" >&2
      false
    fi
  done
}

@test "validation: a missing token or repository fails before any API call" {
  unset GH_TOKEN GITHUB_TOKEN
  # gh is logged out
  printf '#!/usr/bin/env bash\n[ "$1" = auth ] && exit 1\nexit 0\n' >"$WORK/bin/gh.new"
  chmod +x "$WORK/bin/gh.new"
  rm "$WORK/bin/gh"
  mv "$WORK/bin/gh.new" "$WORK/bin/gh"

  run "$SCRIPT"
  [ "$status" -eq 1 ]

  export GH_TOKEN=x
  run env -u REPO "$SCRIPT"
  [ "$status" -eq 1 ]
}

# --- the filters reach the listing -------------------------------------------

@test "filters: workflow, branch and event are sent to the listing" {
  list_queued
  printf 'GET|*workflows/ci.yaml/runs*|200|{"workflow_runs":[]}\n' >"$FAKE_GH_TABLE"
  export WORKFLOW=ci.yaml BRANCH=main EVENT=push

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -q 'workflows/ci.yaml/runs' "$FAKE_GH_LOG"
  grep -q 'branch=main' "$FAKE_GH_LOG"
  grep -q 'event=push' "$FAKE_GH_LOG"
}
