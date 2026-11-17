# 🧹 Cancel Queued Runs Action

[![CI](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml/badge.svg)](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml)
[![Nightly](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly.yaml/badge.svg)](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly.yaml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/durandtibo/cancel-queued-runs-action/badge)](https://scorecard.dev/viewer/?uri=github.com/durandtibo/cancel-queued-runs-action)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/tag/durandtibo/cancel-queued-runs-action?label=release)](https://github.com/durandtibo/cancel-queued-runs-action/tags)

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
- Optional filters to only cancel the runs of one workflow, one branch or one event
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
- **Shell Environment**: Works on both Linux (GNU) and macOS (BSD) runners. Windows runners are not
  supported and are not tested.

---

## 📦 Usage

Add the following job to any workflow where you want stale queued runs to be automatically
cancelled.

This repository does **not** use floating versions: there is no `v1` or `v1.9` tag that moves to
the latest release, and `main` is not a release. Every release is an immutable, exact version tag
(`v1.9`, ...) that is never moved or re-pointed once published. To upgrade, change the version in
your workflow explicitly. For the best supply-chain safety, pin the action to the commit SHA of a
release (`uses: durandtibo/cancel-queued-runs-action@<sha> # v1.9`).

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
| `max_age_hours`             | ❌ No    | `24`                       | Maximum age of a run in hours, since its last update (see the [FAQ](#-faq))             |
| `force_cancel_buffer_hours` | ❌ No    | `3`                        | Hours after `max_age_hours` from which force-cancel is used as a fallback (`0` allowed) |
| `statuses`                  | ❌ No    | `queued`                   | Run statuses to consider: `queued`, `waiting`, `pending`, `requested` (comma-separated) |
| `workflow`                  | ❌ No    | `""` (all workflows)       | Only cancel the runs of this workflow (file name such as `ci.yaml`, or numeric ID)      |
| `branch`                    | ❌ No    | `""` (all branches)        | Only cancel the runs of this branch (a branch name such as `main`, not a ref)           |
| `event`                     | ❌ No    | `""` (all events)          | Only cancel the runs triggered by this event (`push`, `pull_request`, `schedule`, ...)  |
| `fail_on_error`             | ❌ No    | `true`                     | If `false`, a run that could not be cancelled does not fail the step                    |
| `dry_run`                   | ❌ No    | `false`                    | If `true`, only log the runs that would be cancelled                                    |

> **Note**: `force_cancel_buffer_hours`, `statuses`, `workflow`, `branch`, `event`,
> `fail_on_error`, `dry_run` and all the [outputs](#-outputs) were added after `v1.9`. Use a later
> release (or a commit of `main`) to get them; the examples below that use them need such a
> release.

---

## 📤 Outputs

| Name                | Description                                                                                                                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `eligible_count`    | Number of runs older than `max_age_hours` that match the `statuses` and the filters (in a dry run: the number that would be cancelled)                  |
| `cancelled_count`   | Number of runs for which a cancel request was accepted (always `0` in a dry run)                                                                        |
| `skipped_count`     | Number of runs that were gone or no longer cancellable (HTTP 404 or 409)                                                                                |
| `failed_count`      | Number of runs that could not be cancelled, and of runs left unprocessed because GitHub rate limited the execution                                      |
| `cancelled_run_ids` | JSON array with the IDs of the cancelled runs, in the order they were processed (for example `[101,102]`), `[]` if none and in a dry run (`fromJSON()`) |

`cancelled_count + skipped_count + failed_count = eligible_count`, except in a dry run.

The outputs are written even when some runs failed (the step then fails unless `fail_on_error` is
`false`, so use `if: always()` on a following step to read them), and the action appends the same
counts as a table to the
[job summary](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary).

The job summary is one table (eligible, cancelled, skipped and failed runs), followed by the first
50 cancelled runs as links. The logs of the step list every run.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  id: cancel
  with:
    max_age_hours: 24
- run: echo "Cancelled ${{ steps.cancel.outputs.cancelled_count }} run(s)"
```

`cancelled_run_ids` is a JSON array on a single line: read it with `fromJSON()`, for example to
build a matrix or to look at the runs afterwards. As any value that comes from a step, pass it to a
script through `env:` rather than interpolating it in the `run:` line.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  id: cancel
- if: steps.cancel.outputs.cancelled_count != '0'
  env:
    CANCELLED_RUN_IDS: ${{ steps.cancel.outputs.cancelled_run_ids }}
  run: echo "$CANCELLED_RUN_IDS" | jq -r '.[]'
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
Run 12947114653 is 30h12m old.
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

### Example: only cancel the runs of one branch or one event

`branch` and `event` are filters applied by GitHub, on top of the others (`workflow`, `statuses`).
They only take one value each. `branch` is a branch name such as `main` or `feat/my-feature`, not a
ref (`refs/heads/main` matches nothing), and the match is case sensitive. It is the head branch of the
run: for a run triggered by a pull request, the branch of the pull request, not the branch it
targets. `event` is the name of the event that triggered the run, for example `push`,
`pull_request`, `schedule` or `workflow_dispatch`.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  with:
    max_age_hours: 6
    event: pull_request
```

To keep the runs of the default branch and clean up the others, run the action once per case
(a step cannot exclude a branch).

### Example: do not fail the job when a run cannot be cancelled

By default the step fails when a run could not be cancelled, for example after a rate limit or a
server error. For a cleanup that runs often and is retried by the next execution, set
`fail_on_error: false` to only log a warning. The failures are still counted in the
`failed_count` output. Invalid inputs and a failure to list the runs always fail the step.

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.9
  id: cancel
  with:
    max_age_hours: 24
    fail_on_error: false
- run: echo "Failed to cancel ${{ steps.cancel.outputs.failed_count }} run(s)"
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

1. **Validate**: Every input is checked before the first API call
2. **Cutoff**: Computes the instant `max_age_hours` ago, once, so that all the runs are compared
   with the same instant
3. **List**: Asks GitHub for the runs of each of the `statuses` (`queued` by default), restricted to
   the `workflow`, `branch` and `event` when they are set, and created before the cutoff. A run
   listed under two statuses, because its status changed between the two calls, is only
   considered once
4. **Select**: Keeps the runs whose last update (`updated_at`) is strictly older than the cutoff,
   oldest first. The age is measured from `updated_at`, which moves forward when a run is re-run,
   for example after a failure, so such a run is not cancelled
5. **Cancel**: Sends a cancellation request for each selected run, oldest first, with one second
   between two requests (or only logs them with `dry_run: true`)
6. **Report**: Sets the outputs, writes the summary, and fails if a run could not be cancelled
   (unless `fail_on_error` is `false`)

The action uses the GitHub CLI (`gh`) and `jq`, which are on the GitHub-hosted runners. Dates are
handled by `jq`, so it behaves the same on Linux and macOS.

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
    (anything other than HTTP `202`) and does not report that the run is gone (`HTTP 404`) or not
    cancellable (`HTTP 409`): such a run is skipped without a second request
  - More aggressive approach necessary for very old, stuck runs

**Example**: If `max_age_hours: 24` and `force_cancel_buffer_hours: 3` (the default):

- Runs queued more than 24 hours and up to 27 hours: Standard cancel
- Runs queued more than 27 hours: Standard cancel first, then force cancel if it was not accepted

Set `force_cancel_buffer_hours: 0` to allow the force-cancel fallback for every run older than
`max_age_hours`.

Ages are compared with a one-second precision, so a run queued for 24 hours and 30 minutes is
already eligible for cancellation. A run is cancelled only when it is strictly older than
`max_age_hours`.

This design helps handle edge cases where runs have been stuck in the queue for extended periods.

---

## 🔧 Troubleshooting

### Action fails with "Required command(s) not found" or "gh: command not found"

**Solution**: This should not happen on GitHub-hosted runners. If you're using a self-hosted runner,
ensure the GitHub CLI is installed.
See [GitHub CLI installation](https://cli.github.com/manual/installation).

The action checks for `gh` and `jq` before doing anything else and fails with
`::error::Required command(s) not found: ...`, listing every missing command at once.

### Cancellation returns status code 500

**Cause**: Very old workflow runs (several months old) may fail to cancel due to GitHub API
limitations.

**Solution**: These runs may need to be manually deleted, see the next entry. The action sends
`/force-cancel` once for a run older than `max_age_hours + force_cancel_buffer_hours` when `/cancel`
fails with an unexpected error.

### A run stays queued and is skipped at every execution (HTTP 409)

**Cause**: Some runs stay `queued` for months with no job at all (for example after a GitHub
incident). GitHub cancels a run by cancelling its jobs, so a run without jobs can never be
cancelled and `/cancel` answers `409`. The action skips it and counts it in `skipped_count`.

**Solution**: The action does not delete runs. Delete such a run by hand, after checking that it
has no job: `gh api -X DELETE /repos/OWNER/REPO/actions/runs/RUN_ID` (the run and its history are
lost; GitHub may refuse with `403`, and only GitHub Support can then remove it).

### A run could not be cancelled (`failed_count`)

**Cause**: The `gh api` call failed, and the message of `gh` is printed in the log. Typical reasons
are an invalid or expired token (`HTTP 401`), a missing permission (`HTTP 403`), a server error
(`HTTP 5xx`) or a network error.

**Solution**: Read the message in the log, it is the error reported by `gh`. A run that no longer
exists (`HTTP 404`) or that cannot be cancelled anymore (`HTTP 409`) is not a failure: it is skipped
with a warning and counted in `skipped_count`.

### Log shows `::error::Cannot list the workflow runs of ...`

**Cause**: The call that lists the runs failed, for example because of an invalid token, a missing
permission, a wrong `repo` or `workflow`, a network error or a GitHub outage. The error reported by
`gh` is printed just above.

**Solution**: Fix the cause reported by `gh`. No run is cancelled in this case, the step fails
(whatever `fail_on_error` is), and the [outputs](#-outputs) are all set to `0` so that the next steps
do not read empty values. The listing is not retried: the next scheduled execution is the retry.

### Action fails immediately with a `REPO` or a `No GitHub credentials found` error

**Cause**: The inputs are validated before any API call. `repo` must look like `owner/name`
(letters, digits, `.`, `_` and `-` only), `max_age_hours` must be a positive integer, and a token
must be available (the `github_token` input, which must not be empty).

**Solution**: Fix the input named in the error message.

### Log shows `::warning::GitHub lists at most 1000 runs per status`

**Cause**: GitHub does not return more than 1000 runs for a status. The action only asks for the
runs created before the cutoff, so the 1000 are candidates, but older ones may be missing.

**Solution**: Nothing to do: the runs that are cancelled leave the queue, so the next execution
lists the following ones. For a very large backlog, run the action more often.

### Log shows `::warning::GitHub rate limited the requests`

**Cause**: GitHub rate limited the cancel requests (HTTP `429`, or `403` with a rate limit message).
The action stops: the run and the ones after it are counted in `failed_count`.

**Solution**: Nothing to do in most cases: the next execution cancels them. For very large
backlogs, use a lower frequency or a token with a higher rate limit (for example a GitHub App
token).

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

1. Verify you have runs with the considered `statuses` older than `max_age_hours`
2. Check `eligible_count` and the logs of the step to see what runs were selected
3. Ensure the repository name format is correct (`owner/name`)

---

## ❓ FAQ

### Can this action cancel running workflows?

No, this action only cancels workflow runs that have not started: the **queued** state, and
optionally `waiting`, `pending` and `requested` with the `statuses` input. Running (`in_progress`)
or completed workflows are never affected.

### How is the age of a run computed?

The age is the time elapsed since the `updated_at` timestamp of the run, not since its creation.
GitHub moves `updated_at` forward when the run is updated, for example when it is re-run after a
failure. A run that was created three days ago but re-run an hour ago is therefore one hour old and
is not cancelled with `max_age_hours: 24`. This is deliberate: the action must not cancel a run
that was queued again only because its first attempt is old. It applies to every status considered
(`queued`, `waiting`, `pending` and `requested`). The age is shown in the logs
(`Run 12947114653 (age 108720s): cancelled`).

### Will it cancel the workflow that calls this action?

No, the action only processes runs that were queued before it starts executing. The workflow calling
this action is typically in a "running" state, not "queued".

### Can I use this for multiple repositories?

Yes, you can either:

- Set up the action in each repository
- Use a centralized workflow with a matrix strategy to target multiple repositories
- Run `dev/run_for_repos.sh -u <username>` to process all the public, non-archived repositories
  of a user (sorted by name); a summary table with the runs found and cancelled per repository
  and in total is printed at the end

### Does this work with private repositories?

Yes, as long as the provided token has the necessary permissions for the target repository.

### What happens if a run is cancelled while transitioning from queued to running?

If a run starts or completes between the moment it is listed and the moment the cancel request is
sent, GitHub rejects the request with HTTP `409` (or `404` if the run is gone). The action logs a
`::warning::` for that run, skips it, and does **not** fail. Any other error (for example `401`,
`403`, `5xx`, or a network error) is a real failure: it is logged, the other runs are still
processed, and the step exits with code `1` (unless `fail_on_error` is `false`).

---

## 🚧 Limitations

- **Queue Status Only**: Only cancels runs in the `queued` state by default. The `statuses` input
  can add `waiting`, `pending` and `requested`; runs that are `in_progress` or completed are never
  cancelled
- **Single Repository**: Each action invocation targets one repository (use multiple steps or matrix
  strategies for multiple repos)
- **API Rate Limits**: Subject to GitHub API rate limits. Nothing is retried: a transient error
  while listing the runs fails the step, and a rate limit while cancelling stops the execution (the
  runs left are counted in `failed_count`). The next execution continues. One second separates two
  cancel requests
- **At most 1000 runs per status**: GitHub returns at most 1000 runs for a query that filters on the
  status. If more runs are queued, the action warns and cancels the ones it was given; the others
  are processed by the next executions of the action, as the cancelled runs leave the queue
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
