#!/usr/bin/env bash
#
# Check the result of one case of the action tests (used by ci-action.yaml, for the
# local action and for the released action, so that both runs assert the same thing).
#
# Unit tests run scripts/cancel.sh directly: they cannot see a wrong wiring in
# action.yaml (an input that is not passed, an output that is not exposed, a renamed
# output). The cases are in tests/action_cases.json; this script checks one of them.
#
# Environment variables (passed through env:, never interpolated in a script):
#   CASE               The case, as a JSON object of tests/action_cases.json
#   OUTCOME            The outcome of the step that ran the action (success or failure)
#   ELIGIBLE_COUNT, CANCELLED_COUNT, SKIPPED_COUNT, FAILED_COUNT, CANCELLED_RUN_IDS
#                      The outputs of the action (empty when the step did not set them)
#
# A case has "expect" (the outcome) and, optionally:
#   "eligible-count": the exact value of the output eligible-count
#   "outputs": "unset" (the action failed in the validation, before any output) or
#              "zero" (the action failed after the validation: every output is 0 or [])
# On success, the outputs are checked by format and by invariant, never only printed:
# the counts are non-negative integers, cancelled-run-ids is a JSON array of integers
# with one id per cancelled run, cancelled + skipped + failed = eligible, and in a dry
# run nothing was cancelled, skipped or failed.
#
# Exit codes:
#   0 - The case passed
#   1 - At least one problem (each one is reported as an ::error:: on stderr)

set -euo pipefail

errors=0
fail() {
	echo "::error::[$id] $*" >&2
	errors=1
}

is_count() { [[ "${1:-}" =~ ^(0|[1-9][0-9]*)$ ]]; }

check_success_outputs() {
	local name value
	for name in ELIGIBLE_COUNT CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT; do
		value="${!name:-}"
		is_count "$value" || fail "The output $name must be a non-negative integer (got '$value')"
	done
	[ "$errors" -eq 0 ] || return 0
	if [ -z "${CANCELLED_RUN_IDS:-}" ] || ! jq -e 'type == "array" and all(.[]; type == "number" and . == floor)' <<<"${CANCELLED_RUN_IDS:-}" >/dev/null 2>&1; then
		fail "The output CANCELLED_RUN_IDS must be a JSON array of integers (got '${CANCELLED_RUN_IDS:-}')"
		return 0
	fi
	if [ "$(jq 'length' <<<"$CANCELLED_RUN_IDS")" -ne "$CANCELLED_COUNT" ]; then
		fail "CANCELLED_RUN_IDS ($CANCELLED_RUN_IDS) must have CANCELLED_COUNT ($CANCELLED_COUNT) ids"
	fi
	if [ "$(jq -r '.inputs["dry-run"] // "false"' <<<"$CASE")" = "true" ]; then
		for name in CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT; do
			[ "${!name}" -eq 0 ] || fail "The output $name must be 0 in a dry run (got '${!name}')"
		done
	elif [ $((CANCELLED_COUNT + SKIPPED_COUNT + FAILED_COUNT)) -ne "$ELIGIBLE_COUNT" ]; then
		fail "cancelled ($CANCELLED_COUNT) + skipped ($SKIPPED_COUNT) + failed ($FAILED_COUNT) must be eligible ($ELIGIBLE_COUNT)"
	fi
}

check_failure_outputs() {
	local name want
	want=$(jq -r '.outputs // empty' <<<"$CASE")
	for name in ELIGIBLE_COUNT CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT CANCELLED_RUN_IDS; do
		case "$want" in
		unset) [ -z "${!name:-}" ] || fail "The output $name must not be set after a failed validation (got '${!name}')" ;;
		zero)
			if [ "$name" = CANCELLED_RUN_IDS ]; then
				[ "${!name:-}" = "[]" ] || fail "The output $name must be '[]' (got '${!name:-}')"
			else
				[ "${!name:-}" = "0" ] || fail "The output $name must be 0 (got '${!name:-}')"
			fi
			;;
		esac
	done
}

main() {
	local expect eligible
	id=$(jq -r '.id' <<<"${CASE:?CASE must be set}")
	expect=$(jq -r '.expect' <<<"$CASE")

	if [ "${OUTCOME:-}" != "$expect" ]; then
		fail "The outcome must be '$expect' (got '${OUTCOME:-}')"
		return 1
	fi
	if [ "$expect" = "success" ]; then
		check_success_outputs
	else
		check_failure_outputs
	fi
	eligible=$(jq -r '.["eligible-count"] // empty' <<<"$CASE")
	if [ -n "$eligible" ] && [ "${ELIGIBLE_COUNT:-}" != "$eligible" ]; then
		fail "The output ELIGIBLE_COUNT must be $eligible (got '${ELIGIBLE_COUNT:-}')"
	fi
	[ "$errors" -eq 0 ] || return 1
	echo "✅ Case $id: outcome $OUTCOME, eligible=${ELIGIBLE_COUNT:-}"
}

main "$@"
