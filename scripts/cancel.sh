#!/usr/bin/env bash
#
# Cancel Queued Workflow Runs
#
# This script cancels GitHub Actions workflow runs that have been queued
# longer than a specified maximum age (in hours).
#
# Environment Variables:
#   GH_TOKEN - GitHub token with actions:write permission (required)
#   REPO - Repository in owner/name format (required)
#   MAX_AGE_HOURS - Maximum queue age in hours (default: 24)
#
# Exit Codes:
#   0 - Success (all eligible runs cancelled, or no longer cancellable)
#   1 - One or more cancellations failed
#

set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

# ----------------------------
# Cross-platform timestamp parser
# Handles both GNU date (Linux) and BSD date (macOS)
# ----------------------------
# Converts ISO 8601 timestamp to Unix timestamp
# The timestamp must use the format returned by the GitHub API
# (YYYY-MM-DDTHH:MM:SSZ). Anything else is rejected with an ::error:: message
# on stderr, because BSD date silently ignores trailing characters.
# Args:
#   $1 - ISO 8601 timestamp (e.g., "2025-01-15T10:30:00Z")
# Returns:
#   Unix timestamp (seconds since epoch) on stdout. An empty input returns 0.
#   Exit code 1 if the timestamp is invalid.
to_unix_ts() {
	local ts="$1"
	local unix_ts

	# Empty input returns 0
	if [ -z "$ts" ]; then
		echo 0
		return
	fi

	if ! [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
		echo "::error::Invalid timestamp '$ts' (expected format: YYYY-MM-DDTHH:MM:SSZ)" >&2
		return 1
	fi

	if date -d "$ts" +%s >/dev/null 2>&1; then
		# Linux (GNU date)
		date -d "$ts" -u +%s
	elif unix_ts=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null); then
		# macOS (BSD date)
		echo "$unix_ts"
	else
		echo "::error::Cannot parse timestamp '$ts'" >&2
		return 1
	fi
}

# Logs the HTTP status code with appropriate emoji and message
# Args:
#   $1 - HTTP status code
#   $2 - Workflow run ID
log_status() {
	local status_code="$1"
	local run_id="$2"

	case "$status_code" in
	202)
		echo "✅ Status code: $status_code - Cancellation request accepted for run $run_id"
		;;
	500)
		echo "❌ Status code: $status_code - Internal error for run $run_id"
		;;
	"")
		echo "❌ No HTTP response (the gh API call failed) for run $run_id"
		;;
	*)
		echo "❌ Status code: $status_code for run $run_id"
		;;
	esac
}

# ----------------------------
# Fetch queued runs from GitHub API
# Uses pagination to handle repositories with many queued runs
#
# Prints one JSON object per line with the fields:
#   id        - workflow run ID
#   queued_at - the timestamp the age is measured from: updated_at. It is
#               deliberately not created_at: updated_at moves forward when a
#               run is re-run (for example after a failure), so a re-queued
#               run is not cancelled because of its original creation date.
# ----------------------------
fetch_runs() {
	gh api \
		-H "Accept: application/vnd.github+json" \
		"/repos/$REPO/actions/runs?status=queued&per_page=100" \
		--paginate \
		--jq '.workflow_runs[] | {id: .id, queued_at: (.updated_at)}'
}

# ----------------------------
# POST to a cancel endpoint of a workflow run
# Prints the full HTTP response (headers and body) on stdout. If gh writes
# anything on stderr (network error, bad credentials, missing gh, HTTP error
# message, ...), it is forwarded as a ::warning:: annotation on stderr instead
# of being discarded, so that failures can be diagnosed from the logs.
# Always returns 0: the caller decides what to do from the status code.
# Args:
#   $1 - Workflow run ID
#   $2 - Endpoint action ("cancel" or "force-cancel")
# ----------------------------
post_run_endpoint() {
	local run_id="$1"
	local action="$2"
	local stderr_file
	local response

	stderr_file=$(mktemp "${TMPDIR:-/tmp}/cancel-queued-runs.XXXXXX")

	response=$(
		gh api \
			-X POST \
			-H "Accept: application/vnd.github+json" \
			"/repos/$REPO/actions/runs/$run_id/$action" \
			-i 2>"$stderr_file"
	) || true

	if [ -s "$stderr_file" ]; then
		echo "::warning::gh api ($action) failed for run $run_id: $(tr '\n' ' ' <"$stderr_file")" >&2
	fi
	rm -f "$stderr_file"

	if [ -n "$response" ]; then
		printf '%s\n' "$response"
	fi
}

