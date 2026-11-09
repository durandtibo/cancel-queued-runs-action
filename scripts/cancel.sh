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
#   FORCE_BUFFER_HOURS - Hours after MAX_AGE_HOURS from which force-cancel is
#                        used as a fallback (non-negative integer, default: 3)
#   STATUSES - Comma-separated run statuses to consider, among queued, waiting,
#              pending and requested (default: queued)
#   WORKFLOW - Only consider the runs of this workflow, given as a workflow
#              file name (e.g., ci.yaml) or a numeric workflow ID
#              (default: empty, all the workflows)
#   DRY_RUN - "true" to only log the runs that would be cancelled, without
#             calling the cancel endpoints; "false" otherwise (default: false)
#   FAIL_ON_ERROR - "true" to exit with 1 when a run could not be cancelled;
#                   "false" to only log a warning and exit with 0, the failures
#                   remaining in the failed_count output (default: true).
#                   Invalid inputs and a failure to list the runs always fail
#   CANCEL_DELAY_SECONDS - Seconds to wait between two cancel requests, to stay
#                          under the secondary rate limits of GitHub when many
#                          runs are cancelled. Non-negative integer, 0 means no
#                          delay (default: 0)
#
# Internal tuning (not action inputs, positive integers in seconds/counts):
#   MAX_RETRIES - Retries of a rate-limited cancel request (default: 3)
#   RETRY_BASE_DELAY - First backoff delay in seconds, doubled at each retry
#                      when GitHub gives no delay (default: 5)
#   RETRY_MAX_DELAY - Longest delay we are willing to wait, in seconds; a
#                     rate limit that requires waiting longer is not retried
#                     (default: 60)
#   RUNS_LISTING_LIMIT - Number of runs after which GitHub stops listing the
#                        runs of a status (default: 1000, the documented limit
#                        of the API); reaching it gives a warning
#
# GitHub Actions integration (optional, ignored when the variables are unset):
#   GITHUB_OUTPUT - File to which the outputs found_count, cancelled_count,
#                   skipped_count, failed_count and would_cancel_count are written
#   GITHUB_STEP_SUMMARY - File to which a Markdown summary is appended
#
# Exit Codes:
#   0 - Success (all eligible runs cancelled, or no longer cancellable), or
#       cancellations failed and FAIL_ON_ERROR is "false"
#   1 - One or more cancellations failed (and FAIL_ON_ERROR is "true"), the
#       runs could not be listed, or an input is invalid
#

set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
FORCE_BUFFER_HOURS="${FORCE_BUFFER_HOURS:-3}"
WORKFLOW="${WORKFLOW:-}"
STATUSES="${STATUSES:-queued}"
DRY_RUN="${DRY_RUN:-false}"
CANCEL_DELAY_SECONDS="${CANCEL_DELAY_SECONDS:-0}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-true}"

# Counters filled by process_all_runs and reported by main
CANCELLED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
WOULD_CANCEL_COUNT=0

# Whether a cancel request was already sent, to wait before the next one. It
# is set by throttle_requests, which must not be called in a subshell.
REQUEST_SENT=false

# Outcome of the last process_run call: one of
#   noop, cancelled, skipped, would-cancel, failed
PROCESS_RUN_OUTCOME=""
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_BASE_DELAY="${RETRY_BASE_DELAY:-5}"
RETRY_MAX_DELAY="${RETRY_MAX_DELAY:-60}"
RUNS_LISTING_LIMIT="${RUNS_LISTING_LIMIT:-1000}"

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
# Warn when the listing of a status may be incomplete
# GitHub returns at most RUNS_LISTING_LIMIT (1000) runs for a query that
# filters on the status, however many exist. When that many runs are listed,
# the list is probably truncated and the oldest runs may be missing.
# Args:
#   $1 - Run status that was listed
#   $2 - Number of runs listed for this status
# Returns:
#   Always 0. The warning is written on stderr.
# ----------------------------
warn_if_listing_truncated() {
	local run_status="$1"
	local count="$2"

	if [ "$count" -ge "$RUNS_LISTING_LIMIT" ]; then
		echo "::warning::$count runs were listed for the status '$run_status', which is the maximum that GitHub returns for a query: older runs may be missing from the list and will not be considered until the runs listed now are cancelled. Run the action again to process them." >&2
	fi
}

