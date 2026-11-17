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
#   ELIGIBLE_COUNT, CANCELLED_COUNT, SKIPPED_COUNT, FAILED_COUNT, CANCELLED_RUN_IDS
#
# A dry run must satisfy:
#   - the four counts are non-negative integers (an empty value means that the
#     output is not exposed by action.yaml)
#   - nothing was cancelled, skipped or failed, so cancelled_run_ids is "[]"
#
# Exit codes:
#   0 - The outputs are valid
#   1 - At least one problem (each one is reported as an ::error:: on stderr)

set -euo pipefail

main() {
	local name value
	local errors=0

	for name in ELIGIBLE_COUNT CANCELLED_COUNT SKIPPED_COUNT FAILED_COUNT; do
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

	if [ "${CANCELLED_RUN_IDS:-}" != "[]" ]; then
		echo "::error::The output CANCELLED_RUN_IDS must be '[]' in a dry run (got '${CANCELLED_RUN_IDS:-}')" >&2
		errors=1
	fi

	if [ "$errors" -eq 1 ]; then
		return 1
	fi

	echo "✅ Outputs of the dry run: eligible=$ELIGIBLE_COUNT"
}

main "$@"
