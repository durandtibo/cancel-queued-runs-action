#!/usr/bin/env bash
#
# Mutation-style sanity check of the bats tests.
#
# A passing test suite proves little if the tests would also pass with a broken
# script. This script breaks scripts/cancel.sh on purpose, one small "mutation"
# at a time (a comparison operator, a status code, a regular expression, ...),
# and runs the tests of the mutated function. Every mutation must make at least
# one of these tests fail: a mutation that survives shows a test that does not
# check what its name says.
#
# Each mutation is applied to a copy of scripts/ and tests/ in a temporary
# directory: the repository is never modified.
#
# The mutations are listed in dev/mutants.txt (see the format there).
#
# Usage: dev/mutation_check.sh [NAME_FILTER]
#   NAME_FILTER   - Only run the mutations whose name contains this text
#   MUTANTS_FILE  - (environment) Other list of mutations (default: dev/mutants.txt)
#
# Exit codes:
#   0 - Every mutation was detected
#   1 - A mutation survived, or did not change the script (outdated expression)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
MUTANTS_FILE="${MUTANTS_FILE:-$ROOT/dev/mutants.txt}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mutation-check.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

TOTAL=0
KILLED=0
line=""
name=""
rest=""
SURVIVED=()
OUTDATED=()

# Files whose tests were already checked to pass on the unmutated script
BASELINE_CHECKED=" "

# Fails when the tests of a file do not pass on the unmutated script: every
# mutation would then be "detected" for the wrong reason
# Args:
#   $1 - Test file, in tests/
check_baseline() {
	local file="$1"

	if [[ "$BASELINE_CHECKED" == *" $file "* ]]; then
		return 0
	fi
	BASELINE_CHECKED="$BASELINE_CHECKED$file "

	if ! bats "$ROOT/tests/$file" >/dev/null 2>&1; then
		echo "::error::tests/$file does not pass on the unmutated script: fix the tests before checking the mutations" >&2
		exit 1
	fi
}

# Runs one mutation
# Args:
#   $1 - Name of the mutation
#   $2 - Test file(s) to run, in tests/ (space-separated)
#   $3 - sed -E expression applied to scripts/cancel.sh
mutant() {
	local name="$1"
	local test_files="$2"
	local expression="$3"
	local dir="$WORK_DIR/mutant"
	local file
	local -a files=()

	if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
		return 0
	fi
	TOTAL=$((TOTAL + 1))

	rm -rf "$dir"
	mkdir -p "$dir"
	cp -R "$ROOT/scripts" "$ROOT/tests" "$dir/"
	sed -E "$expression" "$ROOT/scripts/cancel.sh" >"$dir/scripts/cancel.sh"
	chmod +x "$dir/scripts/cancel.sh"

	if cmp -s "$ROOT/scripts/cancel.sh" "$dir/scripts/cancel.sh"; then
		echo "OUTDATED  $name (the expression does not change the script)"
		OUTDATED+=("$name")
		return 0
	fi

	# A mutation that is not valid bash would be "detected" for the wrong reason
	if ! bash -n "$dir/scripts/cancel.sh" 2>/dev/null; then
		echo "INVALID   $name (the mutated script is not valid bash)"
		OUTDATED+=("$name")
		return 0
	fi

	for file in $test_files; do
		files+=("$dir/tests/$file")
		check_baseline "$file"
	done

	if bats "${files[@]}" >/dev/null 2>&1; then
		echo "SURVIVED  $name"
		SURVIVED+=("$name")
	else
		echo "killed    $name"
		KILLED=$((KILLED + 1))
	fi
}

# The mutations are read from fd 3 so that bats cannot consume them from stdin
while IFS= read -r -u 3 line; do
	case "$line" in
	"" | "#"*) continue ;;
	esac
	name="${line%%@@*}"
	rest="${line#*@@}"
	mutant "$name" "${rest%%@@*}" "${rest#*@@}"
done 3<"$MUTANTS_FILE"

echo
echo "$KILLED of $TOTAL mutation(s) detected."

if [ "${#OUTDATED[@]}" -gt 0 ]; then
	echo "::error::${#OUTDATED[@]} mutation(s) do not change the script any more: update their sed expression in $MUTANTS_FILE" >&2
fi
if [ "${#SURVIVED[@]}" -gt 0 ]; then
	echo "::error::${#SURVIVED[@]} mutation(s) survived: the tests of the function do not detect them" >&2
fi
if [ "${#OUTDATED[@]}" -gt 0 ] || [ "${#SURVIVED[@]}" -gt 0 ]; then
	exit 1
fi