# ----------------------------
# Fetch queued runs from GitHub API
# Uses pagination to handle repositories with many queued runs
#
# If WORKFLOW is set, only the runs of that workflow are listed, through the
# per-workflow endpoint (the filtering is done by GitHub).
#
# The API accepts a single status per request, so each status of STATUSES
# (comma-separated, duplicates ignored) is listed with its own paginated call.
#
# Prints one JSON object per line with the fields:
#   id        - workflow run ID
#   queued_at - the timestamp the age is measured from: updated_at. It is
#               deliberately not created_at: updated_at moves forward when a
#               run is re-run (for example after a failure), so a re-queued
#               run is not cancelled because of its original creation date.
#
# A warning is written on stderr for a status when GitHub lists as many runs
# as it is able to return (see warn_if_listing_truncated).
#
# Returns:
#   0 on success, 1 as soon as a listing call fails (the runs already printed
#   are incomplete then, so the caller must not use them). The check is
#   explicit because "set -e" is ignored when the function is called in an
#   "if" condition.
# ----------------------------
fetch_runs() {
	local runs_path="/repos/$REPO/actions/runs"

	if [ -n "$WORKFLOW" ]; then
		runs_path="/repos/$REPO/actions/workflows/$WORKFLOW/runs"
	fi

	local run_status listed count
	local seen=","
	local -a status_list=()
	IFS=',' read -r -a status_list <<<"${STATUSES// /}"

	# ${arr[@]+...} avoids an "unbound variable" error for an empty array with
	# set -u on bash 3.2
	for run_status in ${status_list[@]+"${status_list[@]}"}; do
		if [[ "$seen" == *",$run_status,"* ]]; then
			continue
		fi
		seen="$seen$run_status,"

		listed=$(
			gh api \
				-H "Accept: application/vnd.github+json" \
				"$runs_path?status=$run_status&per_page=100" \
				--paginate \
				--jq '.workflow_runs[] | {id: .id, queued_at: (.updated_at)}'
		) || return 1

		if [ -n "$listed" ]; then
			printf '%s\n' "$listed"
			count=$(printf '%s\n' "$listed" | grep -c '')
			warn_if_listing_truncated "$run_status" "$count"
		fi
	done
}

# ----------------------------
# Tell whether an HTTP status code means that the run is no longer cancellable
# 404 (run not found) and 409 (run cannot be cancelled) are expected when a
# run starts or completes between the listing and the cancel request.
# Args:
#   $1 - HTTP status code
# Returns:
#   0 for 404 and 409, 1 otherwise
# ----------------------------
is_skippable_status() {
	local status_code="${1:-}"

	[ "$status_code" = "404" ] || [ "$status_code" = "409" ]
}

# ----------------------------
# POST to a cancel endpoint of a workflow run
# Prints the full HTTP response (headers and body) on stdout. If gh writes
# anything on stderr (network error, bad credentials, missing gh, HTTP error
# message, ...), it is forwarded as a ::warning:: annotation on stderr instead
# of being discarded, so that failures can be diagnosed from the logs. The
# exception is a response with an expected status (404 or 409, see
# is_skippable_status): process_run already reports it with a single warning.
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

	if [ -s "$stderr_file" ] && ! is_skippable_status "$(get_status_code "$response")"; then
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
# Wait before a cancel request, when another one was sent before
# Spaces the requests by CANCEL_DELAY_SECONDS (GitHub asks for about one second
# between mutating requests; faster bursts trigger secondary rate limits). The
# first request of an execution is never delayed. Nothing is waited for when
# CANCEL_DELAY_SECONDS is 0. It records that a request is about to be sent in a
# global variable, so it must be called in the main shell, not in a subshell
# such as $(...).
# Globals:
#   CANCEL_DELAY_SECONDS - Seconds to wait between two requests
#   REQUEST_SENT - Set to true by this function
# ----------------------------
throttle_requests() {
	if [ "$REQUEST_SENT" = "true" ] && [ "$CANCEL_DELAY_SECONDS" -gt 0 ]; then
		sleep "$CANCEL_DELAY_SECONDS"
	fi

	REQUEST_SENT=true
}

