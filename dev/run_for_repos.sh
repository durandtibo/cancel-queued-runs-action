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

# Print the value of a key from a GITHUB_OUTPUT file (0 when missing)
read_output() {
	local value
	value=$(sed -n "s/^$2=//p" "$1" | tail -n1)
	echo "${value:-0}"
}

# Print the summary table. Args: total found, cancelled, skipped, then "repo|found|cancelled|skipped" rows
print_summary() {
	local total_found="$1" total_cancelled="$2" total_skipped="$3" row
	shift 3
	echo "=== Summary ==="
	{
		printf '%s|%s|%s|%s\n' "Repository" "Running" "Cancelled" "Skipped"
		for row in "$@"; do printf '%s\n' "$row"; done
		printf '%s|%s|%s|%s\n' "Total" "$total_found" "$total_cancelled" "$total_skipped"
	} | awk -F'|' '
		{ for (i = 1; i <= 4; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
		END {
			for (r = 1; r <= NR; r++) {
				printf "%-*s  %*s  %*s  %*s\n", w[1], c[r, 1], w[2], c[r, 2], w[3], c[r, 3], w[4], c[r, 4]
				if (r == 1 || r == NR - 1) {
					printf "%s\n", sep(w[1] + w[2] + w[3] + w[4] + 6)
				}
			}
		}
		function sep(n, s) { s = sprintf("%*s", n, ""); gsub(/ /, "-", s); return s }'
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
		--limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' | sort -f)
	if [ -z "$repos" ]; then
		echo "No public, non-archived repository found for $username" >&2
		return 0
	fi

	local out_file
	out_file=$(mktemp)
	# shellcheck disable=SC2064 # expand now: out_file is local to main
	trap "rm -f '$out_file'" EXIT

	local failed=() summary=() repo found cancelled skipped
	local total_found=0 total_cancelled=0 total_skipped=0
	while read -r repo; do
		[ -z "$repo" ] && continue
		echo "=== Running cancel script for $repo ==="
		: >"$out_file"
		if GITHUB_OUTPUT="$out_file" REPO="$repo" scripts/cancel.sh; then
			found=$(read_output "$out_file" found_count)
			cancelled=$(read_output "$out_file" cancelled_count)
			total_found=$((total_found + found))
			skipped=$(read_output "$out_file" skipped_count)
			total_cancelled=$((total_cancelled + cancelled))
			total_skipped=$((total_skipped + skipped))
			summary+=("$repo|$found|$cancelled|$skipped")
		else
			echo "!!! Failed for $repo, continuing" >&2
			failed+=("$repo")
			summary+=("$repo|-|-|-")
		fi
		echo
	done <<<"$repos"

	print_summary "$total_found" "$total_cancelled" "$total_skipped" "${summary[@]}"

	if [ "${#failed[@]}" -gt 0 ]; then
		echo "Failed repos: ${failed[*]}" >&2
		return 1
	fi
}

main "$@"
