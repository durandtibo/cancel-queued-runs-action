# Examples

This directory contains practical examples of how to use the Cancel Queued Runs Action in different scenarios.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Scheduled Cleanup](#scheduled-cleanup)
- [Multiple Repositories](#multiple-repositories)
- [Integration with Existing Workflows](#integration-with-existing-workflows)
- [Custom Permissions](#custom-permissions)

---

## Basic Usage

The simplest way to use the action in any workflow:

```yaml
name: My Workflow

on:
  push:
    branches: [main]

permissions:
  actions: write
  contents: read

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.7
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 24
```

See [basic-usage.yaml](./basic-usage.yaml) for a complete example.

---

## Scheduled Cleanup

Run cleanup on a schedule to keep your queue clean automatically:

```yaml
name: Cancel stale queued runs

on:
  schedule:
    # Run every 6 hours
    - cron: "0 */6 * * *"
  workflow_dispatch:

permissions:
  actions: write
  contents: read

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.7
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 12
```

See [scheduled-cleanup.yaml](./scheduled-cleanup.yaml) for a complete example.

---

## Multiple Repositories

Clean up queued runs across multiple repositories using a matrix strategy:

```yaml
name: Multi-repo cleanup

on:
  schedule:
    - cron: "0 0 * * *"
  workflow_dispatch:

permissions:
  actions: write
  contents: read

jobs:
  cleanup:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        repo:
          - owner/repo1
          - owner/repo2
          - owner/repo3
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.7
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ matrix.repo }}
          max_age_hours: 24
```

**Note:** Ensure your token has access to all listed repositories.

See [multi-repo-cleanup.yaml](./multi-repo-cleanup.yaml) for a complete example.

---

## Integration with Existing Workflows

Add cleanup as a final step in your CI workflow:

```yaml
name: CI Pipeline

on:
  pull_request:
  push:
    branches: [main]

permissions:
  actions: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: npm test

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run linter
        run: npm run lint

  cleanup:
    needs: [test, lint]
    if: always()  # Run even if previous jobs fail
    runs-on: ubuntu-latest
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.7
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 6
```

See [ci-integration.yaml](./ci-integration.yaml) for a complete example.

---

## Custom Permissions

Example with minimal permissions and custom token:

```yaml
name: Cleanup with custom token

on:
  workflow_dispatch:

jobs:
  cleanup:
    runs-on: ubuntu-latest
    permissions:
      actions: write  # Required to cancel runs
      contents: read  # Required to read workflow files
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.7
        with:
          # Using a custom token with specific permissions
          github_token: ${{ secrets.CUSTOM_GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 48
```

**Token Requirements:**
- `actions:write` - Required to cancel workflow runs
- `contents:read` - Optional but recommended

See [custom-permissions.yaml](./custom-permissions.yaml) for a complete example.

---

## Tips and Best Practices

### Choosing the Right max_age_hours

- **High-traffic repos**: Use lower values (6-12 hours) to keep the queue moving
- **Low-traffic repos**: Use higher values (24-48 hours) to avoid premature cancellations
- **CI/CD pipelines**: Consider your typical queue time and add a buffer

### When to Run

- **Scheduled**: Best for consistent cleanup without manual intervention
- **On push**: Good for immediate cleanup after merges
- **Manual**: Useful for one-time cleanups or troubleshooting

### Monitoring

Check the action logs to see:
- How many runs were found in the queue
- Which runs were cancelled
- Any failures or errors

Example log output:
```
⏱ Configured max age: 24 hours
🔎 Checking for stale queued workflow runs for owner/repo...
Found 5 queued workflow run(s).
Run 123456789 has been queued for 30 hours.
Cancelling run 123456789 (age=30)...
✅ Status code: 202 - Cancellation request accepted for run 123456789
```