# ----------------------------
# Process a single workflow run
# Cancels the run if needed and logs the result
#
# Uses a two-tier cancellation strategy:
# 1. Standard cancel: MAX_AGE_HOURS < age <= MAX_AGE_HOURS + FORCE_BUFFER_HOURS
#    - Uses /cancel endpoint for recently queued runs
# 2. Force cancel: age > MAX_AGE_HOURS + FORCE_BUFFER_HOURS
#    - Tries /cancel first, then falls back to /force-cancel (which returns
#      409 if no regular cancel was attempted) for very old, stuck runs
#
# A final HTTP 404 (run not found) or 409 (run cannot be cancelled) means that
# the run is gone or already finished, typically because it started or
# completed between the listing and the cancel request. It is reported as a
# warning and is not a failure.
#
# When DRY_RUN is "true", the run that would be cancelled is only logged and
# no request is sent.
#
# The outcome is stored in PROCESS_RUN_OUTCOME (noop, cancelled, skipped,
# would-cancel or failed) so that the caller can count what happened.
#
# Args:
#   $1 - Run ID
#   $2 - Age in seconds
# Globals:
#   MAX_AGE_HOURS - Base threshold for cancellation
#   FORCE_BUFFER_HOURS - Extra hours before force-cancel is used
#   DRY_RUN - "true" to log without cancelling
#   CANCEL_DELAY_SECONDS - Seconds to wait between two requests (see
#                          throttle_requests)
# Returns:
#   0 on success or if the run is no longer cancellable, 1 on failure
# ----------------------------
process_run() {
	local run_id="$1"
	local age_seconds="$2"
	local max_age_seconds=$((MAX_AGE_HOURS * 3600))
	local force_age_seconds=$(((MAX_AGE_HOURS + FORCE_BUFFER_HOURS) * 3600))
	local age
	age=$(format_age "$age_seconds")

	PROCESS_RUN_OUTCOME="noop"

	# Do nothing if run_id is empty
	if [ -z "$run_id" ]; then
		return 0
	fi

	local response=""
	local status_code=""

	# Force-cancel runs older than MAX_AGE_HOURS + FORCE_BUFFER_HOURS hours
	# The buffer gives the standard cancellation time to work for recent runs
	if [ "$age_seconds" -gt "$force_age_seconds" ]; then
		if [ "$DRY_RUN" = "true" ]; then
			echo "🧪 [dry-run] Would force-cancel run $run_id (age=$age)"
			PROCESS_RUN_OUTCOME="would-cancel"
			return 0
		fi
		echo "Force-cancelling run $run_id (age=$age)..."
		# The force-cancel endpoint returns 409 unless a regular cancel was
		# attempted first, so try the standard cancel and fall back to force.
		throttle_requests
		response=$(cancel_run "$run_id")
		if [ "$(get_status_code "$response")" != "202" ]; then
			throttle_requests
			response=$(force_cancel_run "$run_id")
		fi
	elif [ "$age_seconds" -gt "$max_age_seconds" ]; then
		if [ "$DRY_RUN" = "true" ]; then
			echo "🧪 [dry-run] Would cancel run $run_id (age=$age)"
			PROCESS_RUN_OUTCOME="would-cancel"
			return 0
		fi
		echo "Cancelling run $run_id (age=$age)..."
		throttle_requests
		response=$(cancel_run "$run_id")
	else
		# Age does not exceed thresholds, nothing to do
		return 0
	fi

	status_code=$(get_status_code "$response")

	if is_skippable_status "$status_code"; then
		echo "::warning::Run $run_id could not be cancelled (HTTP $status_code): it is no longer queued or cannot be cancelled, skipping."
		PROCESS_RUN_OUTCOME="skipped"
		return 0
	fi

	log_status "$status_code" "$run_id"

	if [ "$status_code" != "202" ]; then
		echo "❌ Cancellation failed for run $run_id"
		PROCESS_RUN_OUTCOME="failed"
		return 1
	fi

	PROCESS_RUN_OUTCOME="cancelled"
	return 0
}

