#!/usr/bin/env bats
#
# dev/requeue_queued_runs.sh: cancel the queued runs of the other repositories and
# re-run them, only when the target has queued runs. Uses the fake gh.

load helpers/common

setup() {
  setup_fake_gh
  export WAIT_SECONDS=4 POLL_SECONDS=2
  unset DRY_RUN
  SCRIPT="$BATS_TEST_DIRNAME/../dev/requeue_queued_runs.sh"
  # shellcheck source=../dev/requeue_queued_runs.sh
  source "$SCRIPT"
}

# queued REPO ID...: the queued runs that the fake API lists for REPO
queued() {
  local repo="$1" ids="" id
  shift
  for id in "$@"; do ids="${ids:+$ids,}{\"id\":$id}"; done
  add_rule GET "*repos/$repo/actions/runs --paginate*status=queued*" 200 "{\"workflow_runs\":[$ids]}"
}

# a run that is completed as soon as it is cancelled
completed() { add_rule GET "*repos/$1/actions/runs/$2 *" 200 '{"status":"completed"}'; }

@test "requeue_run: cancel, then re-run, in this order" {
  add_rule POST '*runs/7/*' 202 '{}'
  completed o/a 7
  [ "$(requeue_run o/a 7)" = "requeued" ]
  [ "$(grep -E -- '--method POST' "$FAKE_GH_LOG" | sed -E 's#.*/runs/7/##')" = "$(printf 'cancel\nrerun')" ]
}

@test "requeue_run: 409 on the cancel is skipped and the run is not re-run" {
  add_rule POST '*runs/7/cancel*' 409 '{"message":"Cannot cancel a workflow run that is completed."}'
  [ "$(requeue_run o/a 7)" = "skipped" ]
  [ "$(posted)" -eq 1 ]
}

@test "requeue_run: a run that never completes is failed and not re-run" {
  add_rule POST '*runs/7/*' 202 '{}'
  add_rule GET '*repos/o/a/actions/runs/7 *' 200 '{"status":"in_progress"}'
  [ "$(requeue_run o/a 7 2>/dev/null)" = "failed" ]
  [ "$(posted)" -eq 1 ]
}

@test "requeue_run: a failed re-run is failed" {
  add_rule POST '*runs/7/cancel*' 202 '{}'
  add_rule POST '*runs/7/rerun*' 403 '{"message":"Forbidden"}'
  completed o/a 7
  [ "$(requeue_run o/a 7 2>/dev/null)" = "failed" ]
}

@test "main: nothing is cancelled when the target has no queued run" {
  queued o/target
  run main -t o/target o/a
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"nothing to prioritize"* ]] || false
  [ "$(posted)" -eq 0 ]
}

@test "main: the runs of the other repositories are requeued, the target is left alone" {
  queued o/target 1
  queued o/a 10 11
  completed o/a 10
  completed o/a 11
  add_rule POST '*runs/*' 202 '{}'
  run main -t o/target o/target o/a
  [ "$status" -eq 0 ] || false
  [ "$(posted_to 10)" -eq 2 ]
  [ "$(posted_to 11)" -eq 2 ]
  [ "$(posted_to 1)" -eq 0 ]
  [[ "$output" == *"Requeued: 2, failed: 0"* ]] || false
}

@test "main: dry run lists the runs and sends no POST" {
  queued o/target 1
  queued o/a 10
  DRY_RUN=true run main -t o/target o/a
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"Would requeue run 10 of o/a"* ]] || false
  [ "$(posted)" -eq 0 ]
}

@test "main: a run that could not be re-run is listed and the exit code is 1" {
  queued o/target 1
  queued o/a 10
  add_rule POST '*runs/10/cancel*' 202 '{}'
  add_rule POST '*runs/10/rerun*' 500 '{"message":"boom"}'
  completed o/a 10
  run main -t o/target o/a
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"o/a 10"* ]] || false
}

@test "main: the target is required and must be OWNER/NAME" {
  run main o/a
  [ "$status" -eq 2 ] || false
  run main -t nope o/a
  [ "$status" -eq 2 ] || false
}

@test "main: an unknown option fails with 2" {
  run main -t o/target --nope
  [ "$status" -eq 2 ] || false
}

@test "default_repos: lists only the public, non-archived repos, without the target" {
  add_rule GET '*' 200 '[]'
  default_repos o o/target >/dev/null
  grep -q -- 'repo list o --visibility public --no-archived' "$FAKE_GH_LOG"
}

@test "paint: plain text when not on a terminal" {
  [ "$(paint 32 ok)" = "ok" ]
}

@test "outcome_label: one emoji per outcome" {
  [ "$(outcome_label requeued)" = "✅ requeued" ]
  [ "$(outcome_label skipped)" = "⏭️  skipped" ]
  [ "$(outcome_label failed)" = "❌ failed" ]
}
