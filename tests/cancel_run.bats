#!/usr/bin/env bats
#
# cancel_run: which request is sent for a run and how its answer is classified.
# The answers are those of gh: an HTTP error exits 1 and writes
# "gh: <message> (HTTP <code>)" on stderr (checked on the real API, see below).

load helpers/common

H=3600
# the buffer is 3 hours: a run is force-cancelled after 24 + 3 = 27 hours
OLD=$((28 * H))
YOUNG=$((25 * H))

setup() {
  setup_fake_gh
  # shellcheck source=../scripts/cancel.sh
  source "$SCRIPT"
}

# the endpoints that were posted, one per line: "101/cancel"
endpoints() { grep -E -- '(-X|--method) POST' "$FAKE_GH_LOG" | sed -E 's#.*/runs/([0-9]+/[a-z-]+).*#\1#'; }

@test "202 on /cancel: cancelled, with one request" {
  answer_post 101 202
  [ "$(cancel_run 101 $YOUNG)" = "cancelled" ]
  [ "$(endpoints)" = "101/cancel" ]
}

@test "the request is a POST on /repos/REPO/actions/runs/ID/cancel" {
  answer_post 101 202
  cancel_run 101 $YOUNG >/dev/null
  grep -q -- '--method POST /repos/myorg/myrepo/actions/runs/101/cancel' "$FAKE_GH_LOG"
}

@test "404: skipped, and no force-cancel even for an old run" {
  answer_post 101 404 "Not Found"
  [ "$(cancel_run 101 $OLD)" = "skipped" ]
  [ "$(posted)" -eq 1 ]
}

@test "409: skipped, and no force-cancel even for an old run" {
  answer_post 101 409 "Cannot cancel a workflow run that is completed."
  [ "$(cancel_run 101 $OLD)" = "skipped" ]
  [ "$(posted)" -eq 1 ]
}

@test "429: rate-limited, and no force-cancel" {
  answer_post 101 429 "Too Many Requests"
  [ "$(cancel_run 101 $OLD)" = "rate-limited" ]
  [ "$(posted)" -eq 1 ]
}

@test "403 about a rate limit: rate-limited" {
  answer_post 101 403 "You have exceeded a secondary rate limit."
  [ "$(cancel_run 101 $OLD)" = "rate-limited" ]
  [ "$(posted)" -eq 1 ]
}

@test "403 about a rate limit is recognized whatever the case" {
  answer_post 101 403 "API Rate Limit exceeded"
  [ "$(cancel_run 101 $YOUNG)" = "rate-limited" ]
}

@test "403 without a rate limit on a young run: failed" {
  answer_post 101 403 "Resource not accessible by integration"
  [ "$(cancel_run 101 $YOUNG)" = "failed" ]
  [ "$(posted)" -eq 1 ]
}

@test "500 on a young run: failed, and no force-cancel" {
  answer_post 101 500 "Server Error"
  [ "$(cancel_run 101 $YOUNG)" = "failed" ]
  [ "$(endpoints)" = "101/cancel" ]
}

@test "500 on an old run: /cancel then /force-cancel, in this order" {
  add_rule POST '*runs/101/force-cancel*' 202 '{}'
  add_rule POST '*runs/101/cancel*' 500 '{"message":"Server Error"}'
  [ "$(cancel_run 101 $OLD)" = "cancelled" ]
  [ "$(endpoints)" = $'101/cancel\n101/force-cancel' ]
}

@test "403 without a rate limit on an old run: /force-cancel is tried" {
  add_rule POST '*runs/101/force-cancel*' 202 '{}'
  add_rule POST '*runs/101/cancel*' 403 '{"message":"Forbidden"}'
  [ "$(cancel_run 101 $OLD)" = "cancelled" ]
  [ "$(posted)" -eq 2 ]
}

@test "the force-cancel is only sent once: a second error is a failure" {
  answer_post 101 500 "Server Error"
  [ "$(cancel_run 101 $OLD)" = "failed" ]
  [ "$(posted)" -eq 2 ]
}

@test "a 409 or 404 on /force-cancel is skipped" {
  add_rule POST '*runs/101/force-cancel*' 409 '{"message":"Cannot cancel a workflow run that is completed."}'
  add_rule POST '*runs/101/cancel*' 500 '{"message":"Server Error"}'
  [ "$(cancel_run 101 $OLD)" = "skipped" ]
}

@test "a rate limit on /force-cancel is rate-limited" {
  add_rule POST '*runs/101/force-cancel*' 429 '{"message":"Too Many Requests"}'
  add_rule POST '*runs/101/cancel*' 500 '{"message":"Server Error"}'
  [ "$(cancel_run 101 $OLD)" = "rate-limited" ]
}

@test "force-cancel boundary: exactly max age + buffer is not force-cancelled" {
  answer_post 101 500 "Server Error"
  [ "$(cancel_run 101 $((27 * H)))" = "failed" ]
  [ "$(posted)" -eq 1 ]
}

@test "force-cancel boundary: one second more is force-cancelled" {
  answer_post 101 500 "Server Error"
  cancel_run 101 $((27 * H + 1)) >/dev/null
  [ "$(posted)" -eq 2 ]
}

@test "a buffer of 0 force-cancels as soon as the run is older than max age" {
  FORCE_BUFFER_HOURS=0
  answer_post 101 500 "Server Error"
  cancel_run 101 $((24 * H + 1)) >/dev/null
  [ "$(posted)" -eq 2 ]
}

@test "the buffer is added to max age" {
  FORCE_BUFFER_HOURS=10 MAX_AGE_HOURS=2
  answer_post 101 500 "Server Error"
  cancel_run 101 $((12 * H)) >/dev/null
  [ "$(posted)" -eq 1 ]
  cancel_run 101 $((12 * H + 1)) >/dev/null
  [ "$(posted)" -eq 3 ]
}

@test "an error without an HTTP code (network failure) is a failure, not a skip" {
  printf '#!/usr/bin/env bash\necho "dial tcp: lookup api.github.com: no such host" >&2\nexit 1\n' >"$WORK/bin/gh.new"
  chmod +x "$WORK/bin/gh.new" && rm "$WORK/bin/gh" && mv "$WORK/bin/gh.new" "$WORK/bin/gh"
  [ "$(cancel_run 101 $YOUNG 2>/dev/null)" = "failed" ]
}

@test "the message of a failure is logged on stderr, not on stdout" {
  answer_post 101 500 "Server Error"
  run bash -c 'source "$1"; cancel_run 101 1 2>&1 >/dev/null' _ "$SCRIPT"
  [[ "$output" == *"Server Error"* ]] || false
}

@test "an unknown run (the real API answers 404 with the JSON body on stdout)" {
  # the real stderr: gh: Not Found (HTTP 404)
  [ "$(cancel_run 99999 $OLD)" = "skipped" ]
}
