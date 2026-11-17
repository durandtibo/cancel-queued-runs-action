# cancel-queued-runs-action: target state

Review date: 2026-11-17, on `main` at `2f8ced2` (the v3 rewrite of #198 to #203 is merged, `v3.0.0`
is not released). This file replaces the previous target state, which is implemented (it stays in
the git history). The testing rules come from `review/testing.md` (T1 to T16).

What was read: `action.yaml`, `scripts/cancel.sh`, `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`,
`.gitattributes`, `examples/`, `dev/*.sh`, `dev/mutants.txt`, `tests/helpers/*`,
`tests/action_cases.json`, the heads of `characterization.bats`, `validate.bats` and
`action_readme_sync.bats`, and the workflows `ci*.yaml`, `nightly.yaml`, `lib-get-test-matrix.yaml`,
`bot-cancel-stale-queued-runs.yaml`, `bot-report-queued-runs.yaml`. Not read in full: the other
bats files, `security-*`, `bot-format-files`, `bot-pin-action`, `bot-sync-shared-makefile`, `.make/`
(shared, out of scope).

What was run: `bats --recursive tests` (188 tests, 0 failures), `make lint-shell`, `lint-markdown`,
`lint-yaml`, `check-format-shell`, `lint-bats`, `check-export` (all pass), two experiments on the
script (findings 1 and 7), one read-only `gh api` listing of this repository (finding 3), and the
GitHub REST documentation page of the workflow-run endpoints. Not run: the CI workflows, anything
that writes to GitHub, `make mutation-check`, `make format`.

## 1. Properties of the action

The target state keeps these properties. Every finding and every choice below is judged against
them. P1 to P9 are about the action; P10 to P12 are about how it is built and shipped.

