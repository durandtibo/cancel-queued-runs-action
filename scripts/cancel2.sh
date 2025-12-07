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
#   0 - Success (all eligible runs cancelled)
#   1 - One or more cancellations failed
#

set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

# ----------------------------
# Cross-platform timestamp parser
# Handles both GNU date (Linux) and BSD date (macOS)
# ----------------------------
# Converts ISO 8601 timestamp to Unix timestamp
# Args:
#   $1 - ISO 8601 timestamp (e.g., "2025-01-15T10:30:00Z")
# Returns:
#   Unix timestamp (seconds since epoch)
to_unix_ts() {
	local ts="$1"

	# Empty input returns 0
	if [ -z "$ts" ]; then
		echo 0
		return
	fi

	if date -d "$ts" +%s >/dev/null 2>&1; then
		# Linux (GNU date)
		date -d "$ts" -u +%s
	else
		# macOS (BSD date)
		date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
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
	*)
		echo "❌ Status code: $status_code for run $run_id"
		;;
	esac
}

# ----------------------------
# Fetch queued runs from GitHub API
# Uses pagination to handle repositories with many queued runs
# ----------------------------
fetch_runs() {
	gh api \
		-H "Accept: application/vnd.github+json" \
		"/repos/$REPO/actions/runs?status=queued&per_page=100" \
		--paginate \
		--jq '.workflow_runs[] | {id: .id, created_at: .created_at}'
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

	gh api \
		-X POST \
		-H "Accept: application/vnd.github+json" \
		"/repos/$REPO/actions/runs/$run_id/cancel" \
		-i 2>/dev/null || true
}

# ----------------------------
# Force cancel a run
# ----------------------------
force_cancel_run() {
	local run_id="$1"

	if [ -z "$run_id" ]; then
		echo "❌ cancel_run error: run_id is empty" >&2
		return 1
	fi

	gh api \
		-X POST \
		-H "Accept: application/vnd.github+json" \
		"/repos/$REPO/actions/runs/$run_id/force-cancel" \
		-i 2>/dev/null || true
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
# Compute the age in hours between two ISO 8601 timestamps
# Args:
#   $1 - ISO 8601 timestamp for "created_at" (e.g., "2025-01-01T10:00:00Z")
#   $2 - ISO 8601 timestamp for "now" (optional, defaults to current UTC time)
# Returns:
#   Age in hours (integer)
# ----------------------------
compute_age_hours() {
	local created_at="$1"
	local now="${2:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

	# Return -1 if any timestamp is empty
	if [ -z "$created_at" ] || [ -z "$now" ]; then
		echo -1
		return
	fi

	local created_ts
	local now_ts

	created_ts=$(to_unix_ts "$created_at")
	now_ts=$(to_unix_ts "$now")

	echo $(((now_ts - created_ts) / 3600))
}

# ----------------------------
# Process a single workflow run
# Cancels the run if needed and logs the result
# Args:
#   $1 - Run ID
#   $2 - Age in hours
#   $3 - Current failed count
# Globals:
#   MAX_AGE_HOURS
#   failed (incremented if cancellation fails)
# ----------------------------
process_run() {
	local run_id="$1"
	local age_hours="$2"
	local failed="$3"

	# Do nothing if run_id is empty
	if [ -z "$run_id" ]; then
		echo "$failed"
		return
	fi

	local response=""
	local status_code=""

	if [ "$age_hours" -gt $((MAX_AGE_HOURS + 3)) ]; then
		echo "Force-cancelling run $run_id (age=$age_hours)..."
		response=$(force_cancel_run "$run_id")
	elif [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
		echo "Cancelling run $run_id (age=$age_hours)..."
		response=$(cancel_run "$run_id")
	else
		# Age does not exceed thresholds, nothing to do
		echo "$failed"
		return
	fi

	status_code=$(get_status_code "$response")
	log_status "$status_code" "$run_id"

	if [ "$status_code" != "202" ]; then
		echo "❌ Cancellation failed for run $run_id"
		failed=$((failed + 1))
	fi

	echo "$failed" # return updated failed count
}

# ----------------------------
# Process all workflow runs
# Args:
#   $1 - JSON array stream from fetch_runs (line-delimited objects)
# Returns:
#   Echoes the final failed count (as integer)
# ----------------------------
process_all_runs() {
	local runs_stream="$1"
	local failed=0

	# Use stdin redirection instead of a pipeline to avoid subshell issues
	while read -r run; do
		run_id=$(echo "$run" | jq -r '.id')
		created_at=$(echo "$run" | jq -r '.created_at')

		# skip invalid entries
		if [ -z "$run_id" ] || [ -z "$created_at" ]; then
			continue
		fi

		age_hours=$(compute_age_hours "$created_at")
		echo "Run $run_id has been queued for $age_hours hours."

		# process the run and get updated failed count
		failed=$(process_run "$run_id" "$age_hours" "$failed")
	done <<<"$runs_stream"

	echo "$failed"
}

# ----------------------------
# Main workflow logic
# ----------------------------
main() {
	echo "⏱ Configured max age: ${MAX_AGE_HOURS} hours"
	echo "🔎 Checking for stale queued workflow runs for ${REPO}..."

	runs=$(fetch_runs)

	run_count=$(echo "$runs" | jq -s 'length')
	echo "Found $run_count queued workflow run(s)."

	if [ "$run_count" -eq 0 ]; then
		echo "✅ No queued runs found."
		return 0
	fi

	# Process runs and get failed count from helper function
	failed=$(process_all_runs "$runs")

	# Exit with error if any cancellations failed
	if [ "$failed" -gt 0 ]; then
		echo "❌ Error: $failed run(s) failed to cancel."
		return 1
	fi

	echo "✅ All eligible runs processed successfully."
}

# Only run when not sourced
#[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
