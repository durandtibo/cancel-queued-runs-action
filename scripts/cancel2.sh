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

#MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
#
#echo "⏱ Configured max age: ${MAX_AGE_HOURS} hours"
#echo "🔎 Checking for stale queued workflow runs for ${REPO}..."

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
		return 0
	fi

	if date -d "$ts" +%s >/dev/null 2>&1; then
		date -d "$ts" -u +%s
	else
		date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
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

	gh api \
		-X POST \
		-H "Accept: application/vnd.github+json" \
		"/repos/$REPO/actions/runs/$run_id/force-cancel" \
		-i 2>/dev/null || true
}
