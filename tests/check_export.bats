#!/usr/bin/env bats

# dev/check_export.sh compares `git archive` with the files the action needs.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SCRIPT="$REPO_ROOT/dev/check_export.sh"
}

@test "check_export passes on the repository" {
	cd "$REPO_ROOT"
	run "$SCRIPT"
	[ "$status" -eq 0 ] || false
	[[ "$output" == *"scripts/cancel.sh"* ]] || false
}

@test "check_export fails when a needed file is not exported" {
	tmp="${BATS_TEST_TMPDIR:-$(mktemp -d)}/repo"
	mkdir -p "$tmp/scripts"
	cd "$tmp"
	git init -q
	git config user.email t@example.com
	git config user.name t
	touch LICENSE action.yaml scripts/cancel.sh
	printf '/scripts/ export-ignore\n' >.gitattributes
	git add -A
	git commit -q -m init
	run "$SCRIPT"
	[ "$status" -eq 1 ] || false
	[[ "$output" == *"::error::"* ]] || false
}
