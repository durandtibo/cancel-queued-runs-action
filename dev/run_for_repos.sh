#!/usr/bin/env bash
set -euo pipefail

failed=()

while read -r repo; do
	repo="$(echo "$repo" | tr -d '\r' | xargs)" # remove CR and trim
	[ -z "$repo" ] && continue                  # skip empty lines
	echo "=== Running cancel script for $repo ==="
	if ! REPO="$repo" scripts/cancel.sh; then
		echo "!!! Failed for $repo, continuing" >&2
		failed+=("$repo")
	fi
	echo
done <dev/repos.txt

if [ "${#failed[@]}" -gt 0 ]; then
	echo "Failed repos: ${failed[*]}" >&2
	exit 1
fi