| #   | Property                | Statement                                                                                                                                                                                                                                                                            |
| --- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| P1  | Single purpose          | Cancel the runs of **one repository** that have not started (`queued` by default) for longer than `max-age-hours`. It does not delete runs, keep the N most recent, or loop over repositories.                                                                                       |
| P2  | Never cancels too much  | A run is cancelled only if its status is listed by the caller, it matches the filters, and its `updated_at` is strictly older than the cutoff. A run in progress or completed is never listed. `dry-run` sends no request that writes. One rule decides: `updated_at < cutoff`.      |
| P3  | Idempotent, convergent  | Running it twice, or two executions at once, gives the same end state. A run that is gone or finished (HTTP 404 or 409) is skipped, not a failure. What one execution does not do (rate limit, 1000-run cap, listing error) the next one does. Nothing is retried inside the action. |
| P4  | Exact contract          | Every input is validated before the first API call, with one `::error::`. Every output is set on every path, has a documented format, and is the same for the local and the released action. Inputs and outputs are `kebab-case`.                                                    |
| P5  | Injection-safe          | Inputs reach the script through `env:` only. Values in an API path match a strict pattern. Values in a query are sent as `gh api -f` fields. Nothing that comes from the API is printed as a workflow command.                                                                       |
| P6  | Fails loudly, by choice | A caller mistake, a missing tool or credential, and a failure to list the runs always fail. A failure to cancel a run fails by default, and is a warning only with `fail-on-error: false`.                                                                                           |
| P7  | Portable and light      | GNU/Linux and BSD/macOS, bash 3.2 included. Only `bash`, `gh` and `jq`, which are on the GitHub-hosted runners. No `date` arithmetic. Windows is not supported.                                                                                                                      |
| P8  | Small and fast          | One script, at most 250 lines and 12 functions. Filters run on the server, selection in one `jq` call. One paginated listing per status, one request per run. Requests that write are sequential, one second apart (GitHub's rule), so the cost of a backlog is one second per run.  |
| P9  | Maintainable            | Each behaviour has one place: one function, one test, one sentence in the README. No knob that cannot be explained in one sentence. Tests pin behaviour (requests sent, outputs, exit code), not the text of the script.                                                             |
| P10 | Tested at three levels  | Level 1: the script with a fake `gh`. Level 2: the local action (`uses: ./`). Level 3: the released action, nightly, same cases. No test has a side effect on a repository. What CI cannot test is written down with the check that covers it.                                       |
| P11 | Shipped equals needed   | A release contains `action.yaml`, `LICENSE` and `scripts/cancel.sh`, and nothing else. CI checks it.                                                                                                                                                                                 |
| P12 | Immutable, documented   | Releases are exact version tags, no floating tag. The README describes the current behaviour only; history is in the release notes.                                                                                                                                                  |

Non-goals: Windows, several repositories in one call (a matrix, see `examples/`), deleting runs,
pruning by count (`concurrency` does it at creation time), retries and rate-limit tuning.

## 2. State today

| Item                | Value                                                                                |
| ------------------- | ------------------------------------------------------------------------------------ |
| `scripts/cancel.sh` | 245 lines, 11 functions                                                              |
| `action.yaml`       | 10 inputs, 5 outputs, one composite step                                             |
| `README.md`         | 161 lines                                                                            |
| Tests               | 188 bats tests in 14 files, 1881 lines with helpers; 21 mutations; all pass          |
| `dev/`              | 4 scripts and `mutants.txt`, 318 lines of shell, 3 bats files that test them         |
| CI                  | 8 `ci-*`, `nightly`, `lib-*`, 5 `bot-*`, 2 `security-*` workflows                    |
| Released versions   | latest is `v2.0.0` (old names). `v3.0.0` is documented everywhere and does not exist |

The v3 design is sound and matches P1 to P9: one rule, server-side `created` filter, `jq` dates,
one `require` table, five outputs, no retry layers. **The target state does not redesign it.** It
closes the gaps between what the repository claims and what it does or tests, then releases.

## 3. Findings

Ordered by impact. "Verified" means I ran it; "read" means I read the code or the documentation.

### Correctness

- **1. A missing `jq` or `gh` does not stop the script (verified).** `validate_all` runs
  `command -v "$cmd" || die ...` and `main` calls it as `validate_all || return 1`. Bash ignores
  `set -e` inside a function called in an `||` list, so `die` (which only returns 1) does not
  end the loop. With `gh` present and `jq` absent, the output is
  `::error::Required command not found: jq`, then `cancel.sh: line 222: jq: command not found`,
  exit **127**, and no output is written. This breaks P4 (outputs on every path) and P6 (the
  message is clear, the exit code is not). Test 186 does not see it: it calls `validate_all`
  directly, where `set -e` is active, and with `gh` missing.
- **2. `max-age-hours` has no upper bound (verified).** `99999999` passes validation and the cutoff
  becomes `-9382-12-08T04:51:43Z`, which GitHub's `created` filter will not accept: the user gets
  "Cannot list the workflow runs" instead of "max-age-hours is not valid". Past 10^19 `jq` itself
  fails. A bound of 87600 (ten years) says what is meant and the `huge-age` case already uses it.
- **3. The README says the oldest runs are listed first, and they are not (verified).** A read-only
  listing of this repository returned runs newest first by `created_at`. The documentation does not
  state an order. With more than 1000 stale runs for a status, the cap keeps the **newest** of the
  stale ones, and `select_stale` then sorts only those. The action still converges (the cancelled
  runs leave the queue), but the sentence "the oldest are asked for first" in Limitations is false,
  and "oldest first" in `select_stale` is the order of one batch, not of the backlog.
- **4. The force-cancel tier is triggered by the wrong signal (read).** The REST documentation says
  `/force-cancel` is for "a workflow run [that] is not responding to" `/cancel`. The script sends
  it only when `/cancel` itself returns an unexpected error (not 202, 404, 409, 429) on a run older
  than `max-age-hours + force-cancel-buffer-hours`. A run that does not respond to `/cancel` is one
  where `/cancel` answered **202 and the run is still queued the next hour**. That run is cancelled
  again by the next execution (it is still stale), and again with the same result, forever, with
  `cancelled-count: 1` each time. The tier never helps that run. The previous review decided to keep
  the tier (D1 then); this finding is about when it fires, not whether it exists. See section 5.3.
  The documentation also does not explain the 409 on `/force-cancel`: the earlier claim that GitHub
  "rejects it unless a regular cancel was sent first" is not in the documentation and was never
  tested.
- **5. The `(HTTP nnn)` suffix of `gh` is the only way the script reads a cancel error (read).**
  The fake `gh` writes it, so the tests can only confirm that the script agrees with the fake. No
  check shows that the real `gh` writes it for a `POST`. If `gh` changes, every failure becomes
  `failed` (the safe side), and a 404 or 409 that should be skipped fails the step. The listing path
  is covered by the real dry-run jobs; the cancel path is not.

### Tests and CI

- **6. Level 2 and 3 cannot assert the effect of any input (P10, T5, T16, CLAUDE.md).** CLAUDE.md
  says every input needs a case "that sets it and asserts its effect". With dry runs on a repository
  whose queue is normally empty, the cases `workflow-filter`, `branch-event-filter` and
  `all-statuses` only assert "success", and a filter that is silently dropped gives the same
  result: `eligible-count: 0`. The wiring of `max-age-hours`, `statuses`, `workflow`, `branch`,
  `event`, `force-cancel-buffer-hours` and `fail-on-error` is untested end to end, and a real cancel
  (the main path, with outputs `cancelled-count` and `cancelled-run-ids` above 0) is never run.
  Only the mocks of level 1 see it. A rename in `action.yaml`'s `env:` block, for example
  `STATUSES: ${{ inputs.status }}`, would pass level 2.
- **7. Level 3 is nearly empty until `v3.0.0` exists.** `nightly.yaml` runs the pinned `v2.0.0`
  with the old names, and every row of `tests/action_cases.json` has `"released": false`. Only one
  dry run per OS runs against the released action, through snake_case aliases in `ci-action.yaml`.
  The nightly check currently protects nothing about the v3 contract.
- **8. The jobs have more permissions than they use (T15).** `test` and `test-cases` in
  `ci-action.yaml` and the caller job in `ci.yaml` and `nightly.yaml` have `actions: write`. A dry
  run needs `actions: read`, a validation failure needs none.
  `bot-cancel-stale-queued-runs.yaml` has `contents: read` and no checkout. The examples set
  `contents: read` at the workflow level for the same reason, while the README says `actions: write`
  is enough. Users copy examples.
- **9. `characterization.bats` is a scaffold that outlived its job.** It was written to pin five
  rules during the rewrite (its own header says so, and refers to the previous target state). Its
  tests overlap `select_stale.bats`, `cancel_run.bats` and `main.bats`, and it still uses the
  names `fail_on_error`, `max_age_hours` and the removed `MAX_RETRIES` (line 175). 255 lines.
- **10. The mutation check has no mutation for findings 1 and 2 (read).** It is otherwise fine (T12):
  21 mutations, each anchored on a short token. Whenever a finding is fixed, its mutation is added.

### Documentation and housekeeping

- **11. `main` documents a release that does not exist.** README, `examples/` and
  `ci-action.yaml` comments say `@v3.0.0`. A user who copies the README gets "unable to resolve
  action". The README also holds a "Migrating from v2" table, which P12 and T14 put in the release
  notes, and which will be wrong for ever once `v4` exists.
- **12. `CONTRIBUTING.md` points to files that do not exist or are outside the repository:**
  `[CHANGELOG.md](../CHANGELOG.md)` and `[examples/](../examples/)` (a file in the root cannot use
  `../`), and "Update CHANGELOG" when releases carry the history.
- **13. `bot-cancel-stale-queued-runs.yaml` runs `v1.9` with `max_runs`** (a removed input) and
  its header documents `max_runs`. It is the only real cancel of the repository (the CI never
  cancels, correctly), so it is also the only production test of the real cancel path, and it tests
  an old version.
- **14. `bot-report-queued-runs.yaml` is not about this action.** It reports the queued runs of
  every public repository of the user, through a GitHub App. It is useful, and it shares nothing
  with the action, which P1 limits to one repository. It is a maintenance item of an unrelated
  concern in a repository whose `bot-*` files are otherwise about the repository itself.
- **15. A stash from before the rewrite remains** (`git stash list`: "wip: shorter job summary").
  It is superseded by #201, as noted in the notes of that work.

### Not findings (checked, correct)

`.gitattributes` and `dev/check_export.sh` agree (the export is `LICENSE`, `action.yaml`,
`scripts/cancel.sh`). The `created=<cutoff` filter never drops a stale run (`updated_at >=
created_at`). Booleans, statuses, repo and workflow are validated before the first call. Inputs
go through `env:`. All workflows have `permissions: {}`, `timeout-minutes` on jobs, pinned SHAs
with `ratchet` comments. Failure cases in `ci-action.yaml` use `continue-on-error` and assert the
outcome after a positive run. `shellcheck`, `shfmt`, `markdownlint`, `yamllint` pass.

## 4. Target contract

**No change to the names, defaults or meaning of the 10 inputs and 5 outputs of `action.yaml`**,
except two additions to the validation (finding 2, and the force-cancel decision of section 5.3,
which is a behaviour change with no change of name). Rationale: `v3.0.0` has never been released.
The contract is right, and a second round of renames before the first release has a cost (the
README, the tests, the cases, the examples) and no benefit.

Considered and rejected, so they are not proposed again:

| Idea                                            | Why not                                                                                                                                         |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Remove `fail-on-error`, use `continue-on-error` | `continue-on-error` also hides an invalid input and a failure to list, which P6 says must fail. The input costs one condition.                  |
| Remove `branch` and `event`                     | They are server-side filters, cost two lines, and are how a caller targets `schedule` runs.                                                     |
| Add `max-cancellations` or a time budget        | Removed in v3 on purpose. The schedule bounds the work, and `timeout-minutes` is the caller's guard.                                            |
| Cancel in parallel                              | GitHub asks for sequential writes one second apart. Parallelism would trade speed for secondary rate limits.                                    |
| Add an output with the eligible ids             | A sixth output for the preview case. The log and the summary (finding in 5.2) carry it; a caller who needs it uses the `gh` command in the log. |
| Skip the pause after a 404 or 409               | A rejected request is still a request that writes. One rule (always one second) is simpler.                                                     |

Validation changes:

| Input           | Rule today       | Rule in the target                                   |
| --------------- | ---------------- | ---------------------------------------------------- |
| `max-age-hours` | positive integer | positive integer, at most `87600`; the error says so |

## 5. Target `scripts/cancel.sh`

Budget unchanged: at most 250 lines, 12 functions. The five changes below cost about 15 lines, paid
for by the end of `characterization`-style comments and by shortening the header.

### 5.1 Fix the tool check (finding 1)

```bash
for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { die "Required command not found: $cmd"; return 1; }
done
```

Regression test, at the level where the bug lives: **run the script as a process**
(`run env PATH=<only gh> "$SCRIPT"`), not `validate_all` from a sourced shell. Assert exit code 1,
that the output names `jq`, and that `GITHUB_OUTPUT` is untouched or complete (see 5.4). The mutation
is `s/\{ die "Required command[^}]*return 1; \}/die .../`.

A rule for the whole file: every call to a function that can fail is followed by an explicit
return 1 on failure; no function relies on `set -e`, because a caller in an `||` list turns it off.

### 5.2 The summary lists what a dry run would cancel

The first use of the action is a dry run. Today its summary is the four counts, and the runs are in
the step log only. In a dry run the summary lists the eligible runs (first 50, as links); outside a
dry run it lists the cancelled ones, as now. `main` passes `$stale` (the `id age` lines it already
has) to `write_summary` in a dry run and the cancelled ids otherwise. About 6 lines. The outputs
do not change.

### 5.3 Force-cancel on a run that does not respond (finding 4)

Behaviour today: `/cancel`; then `/force-cancel` if `/cancel` failed unexpectedly and the run is
older than `max-age-hours + force-cancel-buffer-hours`.

Target behaviour, same input, same default, same meaning of the buffer in hours: **a run that is
still stale after `max-age-hours + force-cancel-buffer-hours` has already been sent a `/cancel` by
an earlier execution and did not respond. It goes to `/force-cancel` instead of `/cancel`.** In
code, `cancel_run` picks the endpoint from the age, instead of retrying after an error:

```bash
endpoint=cancel
[ "$2" -gt $(((MAX_AGE_HOURS + FORCE_BUFFER_HOURS) * 3600)) ] && endpoint=force-cancel
```

It is shorter than the loop of today (one request, one classification, no `for action in`), and it
matches the documentation. It is a behaviour change, so **it is gated by an experiment**, which I
could not run (it writes):

1. Find a run that stayed `queued` after a `/cancel` that returned 202 (the bot's logs, or
   `gh run list --status queued` older than `max-age-hours + 3` on any of the user's repositories).
2. `POST /force-cancel` on it, once, and keep the status code and the body.
3. If 202 and the run leaves the queue: adopt the behaviour above. If 409 or no effect: the tier
   does nothing in practice either way, and the recommendation becomes to remove it with its input
   (a breaking change to put in `v3.0.0` before it is released).

The previous decision "keep the tier" holds until the experiment is done. Nothing is changed in
this plan before it.

### 5.4 Outputs on every path

`main` writes the outputs on a listing failure but not on a validation failure, and `check_action_case`
encodes it (`"outputs": "unset"`). That is consistent with P4 if the README says it: **a validation
failure sets no output**, because the counts do not exist yet. The README currently says "set on
every path, including a failure". Fix the sentence, not the script.

### 5.5 Smaller

- Header: shorten the 30-line comment to what is not in `action.yaml`, because it is the third copy
  of the input list (the `action.yaml`, the README, the header).
- Check `99999999`-style values (finding 2) in `require`: add a rule `pint87600`, or one more
  argument (`require NAME pint MAX`). Prefer the argument: the `case` stays one table.

## 6. Tests

### 6.1 Level 1: the script with a fake `gh`

Keep `tests/helpers/fake_gh` and the table style. Changes:

- Delete `characterization.bats`, after moving what only it covers (the validation of each input
  by name, `fail-on-error: false` not hiding a listing failure) into `validate.bats` and
  `main.bats`. Before deleting, run `make mutation-check` with and without the file: if no mutation
  needs it, nothing is lost (that is the only criterion, not the test count).
- Add process-level tests for the whole script for the three exit paths a caller sees: invalid input
  (1, no output), missing tool (1, finding 1), listing failure (1, outputs `0`, `[]`).
- Add `max-age-hours=87600` accepted and `87601` rejected.
- Add mutations: the tool check, the upper bound, the dry-run summary lists runs.
- Make the bash version visible in the `test` job of `ci-action.yaml` (`bash --version`), because
  P7 claims bash 3.2 and nobody has checked which bash `shell: bash` selects on the hosted macOS
  image. Not verified here.
- Leave `action_readme_sync.bats` (309 lines) as it is: it implements T14 and CLAUDE.md. If it
  grows again, generate the README tables from `action.yaml` instead of parsing both.

### 6.2 Level 2 and 3: the real action, a fake `gh` on the `PATH`

The composite step calls `gh` from the `PATH`. A job step can put `tests/helpers/fake_gh` first on
the `PATH` (`$GITHUB_PATH`) and set `FAKE_GH_TABLE` and `FAKE_GH_LOG` (`$GITHUB_ENV`). Then the
real `action.yaml` runs, with its real `env:` wiring and a real bash on every OS, and **a real
cancel path with no side effect** (T11). It works the same for `uses: ./` and for the released
action, because both call `gh` from the `PATH`. This closes findings 6 and 7 without a repository
that has stale runs.

Case schema (`tests/action_cases.json`), the row is the test:

```json
{
  "id": "workflow-filter",
  "inputs": { "workflow": "ci.yaml" },
  "fake": [
    "GET|*workflows/ci.yaml/runs*|200|{\"workflow_runs\":[{\"id\":1,\"updated_at\":\"@AGO:30@\"}]}",
    "POST|*runs/1/cancel*|202|{}"
  ],
  "expect": "success",
  "outputs": {
    "eligible-count": "1",
    "cancelled-count": "1",
    "cancelled-run-ids": "[1]"
  },
  "calls": ["*workflows/ci.yaml/runs*", "*POST*runs/1/cancel*"],
  "not-calls": ["*actions/runs?*"],
  "released": false
}
```

Fixture dates are written `@AGO:<hours>@` (for example `@AGO:30@` is 30 hours ago); the step that
installs the fake expands them with `jq` (`now - h*3600 | todate`), so a case never expires.
`dev/check_action_case.sh` gains `calls` and `not-calls` (globs matched
against the fake's log) and exact `outputs`. Cases, one per row, on `ubuntu-latest`:

| Case                  | Inputs                                      | Asserts (outputs, and requests in the log)                                           |
| --------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------ |
| `cancel-old-runs`     | defaults; runs 30 h, 40 h and 1 h old       | `eligible 2`, `cancelled 2`, ids `[a,b]`, one POST per stale run, none for the other |
| `dry-run`             | `dry-run: true`, same fixture               | `eligible 2`, `cancelled 0`, `[]`, **no POST**                                       |
| `max-age-hours`       | `max-age-hours: 48`; runs 30 h and 50 h old | `eligible 1`, only the 50 h run is cancelled                                         |
| `statuses`            | `statuses: queued,waiting`                  | one listing with `status=queued` and one with `status=waiting`                       |
| `workflow`            | `workflow: ci.yaml`                         | path `workflows/ci.yaml/runs`, and not `actions/runs`                                |
| `branch-event`        | `branch: main`, `event: push`               | `branch=main` and `event=push` in the listing                                        |
| `skipped`             | run answers 409 to `/cancel`                | `skipped 1`, `cancelled 0`, step succeeds                                            |
| `failed`              | run answers 500                             | `failed 1`, outcome `failure`                                                        |
| `fail-on-error-false` | same, `fail-on-error: false`                | `failed 1`, outcome `success`                                                        |
| `force-cancel`        | `force-cancel-buffer-hours: 0`, per 5.3     | the endpoint for a run older than the buffer, once                                   |
| `invalid-age`         | `max-age-hours: x`                          | outcome `failure`, outputs unset, **no `gh` call at all**                            |
| `invalid-bool`        | `dry-run: yes`                              | same                                                                                 |
| `invalid-status`      | `statuses: running`                         | same                                                                                 |
| `listing-failure`     | listing answers 500                         | outcome `failure`, outputs `0`, `[]`                                                 |

Each failure row follows a positive row on the same runner (T12), as today.
**Kept as it is: one real dry run on every OS of the matrix** (the `test` job, 13 cells). It is
the only place where the real `gh`, the real `jq` and the real `created` filter meet the real API,
so it covers what the fake cannot. It needs `actions: read`, not `write`. The released action runs
the same job at level 3.

**New: one real contract check, no side effect.** `dev/check_gh_contract.sh`, run once, on
`ubuntu-latest`, calls `gh api --method POST /repos/$GITHUB_REPOSITORY/actions/runs/1/cancel` with
the job's token and asserts that it exits non-zero with `(HTTP 404)` on stderr (finding 5). Run id
`1` does not exist in this repository, so nothing is cancelled. If `gh` changes its error format,
this job fails before a user's run is wrongly counted as failed.

What CI still cannot test: a real cancel of a real run (side effect). It is covered by the fake at
levels 1 to 3, by the contract check above for the error format, and in production by
`bot-cancel-stale-queued-runs.yaml`, which runs the released action every hour on this repository.

Cells per run (T10): 13 (real dry run) + 14 (cases) + 1 (contract) = 28 jobs, 27 of them cheap
(`ubuntu-latest`, seconds). Today: 13 + 11. `max-parallel: 8`, `fail-fast: false`,
`timeout-minutes: 5`.

### 6.3 What does not change

`ci-format`, `ci-shell` (full matrix, because bash and BSD tools differ, P7), `ci-shell-bash32`,
`ci-mutation-check`, `ci-export`, `ci-verify-workflows`, `lib-get-test-matrix`, and the rule that
the pinned release in `ci-action.yaml` is updated by `bot-pin-action.yaml`.

## 7. Repository, workflows and documentation

| Path                                        | Target                                                                                                                                                                                                                       |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `README.md`                                 | Remove "Migrating from v2" (goes to the `v3.0.0` release notes). Fix the "oldest first" sentence (finding 3) and "outputs on every path" (5.4). Document the `87600` bound.                                                  |
| `CONTRIBUTING.md`                           | Remove the CHANGELOG line, fix the `../` links, describe the fake-`gh` cases of `tests/action_cases.json` in 3 lines.                                                                                                        |
| `examples/*.yaml`                           | `permissions: actions: write` only, no `contents: read`.                                                                                                                                                                     |
| `.github/workflows/ci-action.yaml`          | Section 6.2: fake `gh` step, `calls` and `not-calls`, `actions: read` on the real dry run, no `github-token` or `repo` lines that repeat the defaults.                                                                       |
| `.github/workflows/ci.yaml`, `nightly.yaml` | Caller job: `actions: read` (the cases need `contents: read` only).                                                                                                                                                          |
| `bot-cancel-stale-queued-runs.yaml`         | After the release: `v3.0.0` pin, kebab-case names, no `max_runs` input, no `contents: read`, header updated.                                                                                                                 |
| `bot-report-queued-runs.yaml`               | Decision D3. No change in this plan.                                                                                                                                                                                         |
| `dev/`                                      | Add `check_gh_contract.sh` (about 15 lines). `check_action_case.sh` grows by about 25 lines (`calls`, `not-calls`, exact `outputs`).                                                                                         |
| `tests/characterization.bats`               | Deleted, as in 6.1.                                                                                                                                                                                                          |
| `CLAUDE.md`                                 | Add two rules: a function that can fail is followed by an explicit return 1 (never rely on set -e), and the action cases use the fake `gh` (`calls`, `not-calls`). Drop the sentence about the target layout, which is done. |
| `git stash`                                 | Drop `stash@{0}` (finding 15), with the user's go-ahead.                                                                                                                                                                     |

`.gitattributes` and the exported set do not change.

## 8. Migration plan

One branch and one PR per step, each from an up-to-date `main`, in this order. Steps 1 to 4 are
independent of the release and of each other.

1. `bugfix/check-tools-and-age-bound`: findings 1 and 2, with the process-level tests and the
   mutations. Smallest and the only wrong behaviour in the script. Behaviour change: a missing tool
   now exits 1; `max-age-hours` above 87600 is refused.
2. `test/fake-gh-action-cases`: section 6.2 (cases, `check_action_case.sh`, `ci-action.yaml`,
   `check_gh_contract.sh`) and the removal of `characterization.bats`. Behaviour change: none. Every
   row has `"released": false` until step 5.
3. `feat/list-runs-in-dry-run-summary`: 5.2.
4. `docs/fix-readme-and-contributing`: findings 3, 5.4, 11 (the migration table), 12 and the
   examples' permissions. Merge **together with, or after,** the release of step 5 for the
   `v3.0.0` references.
5. **Release `v3.0.0`** (exact tag, release notes with the migration table, no floating tag). Then
   one PR: pin it in `ci-action.yaml` and `bot-cancel-stale-queued-runs.yaml` (the pin bot may open
   it), switch the released steps to kebab-case, set `"released": true` on every row the release
   supports (all of them, if steps 1 and 3 are in the release), delete the snake_case aliases.
6. After the experiment of 5.3: either `feat/force-cancel-unresponsive-runs` (shorter code, same
   input) or `refactor/remove-force-cancel` (removes an input, so a breaking change: do it before
   step 5 if the experiment is done by then).

Per CLAUDE.md, each PR states which checks ran (`make lint` fails on `main` at `lint-makefile`, a
shared `.make/` issue noted in the repository's tooling notes; run the targets one by one), that CI
was not awaited, and which workflows cannot run locally (all of `ci-action.yaml`).

## 9. Decisions and risks

- **D1. The force-cancel experiment (5.3).** Needs the user: it sends one real `POST /force-cancel`
  on one stuck run. Recommended: do it before the release, because the answer may remove an input.
- **D2. Release timing.** `main` already documents `v3.0.0`. Recommended: release as soon as steps
  1 and 2 are merged, so the README is true and level 3 starts to protect the v3 contract (finding
  7). Steps 3 and 4 can follow in `v3.1.0`.
- **D3. `bot-report-queued-runs.yaml`.** Options: keep it here (nothing breaks), or move it to a
  personal `.github` or "ops" repository so this one is about one action. Recommended: move it when
  convenient; it is not part of this plan and has no urgency.
- **R1. The fake `gh` on the `PATH` assumes the composite step uses the `gh` of the `PATH`.** True
  today (`gh api` in the script). The levels 2 and 3 cases would fail loudly, not pass silently,
  if it changed: a case that expects a POST and sees none fails. The real dry-run job still runs
  without the fake.
- **R2. The fake can drift from the real API.** It is the reason for the two real jobs (dry run on
  every OS, 404 contract check). A fake that gets a field wrong cannot be seen by the other 14
  cases. Fixtures use only `id` and `updated_at`, the two fields the script reads.
- **R3. Releasing before the experiment of 5.3** puts force-cancel in `v3.0.0` with a trigger that
  may do nothing. Cost: if it must be removed, that is a second breaking release. Accepted if the
  user wants the release first.

## 10. Rejected alternatives

- **Redesign the contract again before the first v3 release.** No flaw in it is large enough to pay
  for a second migration (section 4).
- **Test the action only at level 1.** The wiring (`env:` names, outputs) is the part that unit
  tests cannot see, and it is the part that breaks on a rename. The fake `gh` makes level 2 as
  cheap as level 1.
- **Create stale queued runs in a scratch repository for a real cancel test.** A queued run cannot
  be made stale in minutes (the age threshold is in hours), and it needs a second repository, a
  token and a cleanup. The fake and one 404 check show the same thing, with no state.
- **Rewrite the script in Python or JavaScript.** Not on every runner, or a build step (P7, P8,
  P11). `gh` and `jq` are enough for 245 lines.
- **Move the logic into `run:` blocks of `action.yaml`.** It could not be sourced and tested (T5).
- **Delete `check_bats_assertions.sh` and the bash 3.2 job.** They protect against a real bats
  limitation on the macOS bash and cost 60 lines and one macOS job. Revisit only if P7 drops bash
  3.2.
