#!/usr/bin/env bash
#
# Check that the bats tests do not contain assertions that pass vacuously.
#
# On bash 3.2 (the bash of macOS), a failing "[[ ... ]]" or "! command" that is
# not the last command of a test does NOT fail the test: bash ignores "set -e"
# for them. Such an assertion looks like a check but never fails. Ending it with
# "|| false" makes it fail on every bash version.
#
# Usage: dev/check_bats_assertions.sh [DIRECTORY]
#   DIRECTORY - Directory with the .bats files (default: tests)
#
# Exit codes:
#   0 - No problematic assertion
#   1 - At least one assertion needs "|| false" (listed on stderr)
#   2 - Invalid usage (the directory does not exist)

set -euo pipefail

# Prints the problematic lines of a file as "file:line:text"
# Args:
#   $1 - Path of a .bats file
find_vacuous_assertions() {
	local file="$1"

	# A statement that starts with "[[ ... ]]" or with "! " and that does not end
	# with "|| false". Conditions (if, while, &&, ||) are not statements of this
	# form: they do not start the line.
	{ grep -nE '^[[:space:]]*(\[\[ .*\]\]|! .*)$' "$file" || true; } |
		{ grep -v '|| false$' || true; } |
		sed "s#^#${file}:#"
}

main() {
	local dir="${1:-tests}"
	local file output
	local found=0

	if [ ! -d "$dir" ]; then
		echo "Directory not found: $dir" >&2
		return 2
	fi

	for file in "$dir"/*.bats; do
		# An empty directory leaves the unexpanded pattern
		[ -e "$file" ] || continue
		output=$(find_vacuous_assertions "$file")
		if [ -n "$output" ]; then
			echo "$output" >&2
			found=1
		fi
	done

	if [ "$found" -eq 1 ]; then
		echo "::error::Assertions above pass vacuously on bash 3.2 unless they are the last command of a test: end them with '|| false'" >&2
		return 1
	fi
}

main "$@"
