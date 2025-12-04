# 🧹 Cancel Queued Runs Action

<p align="center">
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/actions/ci.yaml">
        <img alt="CI" src="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/ci.yaml/badge.svg">
    </a>
    <a href="https://github.com/durandtibo/cancel-queued-runs-action/actions/nightly-tests.yaml">
        <img alt="Nightly Tests" src="https://github.com/durandtibo/cancel-queued-runs-action/actions/workflows/nightly-tests.yaml/badge.svg">
    </a>
</p>

Automatically cancel GitHub Actions workflow runs that have been **queued longer than a configurable
number of hours**. This helps keep your repository’s workflow queue clean and prevents long-running
backlogs.

---

## 🚀 Features

- Cancels workflow runs stuck in the **queued** state
- Configurable maximum queue age (in hours)
- Lightweight composite action
- Works with private and public repositories
- Requires only the GitHub-provided `GITHUB_TOKEN`

---

## 📦 Usage

Add the following job to any workflow where you want stale queued runs to be automatically
cancelled.

```yaml
jobs:
  cancel-stale-runs:
    runs-on: ubuntu-latest
    steps:
      - uses: durandtibo/cancel-queued-runs-action@v1.0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 24
```

---

## 🛠 Inputs

| Name            | Required | Default | Description                                                                   |
|-----------------|----------|---------|-------------------------------------------------------------------------------|
| `github_token`  | ✅ Yes    | –       | Token with `actions:write` permissions, usually `${{ secrets.GITHUB_TOKEN }}` |
| `repo`          | ✅ Yes    | –       | Repository in `owner/name` format                                             |
| `max_age_hours` | ❌ No     | `24`    | Maximum number of hours a run is allowed to stay queued                       |

---

## ⏱ Examples

### Example: cancel queued runs older than 6 hours

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.0
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
      - uses: your-org/cancel-queued-runs-action@v1.0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repo: ${{ github.repository }}
          max_age_hours: 12
```

---

## 🧩 How It Works

- Lists all workflow runs for the target repository
- Filters to only runs with status queued
- Determines how long each run has been queued
- Cancels any run older than max_age_hours

The GitHub CLI (gh) is used internally to interact with GitHub’s Actions API.

---

## Suggestions and Communication

Everyone is welcome to contribute to the community.
If you have any questions or suggestions, you can
submit [Github Issues](https://github.com/durandtibo/cancel-queued-runs-action/issues).
We will reply to you as soon as possible. Thank you very much.

## License

`cancel-queued-runs-action` is licensed under BSD 3-Clause "New" or "Revised" license available
in [LICENSE](LICENSE) file.