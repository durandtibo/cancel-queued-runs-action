#!/usr/bin/env bats
#
# The validation of the inputs: every rule has valid and invalid values, and an
# invalid value fails before the first API call (see also characterization.bats).

load helpers/common

setup() {
  setup_fake_gh
  # shellcheck source=../scripts/cancel.sh
  source "$SCRIPT"
}

# ok RULE VALUE...: the values are accepted by the rule
ok() {
  local rule="$1" value
  shift
  for value in "$@"; do
    VAR="$value"
    require VAR "$rule" 2>/dev/null || { echo "$rule rejected '$value'" >&2; return 1; }
  done
}

# ko RULE VALUE...: the values are rejected by the rule, with an ::error:: line
ko() {
  local rule="$1" value err
  shift
  for value in "$@"; do
    VAR="$value"
    if err=$(require VAR "$rule" 2>&1); then echo "$rule accepted '$value'" >&2; return 1; fi
    [[ "$err" == "::error::VAR"* ]] || { echo "no ::error:: for '$value': $err" >&2; return 1; }
  done
}

@test "pint accepts positive integers only" {
  ok pint 1 24 87600
  ko pint 0 01 -1 1.5 abc ""
}

@test "pint with a maximum accepts the maximum and rejects one more" {
  VAR=87600
  require VAR pint 87600 2>/dev/null
  VAR=87601
  ! require VAR pint 87600 2>/dev/null || false
  VAR=99999999999999999999
  ! require VAR pint 87600 2>/dev/null || false
}

@test "nint accepts non-negative integers only" {
  ok nint 0 3 100
  ko nint -1 00 03 x ""
}

@test "bool accepts exactly true and false" {
  ok bool true false
  ko bool yes 1 True TRUE "" "true "
}

@test "statuses accepts a list of the four statuses, with duplicates and spaces" {
  ok statuses queued waiting pending requested queued,waiting "queued, waiting" queued,queued
  ko statuses running in_progress completed "" queued, ,queued queued,,waiting Queued
}

@test "repo accepts owner/name and rejects anything that could change an API path" {
  ok repo myorg/myrepo my-org/my.repo_2 a/b
  ko repo myrepo a/b/c ../x x/.. ./x x/. "a b/c" 'a/b?c' 'a/b#c' "" /x x/
}

@test "workflow accepts a file name or an ID, or nothing" {
  ok workflow "" ci.yaml ci-test_1.yml 12345
  ko workflow a/b.yaml . .. "a b.yaml" 'ci.yaml?x=1'
}

@test "line accepts any text on one line, and rejects a new line" {
  ok line "" main feature/x-1 "a b" 'x&y=z'
  ko line $'a\nb' $'a\rb'
}

@test "an unknown rule rejects everything" {
  ko nosuchrule x ""
}

@test "validate_all accepts the defaults" {
  run validate_all
  [ "$status" -eq 0 ]
}

@test "validate_all rejects each invalid input and names it" {
  local pair name value
  for pair in MAX_AGE_HOURS=0 FORCE_BUFFER_HOURS=-1 STATUSES=running FAIL_ON_ERROR=no \
    DRY_RUN=yes REPO=x WORKFLOW=a/b BRANCH=$'a\nb' EVENT=$'a\nb'; do
    name="${pair%%=*}"
    value="${pair#*=}"
    run env "$name=$value" bash -c 'source "$1"; validate_all' _ "$SCRIPT"
    [ "$status" -eq 1 ] || { echo "$pair accepted" >&2; false; }
    [[ "$output" == *"::error::$name"* ]] || { echo "$pair: $output" >&2; false; }
  done
}

@test "validate_all stops at the first missing tool, before the inputs" {
  # a PATH with jq only: gh is missing, and MAX_AGE_HOURS is invalid too
  mkdir -p "$WORK/onlyjq"
  ln -s "$(command -v jq)" "$WORK/onlyjq/jq"

  run env PATH="$WORK/onlyjq" MAX_AGE_HOURS=0 "$BASH" -c 'source "$1"; validate_all' _ "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Required command not found: gh"* ]] || false
  [[ "$output" != *"MAX_AGE_HOURS"* ]] || false
}

@test "validate_all accepts GH_TOKEN or GITHUB_TOKEN, and a logged-in gh" {
  GH_TOKEN="" GITHUB_TOKEN=x run validate_all
  [ "$status" -eq 0 ]
  GH_TOKEN=x GITHUB_TOKEN="" run validate_all
  [ "$status" -eq 0 ]
  GH_TOKEN="" GITHUB_TOKEN="" run validate_all
  [ "$status" -eq 0 ]
}

@test "validate_all fails without a token when gh is logged out" {
  printf '#!/usr/bin/env bash\n[ "$1" = auth ] && exit 1\nexit 0\n' >"$WORK/bin/gh.new"
  chmod +x "$WORK/bin/gh.new"
  rm "$WORK/bin/gh"
  mv "$WORK/bin/gh.new" "$WORK/bin/gh"

  GH_TOKEN="" GITHUB_TOKEN="" run validate_all

  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::No GitHub credentials"* ]] || false
}
