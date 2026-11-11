# CLAUDE.md

Guidance for coding agents working in this repository.

## Repository purpose

A GitHub composite action (`action.yaml`) that cancels workflow runs queued longer than
`max_age_hours`. The logic lives in `scripts/cancel.sh` (bash, must work on GNU/Linux and
BSD/macOS) and is tested with [bats](https://github.com/bats-core/bats-core) in `tests/`.
`dev/` holds maintainer helpers (`run_for_repos.sh`), not part of the action.

## Environment

- Use the `Makefile`; run `make help` to list targets.
- Do not edit `.make/`: it is a shared directory synced by `bot-sync-shared-makefile.yaml`.
- Run `make format` and `make lint` before committing. Fix what they report instead of disabling
  rules.
- Run the shell tests with `bats tests/` (install `bats-core` if missing). Some workflows cannot
  be run locally; say so in the PR instead of claiming they pass.

## Git workflow

- One branch and one PR per logical change, branched from an up-to-date `main`. Never commit or
  push to `main`.
- Name branches `<type>/<short-description>` in kebab-case, with type one of: `feat`, `bugfix`,
  `hotfix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`.
- PR descriptions cover what changed, what was deliberately left alone, and any behaviour change.
- On conflicts with `main`, merge `origin/main` into the branch; do not rebase and force-push.
- Update `README.md` when inputs, behaviour, or workflows change.

## Action rules (`action.yaml`)

- Keep input names, defaults, and descriptions consistent with `README.md`. Renaming or removing
  an input is a breaking change and must be flagged.
- Pass inputs to scripts through `env:`, never by interpolating them in `run:`.
- Every `run:` step sets `shell: bash`.
- Pin third-party actions in workflows to commit SHAs with a `# ratchet:<owner>/<repo>@<tag>`
  comment, never to tags or branches.
- Workflows use least-privilege `permissions` and set `timeout-minutes` on jobs.

## Shell script rules (`scripts/cancel.sh`)

- Must stay portable between GNU and BSD tools (`date`, `sed`, etc.).
- Keep logic in small functions so each can be unit tested; the main flow must be skippable when
  the script is sourced by tests.
- Quote all variables; validate inputs early with clear `::error` messages.
- Code must pass `shellcheck` and `shfmt` via `make lint` / `make format`.

## Workflow structure (`.github/workflows/`)

Files are prefixed by role:

- `ci.yaml`: entry point for pull requests, pushes to `main`, a nightly schedule and manual runs. It
  holds no steps, only jobs that call the reusable `ci-*.yaml` workflows below.
  - `ci-format.yaml`: Markdown, shell, YAML and bats-assertion lint/format checks.
  - `ci-shell.yaml`: bats tests on the OS matrix.
  - `ci-shell-bash32.yaml`: bats tests with the system bash 3.2 on macOS.
  - `ci-mutation-check.yaml`: breaks `scripts/cancel.sh` on purpose (`dev/mutants.txt`) and fails if
    the tests do not notice.
  - `ci-action.yaml`: runs the action from this checkout (`uses: ./`), i.e. the version not
    released yet.
- `ci-verify-workflows.yaml`: lints the workflow files themselves. It has its own triggers and is not
  called from `ci.yaml`, so it can be a required check.
- `nightly.yaml`: scheduled entry point that calls `nightly-test-released.yaml`, which
  tests the latest released action. It is not part of `ci.yaml`.
- `lib-get-test-matrix.yaml`: reusable workflow that loads the shared OS matrix once; callers pass it
  down through the `test-matrix` input.
- `bot-*.yaml`: scheduled automation that opens PRs or acts on runs (format files, pin actions, sync
  `.make/`, cancel stale runs, report queued runs).
- `security-*.yaml`: dependency review and OSSF Scorecard.

Conventions:

- Set `permissions` on every job (including jobs that call a reusable workflow). Every workflow
  has `permissions: {}` at the workflow level (it grants nothing), never a grant.
- Each `ci-*` check is a `workflow_call` workflow that also has `workflow_dispatch`, so it can be run
  alone. Add a new check as a new `ci-<name>.yaml` plus a job in `ci.yaml`.
- Put `make` targets in the steps rather than duplicating commands, so local runs and CI match.
- Start each file with a comment saying what it does, and update it when the behaviour changes.

## Tests

- Each function in `scripts/cancel.sh` has its own `tests/<function_name>.bats` file.
- One behaviour per test; mock `gh` and `date` rather than calling the network.
- Cover success, failure, and edge cases (boundary ages, empty results, API errors).
- Every bug fix needs a regression test that fails without the fix.
- If a check fails for a real reason, report it rather than weakening the test.

## Reporting

- State which checks ran (`make lint`, `make format`, `bats tests/`) and which did not.
- Note that CI was not awaited.
- Report failures that already exist on `main` rather than hiding them.
