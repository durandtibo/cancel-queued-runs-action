#!/usr/bin/env bats
#
# cancel_all: the loop over "id age" lines. It prints
# "eligible cancelled skipped failed ids" on stdout; the logs go to stderr.

load helpers/common

setup() {
  setup_fake_gh
  # shellcheck source=../scripts/cancel.sh
  source "$SCRIPT"
}

all() { cancel_all 2>/dev/null; }

@test "no run: all the counts are 0 and the ids are []" {
  [ "$(printf '' | all)" = "0 0 0 0 []" ]
  [ "$(posted)" -eq 0 ]
}

@test "blank lines are ignored" {
  answer_post 1 202
  [ "$(printf '\n1 100000\n\n' | all)" = "1 1 0 0 [1]" ]
}

@test "the runs are cancelled in the given order and the ids keep it" {
  answer_post 3 202; answer_post 1 202; answer_post 2 202
  [ "$(printf '3 300000\n1 200000\n2 100000\n' | all)" = "3 3 0 0 [3,1,2]" ]
  [ "$(grep -oE 'runs/[0-9]+/' "$FAKE_GH_LOG" | tr -d 'runs/' | tr '\n' ' ')" = "3 1 2 " ]
}

@test "the outcomes are counted: cancelled, skipped (404, 409) and failed" {
  answer_post 1 202; answer_post 2 404 "Not Found"; answer_post 3 409 "Conflict"; answer_post 4 500 "Server Error"
  [ "$(printf '1 100000\n2 100000\n3 100000\n4 100000\n' | all)" = "4 1 2 1 [1]" ]
}

@test "cancelled + skipped + failed = eligible" {
  answer_post 1 202; answer_post 2 404; answer_post 3 500
  local r
  r=$(printf '1 100000\n2 100000\n3 100000\n' | all)
  set -- $r
  [ $(($2 + $3 + $4)) -eq "$1" ]
}

@test "a failed run does not stop the next ones" {
  answer_post 1 500 "Server Error"; answer_post 2 202
  [ "$(printf '1 100\n2 100\n' | all)" = "2 1 0 1 [2]" ]
}

@test "a rate limit stops the loop: this run and the next ones are failed" {
  answer_post 1 202; answer_post 2 429 "Too Many Requests"; answer_post 3 202; answer_post 4 202
  [ "$(printf '1 100\n2 100\n3 100\n4 100\n' | all)" = "4 1 0 3 [1]" ]
  [ "$(posted_to 3)" -eq 0 ]
  [ "$(posted_to 4)" -eq 0 ]
}

@test "a rate limit on the first run fails all of them and sends one request" {
  answer_post 1 429 "Too Many Requests"
  [ "$(printf '1 100\n2 100\n' | all)" = "2 0 0 2 []" ]
  [ "$(posted)" -eq 1 ]
}

@test "one second is waited between two requests, not before the first" {
  answer_post 1 202; answer_post 2 202; answer_post 3 202
  printf '1 100\n2 100\n3 100\n' | all >/dev/null
  [ "$(cat "$SLEEPS")" = $'1\n1' ]
}

@test "the pause also follows a skipped or failed request" {
  answer_post 1 404; answer_post 2 500; answer_post 3 202
  printf '1 100\n2 100\n3 100\n' | all >/dev/null
  [ "$(wc -l <"$SLEEPS" | tr -d ' ')" -eq 2 ]
}

@test "no pause for a single run" {
  answer_post 1 202
  printf '1 100\n' | all >/dev/null
  [ ! -s "$SLEEPS" ]
}

@test "dry run: counts the eligible runs, sends nothing and never pauses" {
  DRY_RUN=true
  [ "$(printf '1 100\n2 100\n' | all)" = "2 0 0 0 []" ]
  [ ! -s "$FAKE_GH_LOG" ]
  [ ! -s "$SLEEPS" ]
}

@test "dry run: the runs that would be cancelled are logged" {
  DRY_RUN=true
  run bash -c 'source "$1"; printf "1 100\n" | DRY_RUN=true cancel_all 2>&1 >/dev/null' _ "$SCRIPT"
  [[ "$output" == *"[dry-run] Would cancel run 1"* ]] || false
}

@test "the logs of the loop do not go to stdout" {
  answer_post 1 202
  [ "$(printf '1 100\n' | cancel_all 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
}

@test "the message of the API is never at the start of a line (no workflow command)" {
  answer_post 1 500 "::error::injected"
  run bash -c 'source "$1"; printf "1 100\n" | cancel_all 2>&1 >/dev/null' _ "$SCRIPT"
  ! printf '%s\n' "$output" | grep -q '^::error::injected' || false
}

@test "format_age prints seconds as hours, minutes and seconds" {
	run format_age 91663
	[ "$output" = "25h27m43s" ]
}

@test "format_age prints zero hours and minutes for a short age" {
	run format_age 5
	[ "$output" = "0h0m5s" ]
}
