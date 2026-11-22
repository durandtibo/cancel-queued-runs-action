#!/usr/bin/env bash
#
# Let the queued runs of a target repository start first: cancel the runs that are
# queued in the other repositories and re-run each of them right after, so they go
# to the back of the queue. Nothing is done when the target has no queued run.
#
# Usage: dev/requeue_queued_runs.sh -t OWNER/NAME [OWNER/NAME...]
#
# Options:
#   -t, --target OWNER/NAME   Repository to prioritize (required)
#   -h, --help                Show this help
#
# Arguments: the repositories to requeue. Default: the public, non-archived repos of
# the owner of the target (the target excluded).
#
# Environment variables:
#   DRY_RUN       true to only list the runs that would be requeued (default: false)
#   WAIT_SECONDS  Time to wait for a cancelled run to complete before giving up
#                 on it (default: 60)
#   POLL_SECONDS  Time between two checks of a cancelled run (default: 2)
#   NO_COLOR      Set to disable the colors (they are only used on a terminal)
#
# Requires gh and jq, authenticated (GH_TOKEN or "gh auth login") with actions: write
# on the repositories. A re-run is only possible once the run is completed, hence
# the wait after the cancel. A run that was cancelled but could not be re-run is
# listed at the end: re-run it by hand.
#
# Exit codes: 0 success; 1 a run could not be listed, cancelled or re-run; 2 invalid usage.
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
WAIT_SECONDS="${WAIT_SECONDS:-60}"
POLL_SECONDS="${POLL_SECONDS:-2}"

usage() {
	sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
}

# Print an error annotation and fail (the callers write "|| return 1")
die() {
	echo "::error::$*" >&2
	return 1
}

# Print "$2" in the ANSI color $1 (32 green, 33 yellow, 31 red, 36 cyan, 1 bold) when
# stdout and stderr are terminals and NO_COLOR is not set, otherwise print it as is
paint() {
	if [ -t 1 ] && [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
		printf '\033[%sm%s\033[0m' "$1" "$2"
	else
		printf '%s' "$2"
	fi
}

# Print the emoji and the colored name of the outcome $1 of requeue_run
outcome_label() {
	case "$1" in
	requeued) paint 32 "✅ requeued" ;;
	skipped) paint 33 "⏭️  skipped" ;;
	*) paint 31 "❌ failed" ;;
	esac
}

# Print the ids of the queued runs of repo $1, oldest first (fails when they cannot be listed)
list_queued_ids() {
	local out
	out=$(gh api --method GET "/repos/$1/actions/runs" --paginate -f status=queued -f per_page=100 \
		--jq '.workflow_runs[] | .id') || return 1
	[ -z "$out" ] || printf '%s\n' "$out" | sort -n
}

# Print the status of run $2 of repo $1 (fails when it cannot be read)
run_status() {
	gh api --method GET "/repos/$1/actions/runs/$2" --jq '.status'
}

# Wait until run $2 of repo $1 is completed (fails after WAIT_SECONDS)
wait_completed() {
	local waited=0 status
	while [ "$waited" -le "$WAIT_SECONDS" ]; do
		status=$(run_status "$1" "$2") || status=""
		[ "$status" = completed ] && return 0
		sleep "$POLL_SECONDS"
		waited=$((waited + POLL_SECONDS))
	done
	return 1
}

# Cancel run $2 of repo $1, wait for it to complete and re-run it. Print
# requeued, skipped (it started or finished meanwhile: nothing was changed) or
# failed. After "failed" the run may be cancelled and not re-run.
requeue_run() {
	local path="/repos/$1/actions/runs/$2" out
	if ! out=$(gh api --method POST "$path/cancel" 2>&1 >/dev/null </dev/null); then
		if grep -qE '\(HTTP (404|409)\)' <<<"$out"; then
			echo skipped
		else
			echo "  cancel of run $2 failed: $out" >&2
			echo failed
		fi
		return 0
	fi
	if ! wait_completed "$1" "$2"; then
		echo "  run $2 is not completed after ${WAIT_SECONDS}s" >&2
		echo failed
		return 0
	fi
	if ! out=$(gh api --method POST "$path/rerun" 2>&1 >/dev/null </dev/null); then
		echo "  re-run of run $2 failed: $out" >&2
		echo failed
		return 0
	fi
	echo requeued
}

