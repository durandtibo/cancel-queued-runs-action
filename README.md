# 🧹 Cancel Queued Runs Action

<p align="center">
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml">
        <img alt="CI" src="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml/badge.svg">
    </a>
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly-tests.yaml">
        <img alt="Nightly Tests" src="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly-tests.yaml/badge.svg">
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

- Cancels workflow runs stuck in the **queued** state
- Configurable maximum queue age (in hours)
- Lightweight composite action
- Works with private and public repositories
- Requires only the GitHub-provided `GITHUB_TOKEN`

---

## 📋 Prerequisites

This action requires:

- **GitHub Token**: The action needs `actions:write` permission to cancel workflow runs. The default
  `GITHUB_TOKEN` provided by GitHub Actions has this permission.
- **GitHub CLI**: Pre-installed on all GitHub-hosted runners (ubuntu-latest, macos-latest, etc.)
- **Shell Environment**: Works on both Linux (GNU) and macOS (BSD) runners

---

## 📦 Usage

Add the following job to any workflow where you want stale queued runs to be automatically
cancelled.

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

| Name            | Required | Default | Description                                                                   |
| --------------- | -------- | ------- | ----------------------------------------------------------------------------- |
| `github_token`  | ✅ Yes   | –       | Token with `actions:write` permissions, usually `${{ secrets.GITHUB_TOKEN }}` |
| `repo`          | ✅ Yes   | –       | Repository in `owner/name` format                                             |
| `max_age_hours` | ❌ No    | `24`    | Maximum number of hours a run is allowed to stay queued                       |

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
2. **Calculate Age**: Determines how long each run has been queued (in hours)
3. **Filter**: Identifies runs older than the configured `max_age_hours`
4. **Cancel**: Sends cancellation requests for eligible runs
5. **Report**: Logs the status of each operation

The action uses the GitHub CLI (`gh`) internally to interact with GitHub's Actions API. It includes
cross-platform timestamp parsing to work correctly on both Linux (GNU date) and macOS (BSD date).

### Cancellation Strategy

The action uses a two-tier cancellation approach:

- **Standard Cancel**: For runs between `max_age_hours` and `max_age_hours + 3` hours old
  - Uses the standard `/cancel` endpoint
  - Graceful cancellation for recently queued runs

- **Force Cancel**: For runs older than `max_age_hours + 3` hours
  - Uses the `/force-cancel` endpoint
  - More aggressive approach necessary for very old, stuck runs

**Example**: If `max_age_hours: 24`:

- Runs queued 25-27 hours: Standard cancel
- Runs queued >27 hours: Force cancel

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

No, this action only cancels workflow runs in the **queued** state. Running or completed workflows
are not affected.

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

The GitHub API handles this gracefully. If a run starts executing between the time it's identified
and when the cancel request is sent, the cancellation may fail (with a non-202 status code), but
this won't cause the action to error.

---

## ⚠️ Limitations

- **Queue Status Only**: Only cancels runs in the `queued` state, not `in_progress` or other states
- **Single Repository**: Each action invocation targets one repository (use multiple steps or matrix
  strategies for multiple repos)
- **API Rate Limits**: Subject to GitHub API rate limits (generally not an issue for typical usage)
- **Very Old Runs**: Runs that are extremely old (several months) may fail to cancel via the API
- **Permissions Required**: Needs `actions:write` permission, which may not be available in some
  restricted environments
- **Pagination**: Fetches up to 100 queued runs per page (uses automatic pagination)

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For questions or suggestions, you can
submit [GitHub Issues](https://github.com/durandtibo/cancel-queued-runs-action/issues).
We will reply to you as soon as possible. Thank you very much.

---

## License

`cancel-queued-runs-action` is licensed under BSD 3-Clause "New" or "Revised" license available
in [LICENSE](LICENSE) file.
