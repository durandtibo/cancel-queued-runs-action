#!/usr/bin/env bash
set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

echo "Configured max age: ${MAX_AGE_HOURS} hours"
echo "Checking for stale queued workflow runs for ${REPO}..."

# ----------------------------
# Cross-platform timestamp parser
# ----------------------------
to_unix_ts() {
  if date -d "$1" +%s >/dev/null 2>&1; then
    # Linux (GNU date)
    date -d "$1" -u +%s
  else
    # macOS (BSD date)
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s
  fi
}

# ----------------------------
# Fetch queued runs
# ----------------------------
runs=$(gh api \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/actions/runs?status=queued\&per_page=100" \
  --paginate \
  --jq '.workflow_runs[] | {id: .id, created_at: .created_at}')

# Count runs
run_count=$(echo "$runs" | jq -s 'length')
echo "Found $run_count queued workflow run(s)."

if [ "$run_count" -eq 0 ]; then
  echo "No queued runs found."
  exit 0
fi

# ----------------------------
# Process each workflow run
# ----------------------------
echo "$runs" | jq -c '.' | while read -r run; do
  run_id=$(echo "$run" | jq -r '.id')
  created_at=$(echo "$run" | jq -r '.created_at')

  if [ -z "$run_id" ] || [ -z "$created_at" ]; then
    continue
  fi

  # Convert timestamps using ISO-8601 UTC format
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  now_ts=$(to_unix_ts "$now_iso")
  created_ts=$(to_unix_ts "$created_at")

  age_hours=$(( (now_ts - created_ts) / 3600 ))

  echo "Run $run_id has been queued for $age_hours hours."

  if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
    echo "Cancelling run $run_id..."

    status=$(gh api -X POST \
      -H "Accept: application/vnd.github+json" \
      "/repos/$REPO/actions/runs/$run_id/cancel" \
      --silent --status 2>/dev/null || true)

    if [ "$status" = "500" ]; then
      echo "Ignoring 500 error for run $run_id"
    fi
  fi
done
