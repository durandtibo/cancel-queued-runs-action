#!/usr/bin/env bash
#
# Cancel Queued Workflow Runs
#
# This script cancels GitHub Actions workflow runs that have been queued
# longer than a specified maximum age (in hours).
#
# Environment Variables:
#   GH_TOKEN - GitHub token with actions:write permission (required, unless
#              GITHUB_TOKEN is set or gh is logged in with "gh auth login")
#   REPO - Repository in owner/name format (required)
#   MAX_AGE_HOURS - Maximum queue age in hours (default: 24)
#
# Internal tuning (not action inputs, positive integers in seconds/counts):
#   MAX_RETRIES - Retries of a rate-limited cancel request (default: 3)
#   RETRY_BASE_DELAY - First backoff delay in seconds, doubled at each retry
#                      when GitHub gives no delay (default: 5)
#   RETRY_MAX_DELAY - Longest delay we are willing to wait, in seconds; a
#                     rate limit that requires waiting longer is not retried
#                     (default: 60)
#
# Exit Codes:
#   0 - Success (all eligible runs cancelled, or no longer cancellable)
#   1 - One or more cancellations failed
#

set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_BASE_DELAY="${RETRY_BASE_DELAY:-5}"
RETRY_MAX_DELAY="${RETRY_MAX_DELAY:-60}"

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
#   queued_at - when the run started waiting: run_started_at (which is reset
#               when a run is re-run), falling back to created_at. updated_at is
#               not used because it changes whenever the run is touched.
# ----------------------------
fetch_runs() {
	gh api \
		-H "Accept: application/vnd.github+json" \
		"/repos/$REPO/actions/runs?status=queued&per_page=100" \
		--paginate \
		--jq '.workflow_runs[] | {id: .id, queued_at: (.run_started_at // .created_at)}'
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
# Tell whether an HTTP response is a rate limit error
# A plain 403 (missing permission) is NOT a rate limit and must not be retried.
# Args:
#   $1 - Full HTTP response (headers and body)
# Returns:
#   0 if rate limited (429, or 403 with a rate limit header/message), else 1
# ----------------------------
is_rate_limited() {
	local response="${1:-}"
	local status_code
	status_code=$(get_status_code "$response")

	if [ "$status_code" = "429" ]; then
		return 0
	fi

	if [ "$status_code" = "403" ] &&
		echo "$response" | grep -qiE '^retry-after:|^x-ratelimit-remaining:[[:space:]]*0[[:space:]]*$|rate limit'; then
		return 0
	fi

	return 1
}

# ----------------------------
# Compute how long to wait before retrying a rate-limited request
# Uses, in order: the Retry-After header, the X-RateLimit-Reset header when
# the quota is exhausted, then an exponential backoff
# (RETRY_BASE_DELAY * 2^(attempt-1)). The result is at least 1 second and is
# NOT capped: the caller compares it with RETRY_MAX_DELAY.
# Args:
#   $1 - Full HTTP response (headers and body)
#   $2 - Attempt number, starting at 1
# Returns:
#   Delay in seconds (integer)
# ----------------------------
get_retry_delay() {
	local response="$1"
	local attempt="${2:-1}"
	local delay=""
	local remaining reset now

	delay=$(echo "$response" | awk 'tolower($1)=="retry-after:" {print int($2+0); exit}')

	if [ -z "$delay" ]; then
		remaining=$(echo "$response" | awk 'tolower($1)=="x-ratelimit-remaining:" {print int($2+0); exit}')
		reset=$(echo "$response" | awk 'tolower($1)=="x-ratelimit-reset:" {print int($2+0); exit}')
		if [ "$remaining" = "0" ] && [ -n "$reset" ]; then
			now=$(date -u +%s)
			delay=$((reset - now + 1))
		fi
	fi

	if [ -z "$delay" ]; then
		delay=$((RETRY_BASE_DELAY * (1 << (attempt - 1))))
	fi

	if [ "$delay" -lt 1 ]; then
		delay=1
	fi

	echo "$delay"
}

# ----------------------------
# POST to a cancel endpoint, retrying when GitHub rate limits the request
# Retries at most MAX_RETRIES times. It gives up immediately, without waiting,
# when the required delay exceeds RETRY_MAX_DELAY. In both cases the last
# response is returned, so the caller handles it like any other failure.
# Args:
#   $1 - Workflow run ID
#   $2 - Endpoint action ("cancel" or "force-cancel")
# ----------------------------
post_run_endpoint_with_retry() {
	local run_id="$1"
	local action="$2"
	local attempt=0
	local response delay

	while :; do
		response=$(post_run_endpoint "$run_id" "$action")

		if ! is_rate_limited "$response"; then
			break
		fi

		attempt=$((attempt + 1))
		delay=$(get_retry_delay "$response" "$attempt")

		if [ "$attempt" -gt "$MAX_RETRIES" ] || [ "$delay" -gt "$RETRY_MAX_DELAY" ]; then
			echo "::warning::Rate limited on run $run_id ($action), giving up (needs ${delay}s, attempt $attempt, max $MAX_RETRIES retries, max wait ${RETRY_MAX_DELAY}s)" >&2
			break
		fi

		echo "::warning::Rate limited on run $run_id ($action), retrying in ${delay}s (retry $attempt/$MAX_RETRIES)" >&2
		sleep "$delay"
	done

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

	post_run_endpoint_with_retry "$run_id" "cancel"
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

	post_run_endpoint_with_retry "$run_id" "force-cancel"
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
	local parsed run_id queued_at age_seconds
	# The unit separator is not whitespace, so read keeps empty fields
	# (a tab would be collapsed and shift the fields)
	local sep=$'\x1f'

	# Extract the fields of all the runs with a single jq call instead of two
	# jq processes per run
	if ! parsed=$(printf '%s\n' "$runs_stream" | jq -r '[.id, .queued_at] | map(tostring) | join("\u001f")'); then
		echo "::error::Cannot parse the list of queued runs" >&2
		return 1
	fi

	# Read from fd 3 and not from stdin, so that nothing running inside the
	# loop can consume the remaining runs. No pipeline: it would run the loop
	# in a subshell and lose the failure counter.
	while IFS="$sep" read -r -u 3 run_id queued_at; do

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
	done 3<<<"$parsed"

	# Return failure if any cancellations failed
	if [ "$failed" -gt 0 ]; then
		echo "❌ Error: $failed run(s) failed to cancel."
		return 1
	fi

	return 0
}

# ----------------------------
# Validate the maximum queue age
# Args:
#   $1 - Maximum queue age in hours
# Returns:
#   0 if it is a positive integer without leading zero, 1 otherwise
# ----------------------------
validate_max_age_hours() {
	local max_age_hours="${1:-}"

	if ! [[ "$max_age_hours" =~ ^[1-9][0-9]*$ ]]; then
		echo "::error::MAX_AGE_HOURS must be a positive integer (got '$max_age_hours')" >&2
		return 1
	fi
}

# ----------------------------
# Validate the target repository
# The value is used to build API paths, so only the characters allowed in
# GitHub owner and repository names are accepted and "." / ".." are rejected.
# Args:
#   $1 - Repository in owner/name format
# Returns:
#   0 if valid, 1 otherwise
# ----------------------------
validate_repo() {
	local target_repo="${1:-}"

	if [ -z "$target_repo" ]; then
		echo "::error::REPO is required (owner/name)" >&2
		return 1
	fi

	if ! [[ "$target_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || [[ "$target_repo" =~ ^\.{1,2}/ ]] || [[ "$target_repo" =~ /\.{1,2}$ ]]; then
		echo "::error::REPO must be in owner/name format (got '$target_repo')" >&2
		return 1
	fi
}

# ----------------------------
# Validate that GitHub credentials are available
# Credentials come from GH_TOKEN / GITHUB_TOKEN (the github_token input in the
# action) or, for local runs, from a session created with "gh auth login".
# Returns:
#   0 if credentials are available, 1 otherwise
# ----------------------------
validate_auth() {
	if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
		return 0
	fi

	if gh auth status >/dev/null 2>&1; then
		return 0
	fi

	echo "::error::No GitHub credentials found: provide a token (github_token input / GH_TOKEN) or run 'gh auth login'" >&2
	return 1
}

# ----------------------------
# Main workflow logic
# ----------------------------
main() {
	validate_max_age_hours "$MAX_AGE_HOURS" || return 1
	validate_repo "${REPO:-}" || return 1
	validate_auth || return 1

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
