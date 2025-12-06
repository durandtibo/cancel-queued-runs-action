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

echo "⏱ Configured max age: ${MAX_AGE_HOURS} hours"
echo "🔎 Checking for stale queued workflow runs for ${REPO}..."

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
	if date -d "$1" +%s >/dev/null 2>&1; then
		# Linux (GNU date)
		date -d "$1" -u +%s
	else
		# macOS (BSD date)
		date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s
	fi
}

# Logs the HTTP status code with appropriate emoji and message
# Args:
#   $1 - HTTP status code
#   $2 - Workflow run ID
log_status() {
	local status="$1"
	local run_id="$2"

	case "$status" in
	202)
		echo "✅ Status code: $status - Cancellation request accepted for run $run_id"
		;;
	500)
		echo "⚠️ Status code: $status - Internal error for run $run_id"
		;;
	*)
		echo "❌ Status code: $status for run $run_id"
		;;
	esac
}

# ----------------------------
# Fetch queued runs from GitHub API
# Uses pagination to handle repositories with many queued runs
# ----------------------------
runs=$(gh api \
	-H "Accept: application/vnd.github+json" \
	"/repos/$REPO/actions/runs?status=queued\&per_page=100" \
	--paginate \
	--jq '.workflow_runs[] | {id: .id, created_at: .created_at}')

# Count runs
run_count=$(echo "$runs" | jq -s 'length')
echo "Found $run_count queued workflow run(s)."

if [ "$run_count" -eq 0 ]; then
	echo "✅ No queued runs found."
	exit 0
fi

# ----------------------------
# Process each workflow run
# Calculates age and cancels runs older than MAX_AGE_HOURS
# ----------------------------
failed=0 # Counter for failed cancellations

echo "$runs" | jq -c '.' | while read -r run; do
	run_id=$(echo "$run" | jq -r '.id')
	created_at=$(echo "$run" | jq -r '.created_at')

	if [ -z "$run_id" ] || [ -z "$created_at" ]; then
		continue
	fi

	now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	now_ts=$(to_unix_ts "$now_iso")
	created_ts=$(to_unix_ts "$created_at")

	age_hours=$(((now_ts - created_ts) / 3600))

	echo "Run $run_id has been queued for $age_hours hours."

	if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
		echo "Cancelling run $run_id..."

		# Use force-cancel endpoint to cancel queued runs
		# This endpoint bypasses normal cancellation checks
		response=$(gh api \
			-X POST \
			-H "Accept: application/vnd.github+json" \
			"/repos/$REPO/actions/runs/$run_id/force-cancel" \
			-i 2>/dev/null || true)

		status=$(echo "$response" | head -n 1 | awk '{print $2}')
		echo "Status code: $status"

		log_status "$status" "$run_id"

		if [ "$status" != "202" ]; then
			echo "⚠️ Cancellation failed for run $run_id"
			failed=$((failed + 1))
		fi
	fi
done

# ----------------------------
# Exit with error if any cancellations failed
# ----------------------------
if [ "$failed" -gt 0 ]; then
	echo "❌ Error: $failed run(s) failed to cancel."
	exit 1
fi

echo "✅ All eligible runs processed successfully."
