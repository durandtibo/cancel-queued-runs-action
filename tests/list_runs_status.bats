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
  run print_table 1767312000 <<<"o/b|B|queued|2026-01-01T00:00:00Z|2026-01-03T00:00:00Z|222
o/a|A|running|2026-01-01T00:00:00Z|2026-01-02T00:00:00Z|111"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "#"*"Updated ago"*"Job ID" ]] || false
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

@test "print_table: updated at is shown as the age at now, as 12h34m56s" {
  # now = 2026-01-02T00:00:00Z
  run print_table 1767312000 <<<"o/a|A|running|c|2026-01-01T11:25:04Z|1
o/a|B|queued|c|2026-01-01T23:59:59Z|2
o/a|C|queued|c|2026-01-02T00:00:10Z|3"
  [ "$status" -eq 0 ]
  [[ ${lines[2]} == *"12h34m56s"* ]] || false
  [[ ${lines[3]} == *"0h00m01s"* ]] || false
  [[ ${lines[4]} == *"0h00m00s"* ]] || false
}

@test "print_table: ages across a month and a leap day" {
  # now = 2024-03-01T00:00:00Z (1709251200)
  run print_table 1709251200 <<<"o/a|A|running|c|2024-02-28T00:00:00Z|1"
  [ "$status" -eq 0 ]
  [[ ${lines[2]} == *"48h00m00s"* ]] || false
}