# ----------------------------
# Reset the counters reported by main, and forget the requests already sent
# ----------------------------
reset_counters() {
	CANCELLED_COUNT=0
	SKIPPED_COUNT=0
	FAILED_COUNT=0
	WOULD_CANCEL_COUNT=0
	REQUEST_SENT=false
}

# ----------------------------
# Process all workflow runs
# Updates the counters CANCELLED_COUNT, SKIPPED_COUNT, FAILED_COUNT and
# WOULD_CANCEL_COUNT (reset at the start of the call).
# Args:
#   $1 - JSON array stream from fetch_runs (line-delimited objects)
# Returns:
#   Exit code: 0 on success, 1 if any failures (failed cancellation, or a run
#   whose age could not be computed because of an invalid timestamp)
# ----------------------------
process_all_runs() {
	local runs_stream="$1"
	local parsed run_id queued_at age_seconds
	# The unit separator is not whitespace, so read keeps empty fields
	# (a tab would be collapsed and shift the fields)
	local sep=$'\x1f'

	reset_counters

	# Extract the fields of all the runs with a single jq call instead of two
	# jq processes per run
	if ! parsed=$(printf '%s\n' "$runs_stream" | jq -r '[.id, .queued_at] | map(tostring) | join("\u001f")'); then
		echo "::error::Cannot parse the list of queued runs" >&2
		return 1
	fi

	# Read from fd 3 and not from stdin, so that nothing running inside the
	# loop can consume the remaining runs. No pipeline: it would run the loop
	# in a subshell and lose the counters.
	while IFS="$sep" read -r -u 3 run_id queued_at; do
		# skip invalid entries
		if [ -z "$run_id" ] || [ "$run_id" = "null" ] || [ -z "$queued_at" ] || [ "$queued_at" = "null" ]; then
			continue
		fi

		# an invalid timestamp is a failure for this run only, not for the others
		if ! age_seconds=$(compute_age_seconds "$queued_at"); then
			echo "::error::Skipping run $run_id: cannot compute its age from '$queued_at'"
			FAILED_COUNT=$((FAILED_COUNT + 1))
			continue
		fi
		echo "Run $run_id has been queued for $(format_age "$age_seconds")."

		# process the run and count what happened
		PROCESS_RUN_OUTCOME=""
		if process_run "$run_id" "$age_seconds"; then
			case "$PROCESS_RUN_OUTCOME" in
			cancelled) CANCELLED_COUNT=$((CANCELLED_COUNT + 1)) ;;
			skipped) SKIPPED_COUNT=$((SKIPPED_COUNT + 1)) ;;
			would-cancel) WOULD_CANCEL_COUNT=$((WOULD_CANCEL_COUNT + 1)) ;;
			esac
		else
			FAILED_COUNT=$((FAILED_COUNT + 1))
		fi
	done 3<<<"$parsed"

	# Return failure if any cancellations failed
	if [ "$FAILED_COUNT" -gt 0 ]; then
		echo "❌ Error: $FAILED_COUNT run(s) failed to cancel."
		return 1
	fi

	return 0
}

# ----------------------------
# Write the action outputs to $GITHUB_OUTPUT (no-op when it is unset)
# Args:
#   $1 - Number of queued runs found
# ----------------------------
write_outputs() {
	local found_count="$1"

	if [ -z "${GITHUB_OUTPUT:-}" ]; then
		return 0
	fi

	{
		echo "found_count=$found_count"
		echo "cancelled_count=$CANCELLED_COUNT"
		echo "skipped_count=$SKIPPED_COUNT"
		echo "failed_count=$FAILED_COUNT"
		echo "would_cancel_count=$WOULD_CANCEL_COUNT"
	} >>"$GITHUB_OUTPUT"
}

