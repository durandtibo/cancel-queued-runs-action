#!/usr/bin/env bats
#
# The decision "cancel or not": cutoff computes the instant, select_stale applies
# the one rule (updated_at strictly before the cutoff). Time is injected.

load helpers/common

NOW=1800000000 # 2027-01-15T08:00:00Z

setup() {
  setup_fake_gh
  # shellcheck source=../scripts/cancel.sh
  source "$SCRIPT"
  CUT=$(cutoff "$NOW")
}

# run_at SECONDS_AGO: a {id, updated_at} line for a run updated that long ago
run_at() { jq -nc --argjson id "$1" --argjson a "$2" --argjson n "$NOW" '{id: $id, updated_at: ($n - $a | todate)}'; }

select_from() { select_stale "$CUT" "$NOW"; }

@test "cutoff is max-age-hours before the given instant, as ISO 8601 UTC" {
  [ "$CUT" = "2027-01-14T08:00:00Z" ]
  MAX_AGE_HOURS=1
  [ "$(cutoff "$NOW")" = "2027-01-15T07:00:00Z" ]
}

@test "cutoff uses the clock when no instant is given" {
  run cutoff
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || false
}

@test "select_stale keeps a run one second older than max age" {
  run_at 1 $((24 * 3600 + 1)) | select_from | grep -q '^1 '
}

@test "select_stale drops a run exactly max age old: the rule is strict" {
  [ -z "$(run_at 1 $((24 * 3600)) | select_from)" ]
}

@test "select_stale drops a run one second younger than max age" {
  [ -z "$(run_at 1 $((24 * 3600 - 1)) | select_from)" ]
}

@test "select_stale prints the age in seconds" {
  [ "$(run_at 7 $((30 * 3600)) | select_from)" = "7 108000" ]
}

@test "select_stale drops a run that was re-run: it was created long ago but updated recently" {
  local created updated
  created=$(jq -nr --argjson n "$NOW" '$n - 90 * 3600 | todate')
  updated=$(jq -nr --argjson n "$NOW" '$n - 60 | todate')
  [ -z "$(printf '{"id":5,"created_at":"%s","updated_at":"%s"}\n' "$created" "$updated" | select_from)" ]
}

@test "select_stale sorts the runs oldest first" {
  [ "$({ run_at 1 $((25 * 3600)); run_at 2 $((50 * 3600)); run_at 3 $((30 * 3600)); } | select_from | cut -d' ' -f1 | tr '\n' ' ')" = "2 3 1 " ]
}

@test "select_stale removes duplicates by id" {
  [ "$({ run_at 1 $((30 * 3600)); run_at 1 $((30 * 3600)); run_at 2 $((31 * 3600)); } | select_from | wc -l | tr -d ' ')" = "2" ]
}

@test "select_stale prints nothing for an empty input" {
  [ -z "$(printf '' | select_from)" ]
}

@test "select_stale ignores a run without a usable updated_at" {
  [ -z "$(printf '{"id":1,"updated_at":null}\n{"id":2}\n' | select_from)" ]
}
