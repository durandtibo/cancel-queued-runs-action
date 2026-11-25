#!/usr/bin/env bash
#
# Run scripts/cancel.sh on all the public, non-archived repositories of a user.
#
# Usage: dev/run_for_repos.sh [-u USERNAME] [-a MAX_AGE_HOURS]
#
# Options:
#   -u, --username USERNAME        GitHub user or organization (default: durandtibo)
#   -a, --max-age-hours HOURS      Value of MAX_AGE_HOURS (default: that of cancel.sh)
#   -h, --help                     Show this help
#
# Requires gh, authenticated (GH_TOKEN or "gh auth login"). The other
# environment variables of cancel.sh (DRY_RUN, ...) are passed through.
# On a terminal, rows with cancelled runs are colored yellow (ANSI code in
# CANCELLED_COLOR, e.g. 31 for red); NO_COLOR disables it.
set -euo pipefail

usage() {
	sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
}

# Print the value of a key from a GITHUB_OUTPUT file (0 when missing)
read_output() {
	local value
	value=$(sed -n "s/^$2=//p" "$1" | tail -n1)
	echo "${value:-0}"
}

# Print the number of runs of repo $1 whose status is queued right now (- when it cannot be read)
count_queued() {
	# On failure gh prints the error body on stdout, so keep the output only when it is a number
	local count
	count=$(gh api --method GET "/repos/$1/actions/runs" -f status=queued -f per_page=1 --jq '.total_count' 2>/dev/null) || count=""
	if [[ $count =~ ^[0-9]+$ ]]; then echo "$count"; else echo "-"; fi
}

# Print the summary table (a row with Cancelled > 0 is colored on a terminal), sorted by ascending Queued (a "-" last), then by name.
# Args: total queued, eligible, cancelled, skipped, then "repo|queued|eligible|cancelled|skipped" rows
print_summary() {
	local total_queued="$1" total_found="$2" total_cancelled="$3" total_skipped="$4" row
	shift 4
	# ANSI color of the rows with cancelled runs (33 = yellow); empty when not on a terminal or NO_COLOR is set
	local color=""
	if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then color="${CANCELLED_COLOR:-33}"; fi
	echo "=== Summary ==="
	{
		printf '%s|%s|%s|%s|%s\n' "Repository" "Queued" "Eligible" "Cancelled" "Skipped"
		for row in "$@"; do printf '%s\n' "$row"; done |
			awk -F'|' '{ print (($2 == "-") ? 999999999 : $2) "|" $0 }' |
			LC_ALL=C sort -t'|' -k1,1n -k2,2f | cut -d'|' -f2-
		printf '%s|%s|%s|%s|%s\n' "Total" "$total_queued" "$total_found" "$total_cancelled" "$total_skipped"
	} | awk -F'|' -v color="$color" '
		{ for (i = 1; i <= 5; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
		END {
			for (r = 1; r <= NR; r++) {
				line = sprintf("%-*s  %*s  %*s  %*s  %*s", w[1], c[r, 1], w[2], c[r, 2], w[3], c[r, 3], w[4], c[r, 4], w[5], c[r, 5])
				if (color != "" && r > 1 && r < NR && c[r, 4] + 0 > 0) line = "\033[" color "m" line "\033[0m"
				print line
				if (r == 1 || r == NR - 1) {
					printf "%s\n", sep(w[1] + w[2] + w[3] + w[4] + w[5] + 8)
				}
			}
		}
		function sep(n, s) { s = sprintf("%*s", n, ""); gsub(/ /, "-", s); return s }'
}

main() {
	local username="durandtibo" max_age=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		-u | --username | -a | --max-age-hours)
			if [ "$#" -lt 2 ]; then
				echo "::error::Missing value for $1" >&2
				return 2
			fi
			case "$1" in
			-u | --username) username="$2" ;;
			*) max_age="$2" ;;
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

	local failed=() summary=() repo found cancelled skipped queued
	local total_found=0 total_cancelled=0 total_skipped=0 total_queued=0
	while read -r repo; do
		[ -z "$repo" ] && continue
		echo "=== Running cancel script for $repo ($(count_queued "$repo") queued runs found) ==="
		: >"$out_file"
		if GITHUB_OUTPUT="$out_file" REPO="$repo" scripts/cancel.sh; then
			found=$(read_output "$out_file" eligible-count)
			cancelled=$(read_output "$out_file" cancelled-count)
			total_found=$((total_found + found))
			skipped=$(read_output "$out_file" skipped-count)
			total_cancelled=$((total_cancelled + cancelled))
			total_skipped=$((total_skipped + skipped))
			queued=$(count_queued "$repo")
			if [[ $queued =~ ^[0-9]+$ ]]; then total_queued=$((total_queued + queued)); fi
			summary+=("$repo|$queued|$found|$cancelled|$skipped")
		else
			echo "!!! Failed for $repo, continuing" >&2
			failed+=("$repo")
			summary+=("$repo|-|-|-|-")
		fi
		echo
	done <<<"$repos"

	print_summary "$total_queued" "$total_found" "$total_cancelled" "$total_skipped" "${summary[@]}"
	echo
	echo "Repositories processed: ${#summary[@]}"

	if [ "${#failed[@]}" -gt 0 ]; then
		echo "Failed repos: ${failed[*]}" >&2
		return 1
	fi
}

main "$@"
