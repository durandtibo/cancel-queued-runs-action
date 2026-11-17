#!/usr/bin/env bats
#
# list_stale: what is asked to the API (one listing per distinct status, the
# filters as fields) and what is printed ({id, updated_at} lines).

load helpers/common

setup() {
  setup_fake_gh
  # shellcheck source=../scripts/cancel.sh
  source "$SCRIPT"
  CUT="2027-01-14T08:00:00Z"
  add_rule GET '*' 200 '{"workflow_runs":[{"id":1,"updated_at":"2020-01-01T00:00:00Z","name":"x"}]}'
}

calls() { grep -c . "$FAKE_GH_LOG" || true; }

@test "prints one {id, updated_at} object per run and nothing else" {
  run list_stale "$CUT"
  [ "$status" -eq 0 ]
  [ "$output" = '{"id":1,"updated_at":"2020-01-01T00:00:00Z"}' ]
}

@test "the created filter is sent, with the cutoff, as a field" {
  list_stale "$CUT" >/dev/null
  grep -q -- "-f created=<$CUT" "$FAKE_GH_LOG"
}

@test "the request is a GET with the status and 100 runs per page, paginated" {
  list_stale "$CUT" >/dev/null
  grep -q -- '--method GET /repos/myorg/myrepo/actions/runs ' "$FAKE_GH_LOG"
  grep -q -- '-f status=queued' "$FAKE_GH_LOG"
  grep -q -- '-f per_page=100' "$FAKE_GH_LOG"
  grep -q -- '--paginate' "$FAKE_GH_LOG"
}

@test "the cutoff never goes into the URL" {
  list_stale "$CUT" >/dev/null
  ! grep -q "runs?" "$FAKE_GH_LOG" || false
}

@test "one call per status" {
  STATUSES="queued,waiting,pending,requested"
  list_stale "$CUT" >/dev/null
  [ "$(calls)" -eq 4 ]
  for s in queued waiting pending requested; do grep -q -- "-f status=$s" "$FAKE_GH_LOG"; done
}

@test "a status that is repeated is listed once" {
  STATUSES="queued, waiting,queued,waiting"
  list_stale "$CUT" >/dev/null
  [ "$(calls)" -eq 2 ]
}

@test "the workflow is listed through its own endpoint" {
  WORKFLOW=ci.yaml
  list_stale "$CUT" >/dev/null
  grep -q -- '/repos/myorg/myrepo/actions/workflows/ci.yaml/runs ' "$FAKE_GH_LOG"
}

@test "branch and event are sent as fields when set, and only then" {
  list_stale "$CUT" >/dev/null
  ! grep -q -- 'branch=\|event=' "$FAKE_GH_LOG" || false
  : >"$FAKE_GH_LOG"
  BRANCH="feature/a b&c=d" EVENT=push list_stale "$CUT" >/dev/null
  grep -q -- '-f branch=feature/a b&c=d' "$FAKE_GH_LOG"
  grep -q -- '-f event=push' "$FAKE_GH_LOG"
}

@test "the filters are sent for every status" {
  STATUSES="queued,waiting" BRANCH=main list_stale "$CUT" >/dev/null
  [ "$(grep -c -- '-f branch=main' "$FAKE_GH_LOG")" -eq 2 ]
}

@test "the runs of every status are printed" {
  STATUSES="queued,waiting"
  : >"$FAKE_GH_TABLE"
  add_rule GET '*status=queued*' 200 '{"workflow_runs":[{"id":1,"updated_at":"2020-01-01T00:00:00Z"}]}'
  add_rule GET '*status=waiting*' 200 '{"workflow_runs":[{"id":2,"updated_at":"2020-01-02T00:00:00Z"}]}'
  [ "$(list_stale "$CUT" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "an empty listing prints nothing and succeeds" {
  : >"$FAKE_GH_TABLE"
  add_rule GET '*' 200 '{"workflow_runs":[]}'
  run list_stale "$CUT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an error on a listing fails, and the next statuses are not listed" {
  STATUSES="queued,waiting"
  : >"$FAKE_GH_TABLE"
  add_rule GET '*status=queued*' 500 '{"message":"Server Error"}'
  run list_stale "$CUT"
  [ "$status" -eq 1 ]
  [ "$(calls)" -eq 1 ]
}

@test "an error on the workflow (404) fails" {
  WORKFLOW=no-such.yaml
  : >"$FAKE_GH_TABLE"
  run list_stale "$CUT"
  [ "$status" -eq 1 ]
}

@test "no warning below 1000 runs" {
  run list_stale "$CUT"
  [[ "$output" != *"::warning::"* ]] || false
}

@test "a warning when a status reaches the 1000 runs that GitHub returns" {
  : >"$FAKE_GH_TABLE"
  add_rule GET '*' 200 "{\"workflow_runs\":$(jq -nc '[range(1000) | {id: ., updated_at: "2020-01-01T00:00:00Z"}]')}"
  run list_stale "$CUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title="*"1000"* ]] || false
}
