#!/usr/bin/env bash
#
# Run scripts/cancel.sh on all the public, non-archived repositories of a user.
#
# Usage: dev/run_for_repos.sh [-u USERNAME] [-a MAX_AGE_HOURS] [-r MAX_RUNS]
#
# Options:
#   -u, --username USERNAME        GitHub user or organization (default: durandtibo)
#   -a, --max-age-hours HOURS      Value of MAX_AGE_HOURS (default: that of cancel.sh)
#   -r, --max-runs N               Value of MAX_RUNS (default: that of cancel.sh)
#   -h, --help                     Show this help
#
# Requires gh, authenticated (GH_TOKEN or "gh auth login"). The other
# environment variables of cancel.sh (DRY_RUN, ...) are passed through.
set -euo pipefail

usage() {
	sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
	local username="durandtibo" max_age="" max_runs=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		-u | --username | -a | --max-age-hours | -r | --max-runs)
			if [ "$#" -lt 2 ]; then
				echo "::error::Missing value for $1" >&2
				return 2
			fi
			case "$1" in
			-u | --username) username="$2" ;;
			-a | --max-age-hours) max_age="$2" ;;
			*) max_runs="$2" ;;
			esac
			shift 2
			;;
		-h | --help)
			usage
			return 0
			;;
		*)
			echo "::error::Unknown argument: $1" >&2
			usage >&2
			return 2
			;;
		esac
	done

	if [ -z "$username" ]; then
		echo "::error::The username must not be empty" >&2
		return 2
	fi
	if [ -n "$max_age" ]; then export MAX_AGE_HOURS="$max_age"; fi
	if [ -n "$max_runs" ]; then export MAX_RUNS="$max_runs"; fi

	local repos
	repos=$(gh repo list "$username" --visibility public --no-archived \
		--limit 1000 --json nameWithOwner --jq '.[].nameWithOwner')
	if [ -z "$repos" ]; then
		echo "No public, non-archived repository found for $username" >&2
		return 0
	fi

	local failed=() repo
	while read -r repo; do
		[ -z "$repo" ] && continue
		echo "=== Running cancel script for $repo ==="
		if ! REPO="$repo" scripts/cancel.sh; then
			echo "!!! Failed for $repo, continuing" >&2
			failed+=("$repo")
		fi
		echo
	done <<<"$repos"

	if [ "${#failed[@]}" -gt 0 ]; then
		echo "Failed repos: ${failed[*]}" >&2
		return 1
	fi
}

main "$@"
