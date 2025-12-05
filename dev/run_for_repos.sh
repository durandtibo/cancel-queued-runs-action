#!/usr/bin/env bash
set -euo pipefail

while read -r repo; do
  [ -z "$repo" ] && continue  # skip empty lines
  echo "=== Running cancel script for $repo ==="
  REPO="$repo" scripts/cancel.sh
  echo
done < dev/repos.txt