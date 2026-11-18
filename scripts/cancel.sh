#!/usr/bin/env bash
#
# Cancel the workflow runs of one repository that have not started (queued by
# default) for longer than MAX_AGE_HOURS. The age is measured from updated_at, so
# a re-run restarts it; a run is cancelled only if updated_at is strictly older.
#
# Inputs are the environment variables of action.yaml (REPO, MAX_AGE_HOURS,
# FORCE_BUFFER_HOURS, STATUSES, WORKFLOW, BRANCH, EVENT, FAIL_ON_ERROR, DRY_RUN,
# GH_TOKEN), validated before the first API call. Outputs go to $GITHUB_OUTPUT
# (see action.yaml) and a summary to $GITHUB_STEP_SUMMARY.
#
# Exit codes: 0 success; 1 invalid input, runs that cannot be listed, or a run
# that could not be cancelled (unless FAIL_ON_ERROR is false).

set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
FORCE_BUFFER_HOURS="${FORCE_BUFFER_HOURS:-3}"
STATUSES="${STATUSES:-queued}"
WORKFLOW="${WORKFLOW:-}"
BRANCH="${BRANCH:-}"
EVENT="${EVENT:-}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-true}"
DRY_RUN="${DRY_RUN:-false}"

# Print an error annotation and fail (the callers write "|| return 1")
die() {
	echo "::error::$*" >&2
	return 1
}

# Check the variable named $1 against the rule $2: pint (positive integer, at
# most $3 when given), nint, bool, statuses, repo, workflow or line (one line,
# used for the values sent as fields)
require() {
	local name="$1" value="${!1:-}" ok=false
	case "$2" in
	pint) [[ $value =~ ^[1-9][0-9]*$ ]] && [ "${#value}" -le 9 ] && [ "$value" -le "${3:-999999999}" ] && ok=true ;;
	nint) [[ $value =~ ^(0|[1-9][0-9]*)$ ]] && ok=true ;;
	bool) [[ $value == true || $value == false ]] && ok=true ;;
	statuses) [[ ${value// /} =~ ^(queued|waiting|pending|requested)(,(queued|waiting|pending|requested))*$ ]] && ok=true ;;
	repo) [[ $value =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && ! $value =~ ^\.{1,2}/ && ! $value =~ /\.{1,2}$ ]] && ok=true ;;
	workflow) [[ -z $value || ($value =~ ^[A-Za-z0-9_.-]+$ && $value != . && $value != ..) ]] && ok=true ;;
	line) [[ $value != *$'\n'* && $value != *$'\r'* ]] && ok=true ;;
	esac
	[ "$ok" = true ] || die "$name is not valid for the rule '$2${3:+ (at most $3)}' (got '$value')"
}

# Validate every input, then the tools and the credentials, before any API call
validate_all() {
	local cmd
	for cmd in gh jq; do
		command -v "$cmd" >/dev/null 2>&1 || {
			die "Required command not found: $cmd"
			return 1
		}
	done
	require MAX_AGE_HOURS pint 87600 || return 1
	require FORCE_BUFFER_HOURS nint || return 1
	require STATUSES statuses || return 1
	require FAIL_ON_ERROR bool || return 1
	require DRY_RUN bool || return 1
	require REPO repo || return 1
	require WORKFLOW workflow || return 1
	require BRANCH line || return 1
	require EVENT line || return 1
	if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
		die "No GitHub credentials found: provide a token (GH_TOKEN) or run 'gh auth login'"
	fi
}

# Print the ISO 8601 UTC time MAX_AGE_HOURS before $1 (epoch seconds, default: now)
cutoff() {
	jq -nr --argjson n "${1:-null}" --argjson h "$MAX_AGE_HOURS" '(($n // now) - $h * 3600) | floor | todate'
}