# ----------------------------
# Cancel a run normally
# ----------------------------
cancel_run() {
	local run_id="$1"

	if [ -z "$run_id" ]; then
		echo "❌ cancel_run error: run_id is empty" >&2
		return 1
	fi

	post_run_endpoint "$run_id" "cancel"
}

# ----------------------------
# Force cancel a run
# ----------------------------
force_cancel_run() {
	local run_id="$1"

	if [ -z "$run_id" ]; then
		echo "❌ force_cancel_run error: run_id is empty" >&2
		return 1
	fi

	post_run_endpoint "$run_id" "force-cancel"
}

# ----------------------------
# Extract HTTP status code from a full HTTP response
# Args:
#   $1 - Full HTTP response (string)
# Returns:
#   HTTP status code (e.g., 202, 500)
# ----------------------------
get_status_code() {
	local response="$1"
	# Extract the status code from the first line
	echo "$response" | head -n1 | awk '{print $2}'
}

# ----------------------------
# Compute the age in seconds between two ISO 8601 timestamps
# The age is kept in seconds (not truncated to whole hours) so that a run that
# exceeds the threshold by a few minutes is not treated as if it were younger.
# Args:
#   $1 - ISO 8601 timestamp for "queued_at" (e.g., "2025-01-01T10:00:00Z")
#   $2 - ISO 8601 timestamp for "now" (optional, defaults to current UTC time)
# Returns:
#   Age in seconds (integer), or -1 if a timestamp is empty.
#   Exit code 1 if a timestamp is invalid.
# ----------------------------
compute_age_seconds() {
	local queued_at="$1"
	local now="${2:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

	# Return -1 if any timestamp is empty
	if [ -z "$queued_at" ] || [ -z "$now" ]; then
		echo -1
		return
	fi

	local queued_ts
	local now_ts

	queued_ts=$(to_unix_ts "$queued_at") || return 1
	now_ts=$(to_unix_ts "$now") || return 1

	echo $((now_ts - queued_ts))
}

# ----------------------------
# Format an age in seconds as a human readable "<hours>h<minutes>m" string
# Negative ages (e.g., clock skew) are formatted as 0h00m.
# Args:
#   $1 - Age in seconds (integer)
# Returns:
#   String such as "24h59m"
# ----------------------------
format_age() {
	local seconds="$1"

	if [ "$seconds" -lt 0 ]; then
		seconds=0
	fi

	printf '%dh%02dm' $((seconds / 3600)) $(((seconds % 3600) / 60))
}

