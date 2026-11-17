# 🧹 Cancel Queued Runs Action

[![CI](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml/badge.svg)](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml)
[![Nightly](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly.yaml/badge.svg)](https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly.yaml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/durandtibo/cancel-queued-runs-action/badge)](https://scorecard.dev/viewer/?uri=github.com/durandtibo/cancel-queued-runs-action)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/tag/durandtibo/cancel-queued-runs-action?label=release)](https://github.com/durandtibo/cancel-queued-runs-action/tags)

Cancel the GitHub Actions workflow runs of **one repository** that have not started (`queued` by
default) for longer than a number of hours. It never touches a run in progress or a run that is
younger than the limit.

```yaml
jobs:
  cancel-stale-runs:
    runs-on: ubuntu-latest
    permissions:
      actions: write
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v3.0.0
        with:
          max-age-hours: 24
```

Releases are immutable exact version tags (`v3.0.0`, ...): there is no floating tag, so upgrade by
changing the version. For the best supply-chain safety, pin the commit SHA of a release.
The job needs `actions: write` (it includes read). `gh` and `jq` are used and are on the
GitHub-hosted runners (Linux and macOS; Windows is not supported).

## 🛠 Inputs

| Input                       | Default                    | Description                                                                                                                                                            |
| --------------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `github-token`              | `${{ github.token }}`      | Token with actions:write permission on the target repository                                                                                                           |
| `repo`                      | `${{ github.repository }}` | Target repository, owner/name                                                                                                                                          |
| `max-age-hours`             | `24`                       | Runs older than this many hours are cancelled (positive integer). The age is measured from the last update of the run, so a re-run restarts it                         |
| `statuses`                  | `queued`                   | Comma-separated run statuses to consider, among queued, waiting, pending and requested                                                                                 |
| `workflow`                  | `""`                       | Only the runs of this workflow: a file name (ci.yaml) or a numeric ID                                                                                                  |
| `branch`                    | `""`                       | Only the runs of this head branch, given by name (case sensitive)                                                                                                      |
| `event`                     | `""`                       | Only the runs triggered by this event (push, schedule, ...)                                                                                                            |
| `force-cancel-buffer-hours` | `3`                        | Hours after max-age-hours from which /force-cancel is tried when /cancel is refused with an unexpected error (non-negative integer, 0 means right after max-age-hours) |
| `fail-on-error`             | `true`                     | "true" or "false". If "false", a run that could not be cancelled is a warning, not a failure                                                                           |
| `dry-run`                   | `false`                    | "true" or "false". If "true", log the runs that would be cancelled and cancel nothing                                                                                  |

Booleans accept exactly `true` and `false`; anything else fails the step. Every input is validated
before the first API call.

## 📤 Outputs

| Output              | Description                                                                       |
| ------------------- | --------------------------------------------------------------------------------- |
| `eligible-count`    | Number of runs older than max-age-hours (in a dry run: that would be cancelled)   |
| `cancelled-count`   | Number of runs for which a cancel request was accepted (0 in a dry run)           |
| `skipped-count`     | Number of runs that were gone or not cancellable anymore (HTTP 404 or 409)        |
| `failed-count`      | Number of runs that could not be cancelled, or were left when GitHub rate limited |
| `cancelled-run-ids` | JSON array of the cancelled run IDs, "[]" if none. Read it with fromJSON()        |

`cancelled-count + skipped-count + failed-count = eligible-count`, except in a dry run. All the
outputs are set on every path, including a failure, so a step with `continue-on-error` can read
them. The action also writes a summary table with the first 50 cancelled runs.

## ⏱ Examples

Preview what would be cancelled (use it the first time):

```yaml
- uses: durandtibo/cancel-queued-runs-action@v3.0.0
  with:
    dry-run: true
```

Only the runs of one workflow, on one branch, triggered by one event:

```yaml
- uses: durandtibo/cancel-queued-runs-action@v3.0.0
  with:
    max-age-hours: 12
    workflow: ci.yaml
    branch: main
    event: push
```

Every hour, and also the runs that wait for an approval or a concurrency slot:

```yaml
on:
  schedule:
    - cron: "0 * * * *"
jobs:
  cleanup:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      actions: write
    steps:
      - id: cancel
        uses: durandtibo/cancel-queued-runs-action@v3.0.0
        with:
          statuses: queued,waiting
      - run: echo "Cancelled ${{ steps.cancel.outputs.cancelled-count }} run(s)"
```

Several repositories: see [examples/multi-repo-cleanup.yaml](examples/multi-repo-cleanup.yaml). More
in [examples/](examples/).

## 🧩 How It Works

1. **Validate** every input, then `gh`, `jq` and the token.
2. **Cutoff**: compute the instant `max-age-hours` ago, once, so every run is compared with the
   same instant.
3. **List** the runs of each status (and `workflow`, `branch`, `event` when set) created before the
   cutoff, one paginated request per status.
4. **Select** the runs whose last update (`updated_at`) is strictly older than the cutoff, oldest
   first. This is the only rule. The age is measured from `updated_at`, so a run that was created
   long ago but re-run recently (for example after a failure) is **not** cancelled.
5. **Cancel** each run with `POST /actions/runs/{id}/cancel`, one second apart (nothing is sent in a
   dry run). If `/cancel` fails with an unexpected error and the run is older than
   `max-age-hours + force-cancel-buffer-hours`, `/force-cancel` is sent once.
6. **Report**: set the outputs, write the summary, and fail if a run could not be cancelled (unless
   `fail-on-error` is `false`).

A run that is gone or finished between the listing and the request (HTTP 404 or 409) is skipped with
a warning, not a failure. Running the action twice gives the same end state.

## 🚧 Limitations

- Runs that have not started only (`queued`, and optionally `waiting`, `pending`, `requested`), in
  one repository.
- GitHub lists at most 1000 runs per status and per execution. The oldest are asked for first and
  the cancelled runs leave the queue, so the next execution continues (the action warns).
- A run that GitHub refuses to cancel stays in the queue and shows up in `skipped-count`. A run
  with no job (HTTP 409 at every execution) can only be removed by deleting it, which the action
  does not do:
  `gh api -X DELETE /repos/OWNER/REPO/actions/runs/RUN_ID` (the run and its history are lost).
- Nothing is retried. A rate limit stops the execution and the runs left are counted in
  `failed-count`; a failure to list the runs fails the step. The next scheduled execution continues.
  Set `timeout-minutes` for a big backlog: one second is waited per cancelled run.

## 🔄 Migrating from v2

| v2                                                               | v3                                                                    |
| ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| Inputs in `snake_case` (`max_age_hours`, `dry_run`, ...)         | Rename the keys to `kebab-case` (`max-age-hours`, `dry-run`, ...)     |
| `delete_stuck_runs`                                              | Removed. Delete a zombie run by hand with the `gh api` command above  |
| `max_runs`                                                       | Removed. Use `concurrency: { group: ..., cancel-in-progress: true }`  |
| `max_cancellations` and the `deferred_count` output              | Removed. Use `dry-run` first; the schedule bounds the work of one run |
| `cancel_delay_seconds`                                           | Removed. A fixed pause of one second separates two requests           |
| Outputs `found_count`, `would_cancel_count`, `listing_truncated` | Removed. Read `eligible-count` for the old `would_cancel_count`       |
| Outputs `*_count` and `cancelled_run_ids`                        | Renamed to `*-count` and `cancelled-run-ids`                          |
| Retries on rate limits and on listing errors                     | None: the next execution is the retry                                 |
| `scripts/cancel.sh` called directly, `dev/run_for_repos.sh`      | Use the action; for several repositories, the matrix example          |

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Release notes are on the
[GitHub releases page](https://github.com/durandtibo/cancel-queued-runs-action/releases).

## License

`cancel-queued-runs-action` is licensed under BSD 3-Clause "New" or "Revised" license available
in [LICENSE](LICENSE) file.