# Print {id, updated_at} lines of the candidate runs, one listing per distinct
# status. $1: cutoff. The server only returns the runs created before it, which
# includes every stale run (updated_at >= created_at); select_stale decides.
list_stale() {
	local path="/repos/$REPO/actions/runs" status seen=" " out
	local -a extra=()
	if [ -n "$WORKFLOW" ]; then path="/repos/$REPO/actions/workflows/$WORKFLOW/runs"; fi
	if [ -n "$BRANCH" ]; then extra+=(-f "branch=$BRANCH"); fi
	if [ -n "$EVENT" ]; then extra+=(-f "event=$EVENT"); fi
	for status in ${STATUSES//[ ,]/ }; do
		case "$seen" in *" $status "*) continue ;; esac
		seen="$seen$status "
		out=$(gh api --method GET "$path" --paginate -f status="$status" -f per_page=100 \
			-f "created=<$1" ${extra[@]+"${extra[@]}"} --jq '.workflow_runs[] | {id, updated_at}') || return 1
		[ -z "$out" ] && continue
		printf '%s\n' "$out"
		if [ "$(printf '%s\n' "$out" | grep -c .)" -ge 1000 ]; then
			echo "::warning title=Run list truncated::GitHub lists at most 1000 runs per status: older '$status' runs may be missing, the next execution continues" >&2
		fi
	done
}

# Print the number of runs in the statuses of STATUSES whatever their age (the
# runs "found"), or - when GitHub cannot say. Only used for the log line.
count_found() {
	local path="/repos/$REPO/actions/runs" status seen=" " n total=0
	if [ -n "$WORKFLOW" ]; then path="/repos/$REPO/actions/workflows/$WORKFLOW/runs"; fi
	local -a extra=()
	if [ -n "$BRANCH" ]; then extra+=(-f "branch=$BRANCH"); fi
	if [ -n "$EVENT" ]; then extra+=(-f "event=$EVENT"); fi
	for status in ${STATUSES//[ ,]/ }; do
		case "$seen" in *" $status "*) continue ;; esac
		seen="$seen$status "
		n=$(gh api --method GET "$path" -f status="$status" -f per_page=1 \
			${extra[@]+"${extra[@]}"} --jq '.total_count' 2>/dev/null) || {
			echo "-"
			return 0
		}
		[[ $n =~ ^[0-9]+$ ]] || {
			echo "-"
			return 0
		}
		total=$((total + n))
	done
	echo "$total"
}

# Read {id, updated_at} lines, print "id age_seconds" for the runs whose
# updated_at is strictly before $1 (cutoff), without duplicates, oldest first (within the listed runs).
# $2: now (epoch seconds), only used for the age. ISO 8601 UTC strings compare
# as plain strings.
select_stale() {
	jq -r -s --arg c "$1" --argjson now "$2" '
		map(select(.updated_at | type == "string")) | unique_by(.id)
		| map(select(.updated_at < $c)) | sort_by(.updated_at)
		| .[] | "\(.id) \($now - (.updated_at | fromdateiso8601))"'
}

# Print $1 seconds as 25h12m3s (hours are not split into days).
format_age() {
	echo "$(($1 / 3600))h$(($1 % 3600 / 60))m$(($1 % 60))s"
}

# Cancel run $1 (age $2 in seconds) and print cancelled, skipped, rate-limited
# or failed. gh api exits non-zero from HTTP 400 and writes "(HTTP nnn)" on
# stderr. A 404 or 409 (gone, finished) is skipped; a 429, or a 403 about a rate
# limit, stops the execution. After another error on /cancel, a run older than
# MAX_AGE_HOURS + FORCE_BUFFER_HOURS is sent once to /force-cancel.
cancel_run() {
	local path="/repos/$REPO/actions/runs/$1" action out code
	for action in cancel force-cancel; do
		if out=$(gh api --method POST "$path/$action" 2>&1 >/dev/null </dev/null); then
			echo cancelled
			return 0
		fi
		code=$(printf '%s' "$out" | sed -nE 's/.*\(HTTP ([0-9]{3})\).*/\1/p' | head -n 1)
		if [[ $code == 404 || $code == 409 ]]; then
			echo skipped
			return 0
		fi
		if [[ $code == 429 ]] || { [[ $code == 403 ]] && grep -qi 'rate limit' <<<"$out"; }; then
			echo rate-limited
			return 0
		fi
		echo "  $action of run $1 failed: $out" >&2
		if [ "$action" = cancel ] && [ "$2" -gt $(((MAX_AGE_HOURS + FORCE_BUFFER_HOURS) * 3600)) ]; then continue; fi
		break
	done
	echo failed
}

