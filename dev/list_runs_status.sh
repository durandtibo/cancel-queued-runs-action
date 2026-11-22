#!/usr/bin/env bash
#
# Print a table with the status of the active workflow runs (queued or running) of
# several repositories, sorted by update time (oldest first). Columns: rank (1 = the
# least recently updated), repository, run name, status, created at, updated at (UTC), run ID.
#
# Usage: dev/list_runs_status.sh [-u OWNER] [OWNER/NAME...]
#
# Options:
#   -u, --username OWNER   GitHub user or organization (default: durandtibo)
#   -h, --help             Show this help
#
# Arguments: the repositories to list. Default: the public, non-archived repos of
# the owner.
#
# Requires gh, authenticated (GH_TOKEN or "gh auth login"). A repository whose runs
# cannot be listed is reported on stderr and the exit code is 1.
#
# Exit codes: 0 success; 1 a repository could not be listed; 2 invalid usage.
set -euo pipefail

usage() {
	sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
}

# Print an error annotation and fail (the callers write "|| return 1")
die() {
	echo "::error::$*" >&2
	return 1
}

# Print the public, non-archived repositories of owner $1, one per line
default_repos() {
	gh repo list "$1" --visibility public --no-archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' | sort -f
}

# Print the queued and running runs of repo $1 as "repo|name|status|created|updated|id"
# (fails when they cannot be listed)
list_runs() {
	local status
	for status in queued in_progress; do
		gh api --method GET "/repos/$1/actions/runs" --paginate -f status="$status" -f per_page=100 \
			--jq '.workflow_runs[] | ["'"$1"'", .name, (if .status == "in_progress" then "running" else .status end), .created_at, .updated_at, (.id | tostring)] | join("|")' || return 1
	done
}

# Read "repo|name|status|created|updated|id" rows on stdin; print the table sorted by
# update time (oldest first), the header first
print_table() {
	{
		printf '%s|%s|%s|%s|%s|%s|%s\n' "#" "Repository" "Job" "Status" "Created at" "Updated at" "Job ID"
		LC_ALL=C sort -t'|' -k5,5 | awk '{ print NR "|" $0 }'
	} | awk -F'|' '
		{ for (i = 1; i <= 7; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
		END {
			for (r = 1; r <= NR; r++) {
				printf "%*s  %-*s  %-*s  %-*s  %-*s  %-*s  %*s\n", w[1], c[r, 1], w[2], c[r, 2], w[3], c[r, 3], w[4], c[r, 4], w[5], c[r, 5], w[6], c[r, 6], w[7], c[r, 7]
				if (r == 1) {
					s = ""
					for (i = 0; i < w[1] + w[2] + w[3] + w[4] + w[5] + w[6] + w[7] + 12; i++) s = s "-"
					print s
				}
			}
		}'
}

main() {
	local owner="durandtibo" repos=() repo rows="" out failed=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
		-u | --username)
			[ "$#" -ge 2 ] || {
				die "Missing value for $1"
				return 2
			}
			owner="$2"
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
	if [ "${#repos[@]}" -eq 0 ]; then
		while read -r repo; do
			[ -z "$repo" ] || repos+=("$repo")
		done <<<"$(default_repos "$owner")"
	fi
	for repo in ${repos[@]+"${repos[@]}"}; do
		if out=$(list_runs "$repo"); then
			[ -z "$out" ] || rows="${rows:+$rows$'\n'}$out"
		else
			echo "::warning::Cannot list the runs of $repo" >&2
			failed=1
		fi
	done
	printf '%s\n' "$rows" | print_table
	[ "$failed" -eq 0 ] || return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