# ----------------------------
# Append a Markdown summary to $GITHUB_STEP_SUMMARY (no-op when it is unset)
# Args:
#   $1 - Number of queued runs found
# ----------------------------
write_summary() {
	local found_count="$1"
	local mode="Cancel stale queued runs"

	if [ -z "${GITHUB_STEP_SUMMARY:-}" ]; then
		return 0
	fi

	if [ "$DRY_RUN" = "true" ]; then
		mode="Cancel stale queued runs (dry run, nothing was cancelled)"
	fi

	{
		echo "### $mode"
		echo
		echo "Repository: \`${REPO}\`, maximum queue age: ${MAX_AGE_HOURS} hours"
		if [ -n "$WORKFLOW" ]; then
			echo
			echo "Workflow: \`${WORKFLOW}\`"
		fi
		echo
		echo "| Result | Runs |"
		echo "| --- | ---: |"
		echo "| Queued runs found | $found_count |"
		echo "| Cancelled | $CANCELLED_COUNT |"
		echo "| Would be cancelled (dry run) | $WOULD_CANCEL_COUNT |"
		echo "| Skipped (no longer cancellable) | $SKIPPED_COUNT |"
		echo "| Failed | $FAILED_COUNT |"
	} >>"$GITHUB_STEP_SUMMARY"
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
# Validate the force-cancel buffer
# Args:
#   $1 - Buffer in hours
# Returns:
#   0 if it is a non-negative integer without leading zero, 1 otherwise
# ----------------------------
validate_force_buffer_hours() {
	local force_buffer_hours="${1:-}"

	if ! [[ "$force_buffer_hours" =~ ^(0|[1-9][0-9]*)$ ]]; then
		echo "::error::FORCE_BUFFER_HOURS must be a non-negative integer (got '$force_buffer_hours')" >&2
		return 1
	fi
}

# ----------------------------
# Validate the list of run statuses
# Only the statuses of runs that have not started are accepted, so that a
# typo can never make the action cancel a run that is already in progress.
# Args:
#   $1 - Comma-separated statuses (spaces around commas are ignored)
# Returns:
#   0 if every status is one of queued, waiting, pending, requested; 1 otherwise
# ----------------------------
validate_statuses() {
	local statuses="${1:-}"
	local run_status
	local -a status_list=()

	statuses="${statuses// /}"
	if [ -z "$statuses" ]; then
		echo "::error::STATUSES must not be empty (allowed: queued, waiting, pending, requested)" >&2
		return 1
	fi

	IFS=',' read -r -a status_list <<<"$statuses"
	for run_status in "${status_list[@]}"; do
		case "$run_status" in
		queued | waiting | pending | requested) ;;
		*)
			echo "::error::STATUSES contains an unsupported status '$run_status' (allowed: queued, waiting, pending, requested)" >&2
			return 1
			;;
		esac
	done
}

# ----------------------------
# Validate the workflow filter
# The value is used to build an API path, so only the characters of a workflow
# file name or ID are accepted ("." and ".." are rejected). Empty means no
# filter.
# Args:
#   $1 - Workflow file name or ID (may be empty)
# Returns:
#   0 if valid, 1 otherwise
# ----------------------------
validate_workflow() {
	local workflow="${1:-}"

	if [ -z "$workflow" ]; then
		return 0
	fi

	if ! [[ "$workflow" =~ ^[A-Za-z0-9_.-]+$ ]] || [ "$workflow" = "." ] || [ "$workflow" = ".." ]; then
		echo "::error::WORKFLOW must be a workflow file name (e.g., ci.yaml) or a numeric ID (got '$workflow')" >&2
		return 1
	fi
}

# ----------------------------
# Validate the dry run flag
# Args:
#   $1 - "true" or "false"
# Returns:
#   0 if valid, 1 otherwise
# ----------------------------
validate_dry_run() {
	local dry_run="${1:-}"

	if [ "$dry_run" != "true" ] && [ "$dry_run" != "false" ]; then
		echo "::error::DRY_RUN must be 'true' or 'false' (got '$dry_run')" >&2
		return 1
	fi
}

