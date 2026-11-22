#!/usr/bin/env bats
#
# dev/list_runs_status.sh: table of the queued and running runs of several repositories,
# sorted by update time. Uses the fake gh.

load helpers/common

setup() {
  setup_fake_gh
  # shellcheck source=../dev/list_runs_status.sh
  source "$BATS_TEST_DIRNAME/../dev/list_runs_status.sh"
}

@test "list_runs: in_progress is shown as running" {
  add_rule GET '*repos/o/a/actions/runs --paginate*status=queued*' 200 '{"workflow_runs":[{"name":"CI","status":"queued","created_at":"c1","updated_at":"u1","id":11}]}'
  add_rule GET '*repos/o/a/actions/runs --paginate*status=in_progress*' 200 '{"workflow_runs":[{"name":"Docs","status":"in_progress","created_at":"c2","updated_at":"u2","id":22}]}'
  run list_runs o/a
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "o/a|CI|queued|c1|u1|11" ]
  [ "${lines[1]}" = "o/a|Docs|running|c2|u2|22" ]
}

@test "list_runs: an API error fails" {
  run list_runs o/a
  [ "$status" -eq 1 ]
}

@test "print_table: sorted by updated at, header first" {
  run print_table <<<"o/b|B|queued|2026-01-01T00:00:00Z|2026-01-03T00:00:00Z|222
o/a|A|running|2026-01-01T00:00:00Z|2026-01-02T00:00:00Z|111"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "#"*Repository*"Job ID" ]] || false
  [[ ${lines[2]} == "1  o/a"* ]] || false
  [[ ${lines[3]} == "2  o/b"* ]] || false
  [[ ${lines[2]} == *"  111" ]] || false
  [[ ${lines[3]} == *"  222" ]] || false
}

@test "main: a repository that cannot be listed is reported and fails" {
  add_rule GET '*repos/o/a/actions/runs*' 200 '{"workflow_runs":[]}'
  run main o/a o/missing
  [ "$status" -eq 1 ]
  [[ $output == *"Cannot list the runs of o/missing"* ]] || false
}

@test "main: unknown option is a usage error" {
  run main --nope
  [ "$status" -eq 2 ]
}
