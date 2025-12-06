# Notes

## Stale runs

It has been observed that the `force-cancel` request occasionally fails.
This issue primarily occurs with very old runs.
Attempts to cancel these runs manually through the web interface also fail.
When the script encounters this situation, the message displayed will appear as follows.

```textmate
Run 12947114653 has been queued for 7558 hours.
Cancelling run 12947114653...
Status code: 500
Status code: 500 - Internal error for run 12947114653
```

A potential solution is to delete the run.
This can be achieved by adding the following code snippet to the `scripts/cancel.sh` script.
The code is designed to delete only those runs that return a 500 status code and are older than 5000
hours.
This approach ensures that recent or successful runs are not affected, and limits deletion to runs
that are likely causing the issue.

```shell
if [ "$status" = "500" ] && [ "$age_hours" -gt 5000 ]; then
  echo "=== Deleting stale run $run_id ==="
  response=$(gh api \
    --method DELETE \
    -H "Accept: application/vnd.github+json" \
    -i \
    "/repos/$REPO/actions/runs/$run_id" 2>/dev/null || true)

  status=$(echo "$response" | head -n 1 | awk '{print $2}')
  echo "Status code: $status"
fi
```