# ----------------------------
# Validate the fail on error flag
# Args:
#   $1 - "true" or "false"
# Returns:
#   0 if valid, 1 otherwise
# ----------------------------
validate_fail_on_error() {
	local fail_on_error="${1:-}"

	if [ "$fail_on_error" != "true" ] && [ "$fail_on_error" != "false" ]; then
		echo "::error::FAIL_ON_ERROR must be 'true' or 'false' (got '$fail_on_error')" >&2
		return 1
	fi
}

# ----------------------------
# Validate the delay between cancel requests
# Args:
#   $1 - Delay in seconds
# Returns:
#   0 if it is a non-negative integer without leading zero, 1 otherwise
# ----------------------------
validate_cancel_delay_seconds() {
	local delay="${1:-}"

	if ! [[ "$delay" =~ ^(0|[1-9][0-9]*)$ ]]; then
		echo "::error::CANCEL_DELAY_SECONDS must be a non-negative integer (got '$delay')" >&2
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
# Validate that the required commands are installed
# gh and jq are pre-installed on GitHub-hosted runners but not necessarily on
# self-hosted ones. All the missing commands are reported in a single message,
# before any API call, instead of failing later with "command not found".
# Returns:
#   0 if gh and jq are available, 1 otherwise
# ----------------------------
validate_dependencies() {
	local cmd
	local -a missing=()

	for cmd in gh jq; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		echo "::error::Required command(s) not found: ${missing[*]} (install them on the runner; they are pre-installed on GitHub-hosted runners)" >&2
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
	validate_dependencies || return 1
	validate_max_age_hours "$MAX_AGE_HOURS" || return 1
	validate_repo "${REPO:-}" || return 1
	validate_force_buffer_hours "$FORCE_BUFFER_HOURS" || return 1
	validate_statuses "$STATUSES" || return 1
	validate_workflow "$WORKFLOW" || return 1
	validate_dry_run "$DRY_RUN" || return 1
	validate_fail_on_error "$FAIL_ON_ERROR" || return 1
	validate_cancel_delay_seconds "$CANCEL_DELAY_SECONDS" || return 1
	validate_auth || return 1

	echo "⏱ Configured max age: ${MAX_AGE_HOURS} hours"
	if [ "$DRY_RUN" = "true" ]; then
		echo "🧪 Dry run enabled: no run will be cancelled."
	fi
	if [ "$CANCEL_DELAY_SECONDS" -gt 0 ]; then
		echo "Waiting ${CANCEL_DELAY_SECONDS}s between two cancel requests."
	fi
	echo "🔎 Checking for stale queued workflow runs for ${REPO}..."
	if [ "${STATUSES// /}" != "queued" ]; then
		echo "Run statuses considered: ${STATUSES// /}"
	fi
	if [ -n "$WORKFLOW" ]; then
		echo "Only the runs of the workflow ${WORKFLOW} are considered."
	fi

	reset_counters
	local exit_code=0
	local runs run_count

	# The outputs are written even when the listing fails, so that the next
	# steps do not read empty values
	if ! runs=$(fetch_runs); then
		echo "::error::Cannot list the workflow runs of ${REPO} (see the messages above)" >&2
		write_outputs 0
		return 1
	fi

	run_count=$(echo "$runs" | jq -s 'length')
	echo "Found $run_count queued workflow run(s)."

	if [ "$run_count" -eq 0 ]; then
		echo "✅ No queued runs found."
	elif process_all_runs "$runs"; then
		echo "✅ All eligible runs processed successfully."
	elif [ "$FAIL_ON_ERROR" = "true" ]; then
		exit_code=1
	else
		echo "::warning::$FAILED_COUNT run(s) could not be processed, but fail_on_error is false: the step does not fail (see the failed_count output)."
	fi

	# Report even when some runs failed
	write_outputs "$run_count"
	write_summary "$run_count"

	return "$exit_code"
}

# ----------------------------
# Entry point
# ----------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main
fi
