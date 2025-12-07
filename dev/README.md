# Developer Notes

This document contains notes, known issues, and development guidance for contributors.

## Table of Contents

- [Stale Runs](#stale-runs)
- [Testing Multiple Repositories](#testing-multiple-repositories)
- [Debugging Tips](#debugging-tips)
- [Architecture Notes](#architecture-notes)

---

## Stale Runs

### Problem

It has been observed that the `force-cancel` request occasionally fails with a 500 status code.
This issue primarily occurs with **very old runs** (multiple months old).
Attempts to cancel these runs manually through the web interface also fail.

**Example output:**

```
Run 12947114653 has been queued for 7558 hours.
Force-cancelling run 12947114653 (age=7558)...
❌ Status code: 500 - Internal error for run 12947114653
```

### Root Cause

GitHub's Actions API has limitations when handling extremely old workflow runs. These runs may
be in a state where the cancellation endpoint cannot properly process them.

### Workaround: Deleting Stale Runs

A potential solution is to delete the run instead of canceling it.
This can be achieved by adding the following code snippet to the `scripts/cancel.sh` script.

**Implementation:**

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

**Considerations:**

- This code is designed to delete only runs that return a 500 status code and are older than 5000
  hours (~208 days)
- This approach ensures that recent or successful runs are not affected
- Deletion is permanent and cannot be undone
- Consider your organization's audit and compliance requirements before implementing this

---

## Testing Multiple Repositories

The `run_for_repos.sh` script allows you to test the cancel action across multiple repositories.

### Setup

1. Add repository names to `dev/repos.txt`, one per line in `owner/name` format:

   ```
   octocat/hello-world
   octocat/spoon-knife
   ```

2. Set your GitHub token:

   ```bash
   export GH_TOKEN="your-github-token"
   ```

3. Run the script:

   ```bash
   ./dev/run_for_repos.sh
   ```

### Use Cases

- Testing the action against multiple repositories you manage
- Batch cleanup of queued runs across an organization
- Validating changes before submitting a PR

---

## Debugging Tips

### Enable Verbose Output

Add debug logging to the script:

```bash
set -x  # Enable debug mode
export GH_DEBUG=api  # Enable GitHub CLI debug output
```

### Test Locally

Run the cancel script locally without using GitHub Actions:

```bash
export GH_TOKEN="your-github-token"
export REPO="owner/repo"
export MAX_AGE_HOURS=24
./scripts/cancel.sh
```

### Mock GitHub API Responses

For testing without actual API calls, you can create wrapper functions:

```bash
# Override gh command for testing
gh() {
  echo "HTTP/1.1 202 Accepted"
  echo "Status: 202 Accepted"
}
```

---

## Architecture Notes

### Force-Cancel Threshold

The action uses a two-tier cancellation strategy:

1. **Standard Cancel** (`MAX_AGE_HOURS` < age ≤ `MAX_AGE_HOURS + 3`)
   - Uses the standard `/cancel` endpoint
   - Graceful cancellation for recently queued runs

2. **Force Cancel** (age > `MAX_AGE_HOURS + 3`)
   - Uses the `/force-cancel` endpoint
   - More aggressive approach for very old runs
   - Necessary because old runs may not respond to standard cancellation

**Example:**
- `MAX_AGE_HOURS=24`
- Runs queued 25-27 hours: Standard cancel
- Runs queued >27 hours: Force cancel

This design helps handle edge cases where runs have been stuck in the queue for extended periods.

### Cross-Platform Compatibility

The script handles date parsing differences between:
- **Linux**: GNU `date` command with `-d` flag
- **macOS**: BSD `date` command with `-j -f` flags

The `to_unix_ts()` function automatically detects the platform and uses the appropriate syntax.