# Print the public, non-archived repositories of owner $1 other than $2, one per line
default_repos() {
	gh repo list "$1" --visibility public --no-archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' |
		grep -vxF "$2" | sort -f || true
}

# Requeue the queued runs of repo $1; print "found requeued skipped failed" and
# append the runs to check by hand ("repo id") to the file $2
requeue_repo() {
	local ids id outcome found=0 requeued=0 skipped=0 failed=0
	if ! ids=$(list_queued_ids "$1"); then
		echo "::warning::⚠️  Cannot list the queued runs of $1" >&2
		echo "0 0 0 1"
		return 0
	fi
	while read -r id; do
		[ -n "$id" ] || continue
		found=$((found + 1))
		if [ "$DRY_RUN" = true ]; then
			echo "$(paint 36 "🔍 [dry-run]") Would requeue run $id of $1" >&2
			continue
		fi
		outcome=$(requeue_run "$1" "$id")
		echo "Run $id of $1: $(outcome_label "$outcome")" >&2
		case "$outcome" in
		requeued) requeued=$((requeued + 1)) ;;
		skipped) skipped=$((skipped + 1)) ;;
		*)
			failed=$((failed + 1))
			echo "$1 $id" >>"$2"
			;;
		esac
	done <<<"$ids"
	echo "$found $requeued $skipped $failed"
}

main() {
	local target="" repos=() repo
	while [ "$#" -gt 0 ]; do
		case "$1" in
		-t | --target)
			[ "$#" -ge 2 ] || {
				die "Missing value for $1"
				return 2
			}
			target="$2"
			shift 2
			;;
		-h | --help)
			usage
			return 0
			;;
		-*)
			usage >&2
			die "Unknown option: $1"
			return 2
			;;
		*)
			repos+=("$1")
			shift
			;;
		esac
	done
	[[ $target =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
		die "--target must be OWNER/NAME (got '$target')"
		return 2
	}
	[[ $DRY_RUN == true || $DRY_RUN == false ]] || {
		die "DRY_RUN must be true or false (got '$DRY_RUN')"
		return 2
	}
	[[ $WAIT_SECONDS =~ ^[0-9]+$ && $POLL_SECONDS =~ ^[1-9][0-9]*$ ]] || {
		die "WAIT_SECONDS must be an integer and POLL_SECONDS a positive integer"
		return 2
	}

	local queued
	queued=$(list_queued_ids "$target") || {
		die "Cannot list the queued runs of $target"
		return 1
	}
	if [ -z "$queued" ]; then
		echo "😴 $(paint 1 "No queued run in $target"): nothing to prioritize"
		return 0
	fi
	echo "🚦 $(paint 1 "$(grep -c . <<<"$queued") queued run(s) in $target"): requeueing the other repositories"

	if [ "${#repos[@]}" -eq 0 ]; then
		while read -r repo; do
			[ -z "$repo" ] || repos+=("$repo")
		done <<<"$(default_repos "${target%%/*}" "$target")"
	fi

	local leftover found requeued skipped failed total_requeued=0 total_failed=0
	leftover=$(mktemp)
	# shellcheck disable=SC2064 # expand now: leftover is local to main
	trap "rm -f '$leftover'" EXIT
	for repo in ${repos[@]+"${repos[@]}"}; do
		[ "$repo" != "$target" ] || continue
		read -r found requeued skipped failed <<<"$(requeue_repo "$repo" "$leftover")"
		echo "📦 $(paint 1 "$repo"): queued $found, requeued $requeued, skipped $skipped, failed $failed"
		total_requeued=$((total_requeued + requeued))
		total_failed=$((total_failed + failed))
	done
	if [ "$total_failed" -eq 0 ]; then
		{
			paint 32 "🎉 Requeued: $total_requeued, failed: $total_failed"
			echo
		}
	else
		{
			paint 31 "💥 Requeued: $total_requeued, failed: $total_failed"
			echo
		}
	fi
	if [ -s "$leftover" ]; then
		{
			paint 31 "⚠️  Check these runs, they may be cancelled and not re-run (repository, run id):"
			echo
		} >&2
		cat "$leftover" >&2
	fi
	[ "$total_failed" -eq 0 ] || return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