# ----------------------------
# Process a single workflow run
# Cancels the run if needed and logs the result
#
# Uses a two-tier cancellation strategy:
# 1. Standard cancel: MAX_AGE_HOURS < age <= MAX_AGE_HOURS + 3 hours
#    - Uses /cancel endpoint for recently queued runs
# 2. Force cancel: age > MAX_AGE_HOURS + 3 hours
#    - Tries /cancel first, then falls back to /force-cancel (which returns
#      409 if no regular cancel was attempted) for very old, stuck runs
#
# A final HTTP 404 (run not found) or 409 (run cannot be cancelled) means that
# the run is gone or already finished, typically because it started or
# completed between the listing and the cancel request. It is reported as a
# warning and is not a failure.
#
# Args:
#   $1 - Run ID
#   $2 - Age in seconds
# Globals:
#   MAX_AGE_HOURS - Base threshold for cancellation
# Returns:
#   0 on success or if the run is no longer cancellable, 1 on failure
# ----------------------------
process_run() {
	local run_id="$1"
	local age_seconds="$2"
	local max_age_seconds=$((MAX_AGE_HOURS * 3600))
	local force_age_seconds=$(((MAX_AGE_HOURS + 3) * 3600))
	local age
	age=$(format_age "$age_seconds")

	# Do nothing if run_id is empty
	if [ -z "$run_id" ]; then
		return 0
	fi

	local response=""
	local status_code=""

	# Force-cancel runs older than MAX_AGE_HOURS + 3 hours
	# The 3-hour buffer ensures standard cancellation is tried first
	if [ "$age_seconds" -gt "$force_age_seconds" ]; then
		echo "Force-cancelling run $run_id (age=$age)..."
		# The force-cancel endpoint returns 409 unless a regular cancel was
		# attempted first, so try the standard cancel and fall back to force.
		response=$(cancel_run "$run_id")
		if [ "$(get_status_code "$response")" != "202" ]; then
			response=$(force_cancel_run "$run_id")
		fi
	elif [ "$age_seconds" -gt "$max_age_seconds" ]; then
		echo "Cancelling run $run_id (age=$age)..."
		response=$(cancel_run "$run_id")
	else
		# Age does not exceed thresholds, nothing to do
		return 0
	fi

	status_code=$(get_status_code "$response")

	if [ "$status_code" = "404" ] || [ "$status_code" = "409" ]; then
		echo "::warning::Run $run_id could not be cancelled (HTTP $status_code): it is no longer queued or cannot be cancelled, skipping."
		return 0
	fi

	log_status "$status_code" "$run_id"

	if [ "$status_code" != "202" ]; then
		echo "❌ Cancellation failed for run $run_id"
		return 1
	fi

	return 0
}

# ----------------------------
# Process all workflow runs
# Args:
#   $1 - JSON array stream from fetch_runs (line-delimited objects)
# Returns:
#   Exit code: 0 on success, 1 if any failures (failed cancellation, or a run
#   whose age could not be computed because of an invalid timestamp)
# ----------------------------
process_all_runs() {
	local runs_stream="$1"
	local failed=0
	local run run_id queued_at age_seconds

	# Use stdin redirection instead of a pipeline to avoid subshell issues
	while read -r run; do
		run_id=$(echo "$run" | jq -r '.id')
		queued_at=$(echo "$run" | jq -r '.queued_at')

		# skip invalid entries
		if [ -z "$run_id" ] || [ "$run_id" = "null" ] || [ -z "$queued_at" ] || [ "$queued_at" = "null" ]; then
			continue
		fi

		# an invalid timestamp is a failure for this run only, not for the others
		if ! age_seconds=$(compute_age_seconds "$queued_at"); then
			echo "::error::Skipping run $run_id: cannot compute its age from '$queued_at'"
			failed=$((failed + 1))
			continue
		fi
		echo "Run $run_id has been queued for $(format_age "$age_seconds")."

		# process the run and track failures
		if ! process_run "$run_id" "$age_seconds"; then
			failed=$((failed + 1))
		fi
	done <<<"$runs_stream"

	# Return failure if any cancellations failed
	if [ "$failed" -gt 0 ]; then
		echo "❌ Error: $failed run(s) failed to cancel."
		return 1
	fi

	return 0
}

# ----------------------------
# Main workflow logic
# ----------------------------
main() {
	if ! [[ "$MAX_AGE_HOURS" =~ ^[1-9][0-9]*$ ]]; then
		echo "❌ MAX_AGE_HOURS must be a positive integer (got '$MAX_AGE_HOURS')" >&2
		return 1
	fi
	if [ -z "${REPO:-}" ]; then
		echo "❌ REPO is required (owner/name)" >&2
		return 1
	fi

	echo "⏱ Configured max age: ${MAX_AGE_HOURS} hours"
	echo "🔎 Checking for stale queued workflow runs for ${REPO}..."

	runs=$(fetch_runs)

	run_count=$(echo "$runs" | jq -s 'length')
	echo "Found $run_count queued workflow run(s)."

	if [ "$run_count" -eq 0 ]; then
		echo "✅ No queued runs found."
		return 0
	fi

	# Process runs
	if process_all_runs "$runs"; then
		echo "✅ All eligible runs processed successfully."
		return 0
	else
		return 1
	fi
}

# ----------------------------
# Entry point
# ----------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main
fi
