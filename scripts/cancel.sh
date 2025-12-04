#!/usr/bin/env bash
set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

echo "Configured max age: ${MAX_AGE_HOURS} hours"
echo "Checking for stale queued workflow runs for ${REPO}..."

runs=$(gh api \
  -H "Accept: application/vnd.github+json" \
  /repos/$REPO/actions/runs \
  --paginate \
  --jq '.workflow_runs[] | select(.status=="queued") | {id: .id, created_at: .created_at}')

if [ -z "$runs" ]; then
  echo "No queued runs found."
  exit 0
fi

echo "$runs" | jq -c '.' | while read run; do
  run_id=$(echo $run | jq -r '.id')
  created_at=$(echo $run | jq -r '.created_at')

  if [ -z "$run_id" ] || [ -z "$created_at" ]; then
    continue
  fi

  age_hours=$(( ($(date -u +%s) - $(date -d "$created_at" -u +%s)) / 3600 ))

  echo "Run $run_id has been queued for $age_hours hours."

  if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
    echo "Cancelling run $run_id..."
    gh api \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      /repos/$REPO/actions/runs/$run_id/cancel
  fi
done
