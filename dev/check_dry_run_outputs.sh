#!/usr/bin/env bash
#
# Check the outputs of a dry run of the action (used by ci-action.yaml).
#
# Unit tests run scripts/cancel.sh directly: they cannot see a wrong wiring in
# action.yaml (an input that is not passed, an output that is not exposed, a
# renamed output). This script checks the outputs that the action exposes after
# a dry run, whatever the runs of the repository are.
#
# Environment variables (the outputs of the action, passed through env: and
# never interpolated in a script):
#   FOUND_COUNT, CANCELLED_COUNT, SKIPPED_COUNT, FAILED_COUNT,
#   WOULD_CANCEL_COUNT, DEFERRED_COUNT, CANCELLED_RUN_IDS, LISTING_TRUNCATED
#   MAX_CANCELLATIONS (optional) - the max_cancellations input of the dry run,
#   0 or unset when there is no limit
#
# A dry run must satisfy:
#   - the six counts are non-negative integers (an empty value means that the
#     output is not exposed by action.yaml)
#   - nothing was cancelled, skipped or failed, so cancelled_run_ids is "[]"
#   - would_cancel_count + deferred_count <= found_count
#   - would_cancel_count <= MAX_CANCELLATIONS when there is a limit
#   - deferred_count is 0 when there is no limit
#   - listing_truncated is "true" or "false"
#
# Exit codes:
#   0 - The outputs are valid
#   1 - At least one problem (each one is reported as an ::error:: on stderr)

set -euo pipefail

main() {
	local name value
	local errors=0

	for name in FOUND_COUNT CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT WOULD_CANCEL_COUNT DEFERRED_COUNT; do
		value="${!name:-}"
		if ! [[ "$value" =~ ^(0|[1-9][0-9]*)$ ]]; then
			echo "::error::The output $name must be a non-negative integer (got '$value')" >&2
			errors=1
		fi
	done

	if [ "$errors" -eq 1 ]; then
		return 1
	fi

	for name in CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT; do
		value="${!name}"
		if [ "$value" -ne 0 ]; then
			echo "::error::The output $name must be 0 in a dry run (got '$value')" >&2
			errors=1
		fi
	done

	if [ "$WOULD_CANCEL_COUNT" -gt "$FOUND_COUNT" ]; then
		echo "::error::would_cancel_count ($WOULD_CANCEL_COUNT) cannot exceed found_count ($FOUND_COUNT)" >&2
		errors=1
	elif [ $((WOULD_CANCEL_COUNT + DEFERRED_COUNT)) -gt "$FOUND_COUNT" ]; then
		echo "::error::would_cancel_count ($WOULD_CANCEL_COUNT) and deferred_count ($DEFERRED_COUNT) cannot exceed found_count ($FOUND_COUNT) together" >&2
		errors=1
	fi

	local max_cancellations="${MAX_CANCELLATIONS:-0}"
	if ! [[ "$max_cancellations" =~ ^(0|[1-9][0-9]*)$ ]]; then
		echo "::error::MAX_CANCELLATIONS must be a non-negative integer (got '$max_cancellations')" >&2
		errors=1
	elif [ "$max_cancellations" -eq 0 ]; then
		if [ "$DEFERRED_COUNT" -ne 0 ]; then
			echo "::error::deferred_count must be 0 without a limit (got '$DEFERRED_COUNT')" >&2
			errors=1
		fi
	elif [ "$WOULD_CANCEL_COUNT" -gt "$max_cancellations" ]; then
		echo "::error::would_cancel_count ($WOULD_CANCEL_COUNT) cannot exceed max_cancellations ($max_cancellations)" >&2
		errors=1
	fi

	if [ "${CANCELLED_RUN_IDS:-}" != "[]" ]; then
		echo "::error::The output CANCELLED_RUN_IDS must be '[]' in a dry run (got '${CANCELLED_RUN_IDS:-}')" >&2
		errors=1
	fi

	if [ "${LISTING_TRUNCATED:-}" != "true" ] && [ "${LISTING_TRUNCATED:-}" != "false" ]; then
		echo "::error::The output LISTING_TRUNCATED must be 'true' or 'false' (got '${LISTING_TRUNCATED:-}')" >&2
		errors=1
	fi

	if [ "$errors" -eq 1 ]; then
		return 1
	fi

	echo "✅ Outputs of the dry run: found=$FOUND_COUNT would_cancel=$WOULD_CANCEL_COUNT deferred=$DEFERRED_COUNT truncated=$LISTING_TRUNCATED"
}

main "$@"