# Read "id age" lines, cancel the runs oldest first and print
# "eligible cancelled skipped failed ids" (ids is a JSON array on one line).
# One second separates two requests that write. A rate limit stops the loop:
# the runs after it count as failed and the next execution takes them.
cancel_all() {
	local id age outcome eligible=0 cancelled=0 skipped=0 failed=0 ids="" stop=false
	while read -r id age; do
		[ -n "$id" ] || continue
		eligible=$((eligible + 1))
		if [ "$stop" = true ]; then
			failed=$((failed + 1))
			continue
		fi
		if [ "$DRY_RUN" = true ]; then
			echo "[dry-run] Would cancel run $id (age ${age}s, $(format_age "$age"))" >&2
			continue
		fi
		if [ $((cancelled + skipped + failed)) -gt 0 ]; then sleep 1; fi
		outcome=$(cancel_run "$id" "$age")
		echo "Run $id (age ${age}s, $(format_age "$age")): $outcome" >&2
		case "$outcome" in
		cancelled)
			cancelled=$((cancelled + 1))
			ids="${ids:+$ids,}$id"
			;;
		skipped)
			skipped=$((skipped + 1))
			echo "::warning title=Run not cancelled::Run $id no longer exists or cannot be cancelled (HTTP 404 or 409)" >&2
			;;
		rate-limited)
			failed=$((failed + 1))
			stop=true
			echo "::warning title=Rate limited::GitHub rate limited the requests: the runs after $id are left for the next execution" >&2
			;;
		*) failed=$((failed + 1)) ;;
		esac
	done
	echo "$eligible $cancelled $skipped $failed [$ids]"
}

# Write the five outputs: eligible cancelled skipped failed ids (no-op without $GITHUB_OUTPUT)
write_outputs() {
	[ -n "${GITHUB_OUTPUT:-}" ] || return 0
	printf 'eligible-count=%s\ncancelled-count=%s\nskipped-count=%s\nfailed-count=%s\ncancelled-run-ids=%s\n' \
		"$1" "$2" "$3" "$4" "$5" >>"$GITHUB_OUTPUT"
}

# Append one summary table (same arguments as write_outputs), with the first 50
# runs of the array $5 as links: the cancelled runs, or in a dry run the eligible
# ones (no-op without $GITHUB_STEP_SUMMARY)
write_summary() {
	[ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
	{
		echo "### Cancel stale runs in \`$REPO\`"
		echo
		echo "Runs not updated for more than $MAX_AGE_HOURS hours, statuses \`${STATUSES// /}\`."
		[ "$DRY_RUN" = true ] && echo "Dry run: nothing was cancelled."
		echo
		echo "| Eligible | Cancelled | Skipped | Failed |"
		echo "| ---: | ---: | ---: | ---: |"
		echo "| $1 | $2 | $3 | $4 |"
		if [ "$5" != "[]" ]; then
			echo
			if [ "$DRY_RUN" = true ]; then echo "Would cancel:"; else echo "Cancelled:"; fi
			echo
			printf '%s' "$5" | jq -r --arg s "${GITHUB_SERVER_URL:-https://github.com}" --arg r "$REPO" \
				'.[:50][] | "- [\(.)](\($s)/\($r)/actions/runs/\(.))"'
		fi
	} >>"$GITHUB_STEP_SUMMARY"
}

main() {
	validate_all || return 1
	local now cut stale found eligible cancelled skipped failed ids
	now=$(jq -nr 'now | floor')
	cut=$(cutoff "$now")
	echo "Cancelling the runs of $REPO not updated since $cut (more than $MAX_AGE_HOURS hours)..."
	if ! stale=$(list_stale "$cut" | select_stale "$cut" "$now"); then
		write_outputs 0 0 0 0 '[]'
		die "Cannot list the workflow runs of $REPO (see the messages above)"
		return 1
	fi
	found=$(count_found)
	read -r eligible cancelled skipped failed ids <<<"$(cancel_all <<<"$stale")"
	echo "Found: $found, eligible: $eligible, cancelled: $cancelled, skipped: $skipped, failed: $failed"
	write_outputs "$eligible" "$cancelled" "$skipped" "$failed" "$ids"
	if [ "$DRY_RUN" = true ]; then
		ids=$(jq -R -s -c '[split("\n")[] | select(length > 0) | split(" ")[0] | tonumber]' <<<"$stale")
	fi
	write_summary "$eligible" "$cancelled" "$skipped" "$failed" "$ids"
	if [ "$failed" -gt 0 ]; then
		if [ "$FAIL_ON_ERROR" = true ]; then
			die "$failed run(s) could not be cancelled"
			return 1
		fi
		echo "::warning title=Cancellation failed::$failed run(s) could not be cancelled, but FAIL_ON_ERROR is false"
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
