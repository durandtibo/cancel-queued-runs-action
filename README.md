# 🧹 Cancel Queued Runs Action

<p align="center">
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml">
        <img alt="CI" src="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml/badge.svg">
    </a>
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly.yaml">
        <img alt="Nightly Tests" src="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly.yaml/badge.svg">
    </a>
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/blob/main/LICENSE">
        <img alt="License" src="https://img.shields.io/badge/License-BSD_3--Clause-blue.svg">
    </a>
</p>

Automatically cancel GitHub Actions workflow runs that have been **queued longer than a configurable
number of hours**. This helps keep your repository’s workflow queue clean and prevents long-running
backlogs.

---

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Usage](#-usage)
- [Inputs](#-inputs)
- [Outputs](#-outputs)
- [Examples](#-examples)
- [How It Works](#-how-it-works)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Limitations](#-limitations)
- [Contributing](#-contributing)
- [Changelog](#-changelog)
- [License](#license)

---

## 🚀 Features

- Cancels workflow runs stuck in the **queued** state (optionally also `waiting`, `pending` and
  `requested`)
- Configurable maximum queue age (in hours)
- Dry-run mode to preview which runs would be cancelled
- Optional filter to only cancel the runs of one workflow
- Lightweight composite action
- Works with private and public repositories
- Requires only the GitHub-provided `GITHUB_TOKEN`

---

## 📋 Prerequisites

This action requires:

- **GitHub Token**: The action needs `actions:write` permission to cancel workflow runs. The default
  `GITHUB_TOKEN` provided by GitHub Actions has this permission.
- **GitHub CLI** (`gh`) and **jq**: Pre-installed on all GitHub-hosted runners (ubuntu-latest,
  macos-latest, etc.). On a self-hosted runner, install both.
- **Shell Environment**: Works on both Linux (GNU) and macOS (BSD) runners

---

## 📦 Usage

Add the following job to any workflow where you want stale queued runs to be automatically
cancelled. Releases are published as exact version tags (`v1.9`, ...); there is no floating `v1`
tag. For the best supply-chain safety, pin the action to the commit SHA of a release
(`uses: durandtibo/cancel-queued-runs-action@<sha> # v1.9`).

```yaml
jobs:
  cancel-stale-runs:
    runs-on: ubuntu-latest
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.9
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 24
```

---

## 🛠 Inputs

| Name                        | Required | Default                    | Description                                                                             |
| --------------------------- | -------- | -------------------------- | --------------------------------------------------------------------------------------- |
| `github_token`              | ❌ No    | `${{ github.token }}`      | Token with `actions:write` permissions                                                  |
| `repo`                      | ❌ No    | `${{ github.repository }}` | Repository in `owner/name` format                                                       |
| `max_age_hours`             | ❌ No    | `24`                       | Maximum number of hours a run is allowed to stay queued                                 |
| `force_cancel_buffer_hours` | ❌ No    | `3`                        | Hours after `max_age_hours` from which force-cancel is used as a fallback (`0` allowed) |
| `statuses`                  | ❌ No    | `queued`                   | Run statuses to consider: `queued`, `waiting`, `pending`, `requested` (comma-separated) |
| `workflow`                  | ❌ No    | `""` (all workflows)       | Only cancel the runs of this workflow (file name such as `ci.yaml`, or numeric ID)      |
| `dry_run`                   | ❌ No    | `false`                    | If `true`, only log the runs that would be cancelled                                    |

> **Note**: `force_cancel_buffer_hours`, `statuses`, `workflow`, `dry_run` and all the
> [outputs](#-outputs) were added after `v1.9`. Use a later release (or a commit of `main`) to get
> them; the examples below that use them need such a release.

---

## 📤 Outputs

| Name                 | Description                                                                 |
| -------------------- | --------------------------------------------------------------------------- |
| `found_count`        | Number of queued workflow runs found in the repository                      |
| `cancelled_count`    | Number of runs for which a cancel request was accepted                      |
| `skipped_count`      | Number of runs skipped because they were no longer cancellable (404 or 409) |
| `failed_count`       | Number of runs that could not be cancelled                                  |
| `would_cancel_count` | Number of runs that would be cancelled (dry run only, otherwise `0`)        |

The outputs are written even when some runs failed (the step then fails, so use `if: always()` on
a following step to read them), and the action appends the same counts as a table to the
[job summary](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary).

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  id: cancel
  with:
    max_age_hours: 24
- run: echo "Cancelled ${{ steps.cancel.outputs.cancelled_count }} run(s)"
```

---

## ⏱ Examples

### Example: cancel queued runs older than 6 hours

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    repo: ${{ github.repository }}
    max_age_hours: 6
```

### Example: preview what would be cancelled (dry run)

Set `dry_run: true` to list the runs that would be cancelled without cancelling anything. Use it
the first time you add the action to a repository.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  with:
    max_age_hours: 24
    dry_run: true
```

The log then contains lines such as:

```text
Run 12947114653 has been queued for 30h12m.
🧪 [dry-run] Would force-cancel run 12947114653 (age=30h12m)
```

### Example: also cancel runs waiting for an approval or a concurrency slot

By default only the runs with the status `queued` are cancelled. Runs that GitHub reports as
`waiting` (for example for an environment approval), `pending` or `requested` are not. Use
`statuses` to include them. Runs that are `in_progress` are never cancelled: they are rejected by
the input validation.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  with:
    max_age_hours: 48
    statuses: queued,waiting
```

### Example: only cancel the runs of one workflow

`workflow` takes a workflow file name (the name of the file in `.github/workflows/`) or a numeric
workflow ID. The display name of a workflow (the `name:` key) is not supported because several
workflows can share it.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  with:
    max_age_hours: 12
    workflow: ci.yaml
```

### Example: scheduled cleanup every hour

```yaml
name: Cancel stale queued runs

on:
  schedule:
    - cron: "0 * * * *"
  workflow_dispatch:

permissions:
  actions: write
  contents: read

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.9
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 12
```

### More Examples

For additional use cases and complete workflow examples, see the [examples/](examples/) directory:

- **[Basic Usage](examples/basic-usage.yaml)** - Simple integration in any workflow
- **[Scheduled Cleanup](examples/scheduled-cleanup.yaml)** - Automated cleanup on a schedule
- **[Multi-Repository](examples/multi-repo-cleanup.yaml)** - Clean up multiple repos with matrix strategy
- **[CI Integration](examples/ci-integration.yaml)** - Integrate with existing CI/CD pipelines
- **[Custom Permissions](examples/custom-permissions.yaml)** - Use custom tokens and permissions

---

## 🧩 How It Works

1. **Fetch Queued Runs**: Uses the GitHub API to list all workflow runs with status `queued`
2. **Calculate Age**: Determines how long each run has been queued, measured from its last update
   (`updated_at`), which moves forward when a run is re-run, for example after a failure
3. **Filter**: Identifies runs older than the configured `max_age_hours`
4. **Cancel**: Sends cancellation requests for eligible runs (or only logs them with `dry_run: true`)
5. **Report**: Logs the status of each operation

The action uses the GitHub CLI (`gh`) internally to interact with GitHub's Actions API. It includes
cross-platform timestamp parsing to work correctly on both Linux (GNU date) and macOS (BSD date).

### Cancellation Strategy

The action uses a two-tier cancellation approach:

- **Standard Cancel**: For runs between `max_age_hours` and
  `max_age_hours + force_cancel_buffer_hours` hours old
  - Uses the standard `/cancel` endpoint
  - Graceful cancellation for recently queued runs

- **Force Cancel**: For runs older than `max_age_hours + force_cancel_buffer_hours` hours
  (`force_cancel_buffer_hours` defaults to `3`)
  - Sends a standard `/cancel` request first: this is required because GitHub rejects
    `/force-cancel` (HTTP `409`) for a run that never received a regular cancel request
  - Falls back to the `/force-cancel` endpoint **only if** the standard request is not accepted
    (anything other than HTTP `202`)
  - More aggressive approach necessary for very old, stuck runs

**Example**: If `max_age_hours: 24` and `force_cancel_buffer_hours: 3` (the default):

- Runs queued more than 24 hours and up to 27 hours: Standard cancel
- Runs queued more than 27 hours: Standard cancel first, then force cancel if it was not accepted

Set `force_cancel_buffer_hours: 0` to allow the force-cancel fallback for every run older than
`max_age_hours`.

Ages are compared with a one-second precision, so a run queued for 24 hours and 30 minutes is
already eligible for cancellation.

This design helps handle edge cases where runs have been stuck in the queue for extended periods.

---

## 🔧 Troubleshooting

### Action fails with "gh: command not found"

**Solution**: This should not happen on GitHub-hosted runners. If you're using a self-hosted runner,
ensure the GitHub CLI is installed.
See [GitHub CLI installation](https://cli.github.com/manual/installation).

### Cancellation returns status code 500

**Cause**: Very old workflow runs (several months old) may fail to cancel due to GitHub API
limitations.

**Solution**: These runs may need to be manually deleted. See [dev/README.md](dev/README.md) for
notes on handling stale runs.

### Log shows `::warning::gh api (cancel) failed ...` or `No HTTP response`

**Cause**: The `gh api` call failed, and the error message of `gh` is forwarded as a warning
annotation. Typical reasons are an invalid or expired token (`HTTP 401`), a missing permission
(`HTTP 403`), a run that no longer exists (`HTTP 404`), or a network error.

**Solution**: Read the message after the colon, it is the error reported by `gh`.

### Log shows `::error::Cannot list the workflow runs of ...`

**Cause**: The call that lists the runs failed, for example because of an invalid token, a missing
permission, a wrong `repo` or `workflow`, a network error or a GitHub outage. The error reported by
`gh` is printed just above.

**Solution**: Fix the cause reported by `gh`. No run is cancelled in this case, the step fails, and
the [outputs](#-outputs) are all set to `0` so that the next steps do not read empty values.

### Log shows `::error::Invalid timestamp ...`

**Cause**: A run has a timestamp that is not in the `YYYY-MM-DDTHH:MM:SSZ` format returned by the
GitHub API, so its age cannot be computed.

**Solution**: The run is skipped, counted as a failure, and the other runs are still processed.
Please open an issue with the log line if this happens with the GitHub API.

### Action fails immediately with `::error::REPO must be in owner/name format` or `No GitHub credentials found`

**Cause**: The inputs are validated before any API call. `repo` must look like `owner/name`
(letters, digits, `.`, `_` and `-` only), `max_age_hours` must be a positive integer, and a token
must be available (the `github_token` input, which must not be empty).

**Solution**: Fix the input named in the error message.

### Log shows `::warning::Rate limited on run ... giving up`

**Cause**: GitHub rate limited the cancel requests and the quota did not come back within the
retries (3 retries, at most 60 seconds each).

**Solution**: Nothing to do in most cases: the affected runs are reported as failed and are retried
the next time the action runs. For very large backlogs, use a lower frequency or a token with a
higher rate limit (for example a GitHub App token).

### Permission denied error

**Cause**: Insufficient permissions for the GitHub token.

**Solution**: Ensure your workflow has the required permissions:

```yaml
permissions:
  actions: write
  contents: read
```

### No runs are being cancelled

**Check**:

1. Verify you have queued runs older than `max_age_hours`
2. Check the action logs to see what runs were found
3. Ensure the repository name format is correct (`owner/name`)

---

## ❓ FAQ

### Can this action cancel running workflows?

No, this action only cancels workflow runs that have not started: the **queued** state, and
optionally `waiting`, `pending` and `requested` with the `statuses` input. Running (`in_progress`)
or completed workflows are never affected.

### Will it cancel the workflow that calls this action?

No, the action only processes runs that were queued before it starts executing. The workflow calling
this action is typically in a "running" state, not "queued".

### Can I use this for multiple repositories?

Yes, you can either:

- Set up the action in each repository
- Use a centralized workflow with a matrix strategy to target multiple repositories
- See `dev/run_for_repos.sh` for batch processing examples

### Does this work with private repositories?

Yes, as long as the provided token has the necessary permissions for the target repository.

### What happens if a run is cancelled while transitioning from queued to running?

If a run starts or completes between the moment it is listed and the moment the cancel request is
sent, GitHub rejects the request with HTTP `409` (or `404` if the run is gone). The action logs a
`::warning::` for that run, skips it, and does **not** fail. Any other error (for example `401`,
`403`, `5xx`, or a network error) is a real failure: it is logged, the other runs are still
processed, and the step exits with code `1`.

---

## ⚠️ Limitations

- **Queue Status Only**: Only cancels runs in the `queued` state by default. The `statuses` input
  can add `waiting`, `pending` and `requested`; runs that are `in_progress` or completed are never
  cancelled
- **Single Repository**: Each action invocation targets one repository (use multiple steps or matrix
  strategies for multiple repos)
- **API Rate Limits**: Subject to GitHub API rate limits. A cancel request rejected because of a
  rate limit (HTTP `429`, or `403` with a rate limit header or message) is retried up to 3 times,
  waiting for the delay requested by GitHub (`Retry-After` or `X-RateLimit-Reset`) or, if there is
  none, 5, 10 and 20 seconds. A limit that requires waiting more than 60 seconds is not waited for:
  the run is reported as failed and is retried by the next execution of the action
- **Very Old Runs**: Runs that are extremely old (several months) may fail to cancel via the API
  (see [Troubleshooting](#-troubleshooting))

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For questions or suggestions, you can
submit [GitHub Issues](https://github.com/durandtibo/cancel-queued-runs-action/issues).
We will reply to you as soon as possible. Thank you very much.

---

## 📝 Changelog

The release notes are published on the
[GitHub releases page](https://github.com/durandtibo/cancel-queued-runs-action/releases).

---

## License

`cancel-queued-runs-action` is licensed under BSD 3-Clause "New" or "Revised" license available
in [LICENSE](LICENSE) file.
