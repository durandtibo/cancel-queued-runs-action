# cancel-queued-runs-action: target state

Review date: 2026-11-17. Scope: `action.yaml`, `scripts/cancel.sh`, `tests/`, `dev/`, `examples/`,
`README.md`, `CLAUDE.md` and `.github/workflows/`. `.make/` is out of scope: it is synced from a
shared repository. The testing rules come from `review/testing.md` (properties T1 to T16).

What was read: every file listed above, except the bodies of the 61 bats files (only their names
and counts) and the fixtures. What was run: one read-only API call to check the `created` filter
(section 5.2). Not run: `make lint`, `make format`, `bats tests/`, and the CI workflows.

## 1. Properties of the action

These are the properties the target state must keep. Every choice below is judged against them.

| #   | Property                   | Statement                                                                                                                                                                                                                                                              |
| --- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | Single purpose             | Cancel the workflow runs of one repository that have not started (`queued` by default) for longer than `max_age_hours`. It does not prune by count, delete runs, or work on several repositories.                                                                      |
| P2  | Never cancels too much     | A run is cancelled only if its status is one the caller listed, it matches the filters, and its age is strictly greater than `max_age_hours`. A run in progress or completed is never touched. `dry_run` shows exactly what would happen, with no request that writes. |
| P3  | Idempotent and re-runnable | Running it twice, or two executions at the same time, gives the same end state. A run that is gone or finished between the listing and the request (HTTP 404 or 409) is skipped, not a failure. Whatever one execution did not do, the next one does.                  |
| P4  | Exact contract             | Every input is validated before the first API call and fails with an `::error::`. Every output is always set, has a documented format, and is the same for the local and the released action.                                                                          |
| P5  | Injection-safe             | Inputs reach the script only through `env:`. Values that go into an API path are checked against a strict pattern. Values that go into a query are sent as `gh api -f` fields, never concatenated. Nothing from the API is printed as a workflow command.              |
| P6  | Fails loudly, by choice    | A caller mistake and a failure to list the runs always fail. A failure to cancel a run fails by default, and becomes a warning only with `fail_on_error: false`.                                                                                                       |
| P7  | Portable                   | Works on GNU/Linux and BSD/macOS, and with the bash 3.2 of macOS. Uses only `bash`, `gh` and `jq`, which are on the GitHub-hosted runners. No `date` arithmetic, so no GNU/BSD split. Windows is not supported.                                                        |
| P8  | Small and fast             | One script of at most 250 lines and 12 functions. At most one listing call per status and per page, and one call per cancelled run. Work is done on the server (filters) and in one `jq` call, not in a bash loop per run.                                             |
| P9  | Maintainable               | Each behaviour has one place: a function, a test, one sentence in the README. No setting that cannot be explained in one sentence. No undocumented knob. The tests do not depend on the text of the script.                                                            |
| P10 | Tested at three levels     | Level 1: the script with a fake `gh`. Level 2: the local action, with no side effect. Level 3: the released action, nightly, same cases. What CI cannot test is written down with the check that covers it.                                                            |
| P11 | Shipped equals needed      | The release contains `action.yaml`, `LICENSE` and `scripts/cancel.sh`, and nothing else. It is checked in CI.                                                                                                                                                          |
| P12 | Immutable releases         | Exact version tags only. No floating tag.                                                                                                                                                                                                                              |

Non-goals: Windows runners, several repositories in one call (use a matrix, see the README),
deleting runs, keeping the N most recent runs (use `concurrency` in the workflow for that),
retrying inside the action (the schedule retries), and a configurable rate limit.

## 2. Findings in the current state

Numbers are counted from the repository at `02295e7`. Ordered by impact.

### Size and complexity (P8, P9)

- **1.** **The script is 1838 lines with 55 functions, for one `POST`.** The tests are 11,025
  lines (61 files, 1087 tests) and 120 mutations, so the test code is six times the code. Each
  extra feature below costs code, tests, mutations, README text and a troubleshooting entry.
- **2.** **14 inputs and 10 outputs, four of them modes of operation that change what the
  action is.** `max_runs` cancels runs "whatever their age", which contradicts P2: the action can
  cancel a run that was queued one minute ago. `delete_stuck_runs` deletes runs and their
  history. `max_cancellations` and `cancel_delay_seconds` are safety valves and rate-limit tuning
  that a hourly job with `dry_run` does not need. `force_cancel_buffer_hours` configures a tier
  whose value is doubtful (finding 4).
- **3.** **Two retry mechanisms, one tuning layer.** The listing retries on the error text
  (`is_transient_error`, 37 lines). The cancel retries on the HTTP headers (`is_rate_limited`,
  `get_retry_delay`, `post_run_endpoint_with_retry`, about 130 lines with the CRLF handling and
  nine HTTP fixtures). Five environment variables (`MAX_RETRIES`, `RETRY_BASE_DELAY`,
  `RETRY_MAX_DELAY`, `RUNS_LISTING_LIMIT`, `SUMMARY_MAX_RUNS`) are validated by a 38-line function
  but are in neither `action.yaml` nor the README: they cannot be set from the action. The
  action is scheduled hourly and is idempotent (P3), so the next execution is the retry.
- **4.** **The force-cancel tier almost never applies.** `process_run` sends `/force-cancel` only
  when `/cancel` fails with something other than 202, 404 or 409. A run stuck in the queue
  answers 409 to `/cancel`, which is skipped with no second request. So the tier runs only after
  a 5xx or a 403 on `/cancel`, which `/force-cancel` is unlikely to fix. `dev/README.md` says
  it itself: force-cancel "occasionally fails with a 500". Nothing in the repository shows one
  run that this tier cancelled. See open decision D1.
- **5.** **Dates are parsed in bash for both GNU and BSD** (`to_unix_ts`, `compute_age_seconds`,
  `format_age`, `is_old_enough`, about 110 lines plus the mutations that pin them). `jq` has
  `fromdateiso8601` and `now`, and is already required.
- **6.** **`process_all_runs` is 117 lines and runs `jq` four times**, then loops in bash with
  counters in globals, a `PROCESS_RUN_OUTCOME` global, and `RUN_RECORDS` as a string split on
  `|`. The functions "must not be called in a subshell" in five places (comments), which is a
  design smell: the state is hidden in globals.
- **7.** **The job summary is 160 lines** (`write_summary`, `write_summary_runs`,
  `describe_outcome`): a table of every outcome, the filters, a capped list of runs with links.
  The step log already has the same information.
- **8.** **`main` prints a line per option** (nine `if`s) and the validators are 14 functions
  of 16 to 38 lines, each with its own `.bats` file, for what is one table of rules.

### Correctness and efficiency (P2, P3, P8)

- **9.** **The listing is incomplete exactly where it matters.** The API lists the newest runs
  first and returns at most 1000 runs per status. The runs that the action wants (the oldest)
  are the ones cut off. The action then warns, and the `listing_truncated` output exists only
  for this. The cause is that the action downloads every queued run, young or old, then filters
  in bash. The API has a server-side filter on the creation date (section 5.2), which is a
  strict superset of the stale runs because `updated_at >= created_at`. With it, a queue of 5000
  young runs and 3 stale ones is a single page of 3 runs.
- **10.** **Wasted calls.** For a repository with a big queue, the current listing downloads up
  to 10 pages of 100 runs for each status, then throws away nearly all of them.
- **11.** **Cancel and force-cancel, deletion and `/jobs` lookups add up to four request types
  per run**, each with its own error handling, the 404 and 403 special cases of `delete_run`,
  and the `PROCESS_RUN_OUTCOME` states `noop`, `cancelled`, `deleted`, `skipped`, `would-cancel`,
  `failed`.
- **12.** **The age is `updated_at`, which is named `queued_at` in the code and the README.**
  The choice is deliberate and right (a re-run run restarts its age), but the field name lies.
  The target keeps the rule and names it.

### Tests and CI (P10, P11, T11, T16)

- **13.** **The tests of level 2 cancel real runs.** The `test` job (13 cells) and `test-48h`
  run the action without `dry_run` against this repository. This breaks T11 (no side effect)
  and makes the result depend on what is queued at that moment. A real cancel cannot be
  asserted, so the jobs only check that the step succeeds. `test-outputs` already does the right
  thing (dry run, assertions on outputs), but only on one runner.
- **14.** **The cases are jobs, not data** (T8): three jobs of 25 to 60 lines, each duplicated
  for local and released. A new case is a new job.
- **15.** **The mutation check is coupled to the text of the script.** 120 `sed` expressions
  such as `s/\[ "\$age_seconds" -gt "\$force_age_seconds" \]/.../` break on any rewrite of a
  line, so the check punishes refactoring. It is a good idea (T12) with a fragile form.
- **16.** **Most unit tests mock one function to test the next one** (61 files). They pin the
  structure, not the behaviour: replacing `post_run_endpoint` by a different way to call `gh`
  would fail tests that still describe correct behaviour.
- **17.** **`dev/` and the bots are partly redundant.** `dev/run_for_repos.sh` (119 lines) calls
  `scripts/cancel.sh` directly, so it is coupled to the internals, and loops over the user's
  repositories, as `bot-report-queued-runs.yaml` does for the report. `dev/README.md` (250 lines)
  proposes a "workaround" that the script already implements and explains tests in prose that
  the tests say better. `bot-cancel-stale-queued-runs.yaml` runs the action at `v1.9` while the
  latest release is `v2.0.0`.

### Documentation (P4, P9)

- **18.** **The README is 650 lines.** About 250 lines are troubleshooting entries that quote
  internal log lines (`::warning::MAX_CANCELLATIONS (...) reached`), so every message change is
  a README change. The same facts appear in three places (README, `action.yaml`, the header of
  `cancel.sh`).
- **19.** **Input names are `snake_case`, the sibling actions use `kebab-case`**
  (`python-version`, `uv-version`, `github-app-client-id`). One naming per fleet is cheaper to
  remember and to template. This is a breaking change, so it belongs in the same release as the
  rest.

## 3. Target contract

Breaking changes are intentional, listed in section 8. The target version is `v3.0.0`.

### Inputs (9, down from 14)

| Input           | Default                    | Description                                                                                                                                                       |
| --------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `github-token`  | `${{ github.token }}`      | Token with `actions: write` on the target repository.                                                                                                             |
| `repo`          | `${{ github.repository }}` | Target repository, `owner/name`.                                                                                                                                  |
| `max-age-hours` | `24`                       | A run older than this many hours is cancelled. Positive integer. The age is measured from the last update of the run (`updated_at`), so a re-run restarts it.     |
| `statuses`      | `queued`                   | Comma-separated, among `queued`, `waiting`, `pending`, `requested`. Duplicates are ignored. Runs in progress are never listed.                                    |
| `workflow`      | empty                      | Only the runs of this workflow: a file name (`ci.yaml`) or a numeric ID. Empty means all.                                                                         |
| `branch`        | empty                      | Only the runs of this head branch, by name, case sensitive. Empty means all.                                                                                      |
| `event`         | empty                      | Only the runs triggered by this event (`push`, `schedule`, ...). Empty means all.                                                                                 |
| `fail-on-error` | `true`                     | `true` or `false`. When `false`, a run that could not be cancelled is a warning and the step succeeds. Invalid inputs and a failure to list the runs always fail. |
| `dry-run`       | `false`                    | `true` or `false`. List and log the runs that would be cancelled, send nothing that writes.                                                                       |

Booleans accept exactly `true` and `false`. Anything else fails the step.

### Outputs (5, down from 10)

| Output              | Value                                                                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `eligible-count`    | Integer. Runs older than `max-age-hours` that match the statuses and filters. In a dry run, this is the number that would be cancelled.     |
| `cancelled-count`   | Integer. Runs for which GitHub accepted the cancel request (HTTP 202). Always `0` in a dry run.                                             |
| `skipped-count`     | Integer. Runs that were gone or no longer cancellable (HTTP 404 or 409).                                                                    |
| `failed-count`      | Integer. Runs that could not be cancelled, and runs left unprocessed because GitHub rate limited the execution.                             |
| `cancelled-run-ids` | JSON array on one line, for example `[101,102]`, `[]` if none, in the order processed. Read it with `fromJSON()`. Always `[]` in a dry run. |

Invariant: `cancelled + skipped + failed = eligible` outside a dry run. All five are set on every
path, including a failure, so that a step with `continue-on-error` can be read.

Removed: `found_count` (the target does not download the runs it does not need, finding 9),
`would_cancel_count` (equal to `eligible-count` in a dry run), `deleted_count`, `deferred_count`
and `listing_truncated` (their features are removed, see section 8).

### Behaviour

1. **Validate** every input, then the presence of `gh`, `jq` and a token. Stop at the first
   problem with one `::error::` line.
2. **Compute the cutoff** with `jq`: `now - max-age-hours * 3600`, as an ISO 8601 UTC string.
   It is computed once, so all the runs are compared with the same instant.
3. **List** the candidates: for each distinct status, one paginated `GET` on
   `/repos/{repo}/actions/runs` (or `/actions/workflows/{workflow}/runs`), with the fields
   `status`, `per_page=100`, `created=<cutoff`, and `branch` and `event` when set. A listing
   error fails the step, after the outputs are written.
4. **Select** with one `jq` call: keep the runs with `updated_at < cutoff`, remove duplicates by
   `id` (a status changed between two calls), sort by `updated_at`, oldest first. The output is
   one `id age` line per run.
5. **Cancel** each run, oldest first, with `POST /actions/runs/{id}/cancel`, unless `dry-run`.
   Outcome by HTTP code: 202 cancelled; 404 or 409 skipped with a warning; 429, or 403 with a
   rate limit message: stop, and count this run and the ones after it as failed; anything else:
   failed, and continue. A fixed pause of one second separates two requests (the delay GitHub asks
   for between requests that write); nothing is waited before the first one or in a dry run.
6. **Report**: set the outputs, write one summary table (section 4), and exit `1` when
   `failed-count > 0` and `fail-on-error` is `true`.
7. If the listing reaches 1000 runs for a status, write a `::warning::` that older candidates may
   be missing. There is no output for it: the cancelled runs leave the queue, so the next
   execution sees the rest, and the execution converges.

The decision `cancel / do not cancel` has exactly one rule (P2): `updated_at < cutoff`. There is
no second tier, and no rule depends on another input.

## 4. Target `action.yaml`

One composite step. The step is one script because the three parts (validate, decide, act) share
data that is cheaper to pass in memory than through step outputs, and because splitting the
script would make it harder to run and test on a laptop (T13).

```yaml
name: "cancel-queued-runs"
description: "Cancel the workflow runs that have not started for longer than a number of hours"
author: "Thibaut Durand"
branding:
  icon: "clock"
  color: "blue"

inputs:
  github-token:
    description: "Token with actions:write permission on the target repository"
    default: ${{ github.token }}
  repo:
    description: "Target repository, owner/name"
    default: ${{ github.repository }}
  max-age-hours:
    description: >
      Runs older than this many hours are cancelled (positive integer). The age is measured from
      the last update of the run, so a re-run restarts it
    default: "24"
  statuses:
    description: >
      Comma-separated run statuses to consider, among queued, waiting, pending and requested
    default: "queued"
  workflow:
    description: "Only the runs of this workflow: a file name (ci.yaml) or a numeric ID"
    default: ""
  branch:
    description: "Only the runs of this head branch, given by name (case sensitive)"
    default: ""
  event:
    description: "Only the runs triggered by this event (push, schedule, ...)"
    default: ""
  fail-on-error:
    description: >
      "true" or "false". If "false", a run that could not be cancelled is a warning, not a failure
    default: "true"
  dry-run:
    description: >
      "true" or "false". If "true", log the runs that would be cancelled and cancel nothing
    default: "false"

outputs:
  eligible-count:
    description: "Number of runs older than max-age-hours (in a dry run: that would be cancelled)"
    value: ${{ steps.cancel.outputs.eligible-count }}
  cancelled-count:
    description: "Number of runs for which a cancel request was accepted (0 in a dry run)"
    value: ${{ steps.cancel.outputs.cancelled-count }}
  skipped-count:
    description: "Number of runs that were gone or not cancellable anymore (HTTP 404 or 409)"
    value: ${{ steps.cancel.outputs.skipped-count }}
  failed-count:
    description: "Number of runs that could not be cancelled, or were left when GitHub rate limited"
    value: ${{ steps.cancel.outputs.failed-count }}
  cancelled-run-ids:
    description: 'JSON array of the cancelled run IDs, "[]" if none. Read it with fromJSON()'
    value: ${{ steps.cancel.outputs.cancelled-run-ids }}

runs:
  using: "composite"
  steps:
    - name: Cancel the stale runs
      id: cancel
      shell: bash
      run: ${{ github.action_path }}/scripts/cancel.sh
      env:
        GH_TOKEN: ${{ inputs.github-token }}
        REPO: ${{ inputs.repo }}
        MAX_AGE_HOURS: ${{ inputs.max-age-hours }}
        STATUSES: ${{ inputs.statuses }}
        WORKFLOW: ${{ inputs.workflow }}
        BRANCH: ${{ inputs.branch }}
        EVENT: ${{ inputs.event }}
        FAIL_ON_ERROR: ${{ inputs.fail-on-error }}
        DRY_RUN: ${{ inputs.dry-run }}
```

The job summary is one table, written by the script: the repository, the age, the counts of the
five outputs, and the runs cancelled as links, capped at 50. It replaces the 160 lines of the
current summary.

The permissions a caller needs are `actions: write` (it includes read). `contents: read` is only
for a checkout step, which this action does not need.

## 5. Target `scripts/cancel.sh`

Budget: at most 250 lines including comments, at most 12 functions, no global that a function
changes except the counters (and these are read by one function). Every decision is in a function
that takes its input as an argument and prints its result.

### 5.1 Functions

| Function        | Lines | Job                                                                                              |
| --------------- | ----- | ------------------------------------------------------------------------------------------------ |
| `die`           | 4     | Print `::error::` and exit 1 (or return, when sourced).                                          |
| `require`       | 12    | `require NAME KIND`: one rule table for all the inputs (`int`, `bool`, `statuses`, `repo`, ...). |
| `validate_all`  | 25    | Call `require` for each input, then check `gh`, `jq` and the token.                              |
| `cutoff`        | 4     | Print the ISO 8601 UTC time `max-age-hours` ago, computed by `jq` (`now`, `todate`).             |
| `list_stale`    | 30    | One paginated `gh api` call per distinct status. Print `{id, updated_at}` lines.                 |
| `select_stale`  | 10    | `jq`: filter on the cutoff, deduplicate by id, sort oldest first, print `id age_seconds`.        |
| `cancel_run`    | 20    | One `POST`, print `cancelled`, `skipped`, `failed` or `rate-limited`.                            |
| `cancel_all`    | 30    | The loop: pause, call `cancel_run`, count, stop on a rate limit.                                 |
| `write_outputs` | 12    | Write the five outputs to `$GITHUB_OUTPUT`.                                                      |
| `write_summary` | 25    | The one table.                                                                                   |
| `main`          | 30    | The flow of section 3, skipped when the file is sourced by tests.                                |

### 5.2 Key mechanics

**Server-side filter on the creation date.** One read-only call was made on this repository to
check the syntax. `status=completed` returned `total_count` 2500 without the filter, 2490 with
`created=<2026-06-01T00:00:00Z` and 0 with `created=<2020-01-01T00:00:00Z`, so the comparison with
a full ISO 8601 timestamp works and filters on the server. It is sent as a field, not in the URL:

```bash
gh api --method GET "$runs_path" --paginate \
  -f status="$status" -f per_page=100 -f "created=<$cutoff" \
  ${BRANCH:+-f "branch=$BRANCH"} ${EVENT:+-f "event=$EVENT"} \
  --jq '.workflow_runs[] | {id, updated_at}'
```

Because `updated_at >= created_at`, a run created after the cutoff cannot have an `updated_at`
before it, so the filter never removes a stale run. The exact `updated_at` test is still done in
step 4, because a run created long ago and re-run recently must not be cancelled.

**Dates in `jq`, not in bash.** `fromdateiso8601` and `now` work the same on GNU and BSD, and a
test passes a fixed instant with `--argjson now`, so no `date` mock is needed:

```bash
select_stale() { # stdin: {id, updated_at} lines; $1: cutoff; $2: now (epoch seconds)
  jq -r -s --arg cutoff "$1" --argjson now "$2" '
    unique_by(.id) | map(select(.updated_at < $cutoff)) | sort_by(.updated_at)
    | .[] | "\(.id) \($now - (.updated_at | fromdateiso8601))"'
}
```

The comparison of two ISO 8601 UTC strings of the same shape is a plain string comparison, which
is correct and avoids parsing. The age in seconds is only for the log.

**One way to read an error.** `gh api` exits non-zero on HTTP 400 and above and writes
`... (HTTP 409)` on stderr. `cancel_run` reads the code from there, with no `-i`, no header
parsing and no carriage-return handling:

```bash
cancel_run() { # $1: run id
  local out code
  if gh api --method POST "/repos/$REPO/actions/runs/$1/cancel" >/dev/null 2>"$ERR"; then
    echo cancelled; return
  fi
  out=$(<"$ERR")
  code=$(printf '%s' "$out" | sed -nE 's/.*\(HTTP ([0-9]{3})\).*/\1/p' | head -n1)
  case "$code" in
  404 | 409) echo skipped ;;
  429) echo rate-limited ;;
  403) if printf '%s' "$out" | grep -qi 'rate limit'; then echo rate-limited; else echo failed; fi ;;
  *) echo failed ;;
  esac
}
```

**No global state to chase.** `cancel_all` reads the `id age` lines and keeps four counters and
the list of ids in its own scope; `write_outputs` and `write_summary` take them as arguments
(`write_outputs eligible cancelled skipped failed ids`). There is no `PROCESS_RUN_OUTCOME`, no
`RUN_RECORDS`, and no function with a "must not be called in a subshell" rule.

**Validation as a table.**

```bash
validate_all() {
  require MAX_AGE_HOURS pint
  require STATUSES statuses
  require FAIL_ON_ERROR bool
  require DRY_RUN bool
  require REPO repo
  require WORKFLOW workflow_or_empty
  require BRANCH no_newline
  require EVENT no_newline
  ...
}
```

`BRANCH` and `EVENT` only need to be one line: they are sent as `-f` fields, so they cannot add a
query parameter or break the path. `WORKFLOW` and `REPO` go in a path and keep a strict pattern.

### 5.3 What is dropped from the script, and why

| Removed                                                                                                                                                                                 | Lines (about) | Reason                                                                            |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | --------------------------------------------------------------------------------- |
| `to_unix_ts`, `compute_age_seconds`, `format_age`, `is_old_enough`                                                                                                                      | 110           | `jq` does the dates (finding 5).                                                  |
| `is_transient_error`, `list_runs_of_status` retry, `get_retry_delay`, `is_rate_limited`, `post_run_endpoint_with_retry`, `get_status_code`, `get_response_message`, `post_run_endpoint` | 330           | The schedule is the retry (finding 3).                                            |
| `force_cancel_run`, the force tier in `process_run`                                                                                                                                     | 60            | Almost never applies (finding 4).                                                 |
| `delete_run`, `delete_zombie_run`, `run_has_no_jobs`                                                                                                                                    | 140           | Destructive, out of purpose (P1).                                                 |
| `select_excess_run_ids`, `cancellation_limit_reached`, `throttle_requests` configuration, `reset_counters`, `record_run`, `count_unparsed_runs`                                         | 120           | `max_runs`, `max_cancellations`, `cancel_delay_seconds` and the globals are gone. |
| 14 validators, `validate_tuning_variables`                                                                                                                                              | 270           | One `require` function and a table.                                               |
| `write_summary_runs`, `describe_outcome`, the long `write_summary`                                                                                                                      | 130           | One table.                                                                        |
| `create_work_dir`, `cleanup_work_dir`, `make_temp_file`                                                                                                                                 | 50            | One temp file for stderr, removed by a `trap`.                                    |
| `dedupe_runs`, `fetch_runs`, `warn_if_listing_truncated`                                                                                                                                | 90            | Replaced by `list_stale` and `select_stale`.                                      |

## 6. Tests

The strategy is `review/testing.md`. The target is a smaller suite that pins behaviour, not text.

### 6.1 Level 1: the script, with a fake `gh`

- One fake `gh` on `PATH` for the whole suite (`tests/helpers/fake_gh`). It answers from a table
  in the test (path and method to code and body) and appends every call to a log file. A test
  reads the log to assert which requests were sent. This replaces 61 files that mock one
  function each, and the nine `.http` fixtures.
- Tests are grouped by behaviour, not one file per function: `validate.bats` (every input: one
  valid and one invalid value, all in a table), `select_stale.bats` (boundaries: exactly
  `max-age-hours`, one second more, one second less, a re-run run, a duplicate, an empty list),
  `cancel_run.bats` (202, 404, 409, 429, 403 with and without a rate limit message, 500, an
  empty body), `cancel_all.bats` (order, pause, stop on a rate limit, counters), `list_stale.bats`
  (filters sent as fields, one call per distinct status, an error on the listing), `main.bats`
  (the flow, dry run sends no `POST`, `fail-on-error`, outputs on every path), `outputs.bats`
  (format of the five outputs and of the summary).
- The rule "each function has its own `tests/<function>.bats`" in `CLAUDE.md` is replaced by "one
  file per behaviour group, named after what it checks". The rule "one behaviour per test",
  "mock `gh`", "regression test for each bug fix" and "boundary ages" stay.
- `dev/check_bats_assertions.sh` (the check that assertions do not pass vacuously on bash 3.2) is
  kept: it checks the tests, not the script.
- Time is injected (`--argjson now`), never mocked, so `date` is not faked.

### 6.2 Mutation check

Kept (T12), reduced to the rules that define P2 and P3. It stays a `sed` on the script, because a
switch inside the script would put test code in production. To survive a refactor, the list is
limited to about 15 mutations on the decisions that matter, each anchored on a short, stable
token (an operator, a function name) and not on a whole line:

| Decision                                | Mutation                             |
| --------------------------------------- | ------------------------------------ |
| Age is strictly greater than the cutoff | `<` to `<=` in `select_stale`        |
| A run younger than the cutoff is kept   | remove the `select`                  |
| Duplicates are removed                  | remove `unique_by`                   |
| Dry run sends nothing                   | ignore `DRY_RUN`                     |
| 404 and 409 are skipped, not failed     | swap with `failed`                   |
| A rate limit stops the loop             | continue instead of stopping         |
| `fail-on-error: false` does not fail    | ignore it                            |
| A non-boolean value is rejected         | accept any value                     |
| Statuses are listed once each           | remove the deduplication of statuses |
| The filters are sent                    | drop `branch` and `event`            |

The check runs on one OS in `ci-mutation-check.yaml`, as today. If the number of mutations grows
over 25, that is a sign the script grew again.

### 6.3 Level 2 and 3: the action, in a real workflow

One reusable `ci-action.yaml` with `use-released` (as today, T7). Two changes: no job cancels a
real run (T11), and the cases are data (T8).

- **General behaviour, `os_matrix` (13 cells):** the default usage with `dry-run: true`. It asserts
  the contract: `cancelled-count` is `0`, `cancelled-run-ids` is `[]`, the four counts are
  integers, `eligible-count` is the number of lines the log reports. This runs on every OS and
  shows that `gh`, `jq` and the script work on each of them.
- **Edge cases, one runner (`ubuntu-latest`):** one row per case in `tests/action_cases.json`,
  each row a matrix cell:

| Case id               | Inputs                                                        | Asserts                                                      | `released` |
| --------------------- | ------------------------------------------------------------- | ------------------------------------------------------------ | ---------- |
| `default-dry-run`     | `dry-run: true`                                               | outputs are well formed                                      | `false`    |
| `huge-age`            | `max-age-hours: 87600`, `dry-run: true`                       | `eligible-count` is exactly `0`                              | `false`    |
| `all-statuses`        | `statuses: queued,waiting,pending,requested`, `dry-run: true` | succeeds                                                     | `false`    |
| `workflow-filter`     | `workflow: ci.yaml`, `dry-run: true`                          | succeeds                                                     | `false`    |
| `branch-event-filter` | `branch: main`, `event: push`, `dry-run: true`                | succeeds                                                     | `false`    |
| `invalid-age`         | `max-age-hours: not-a-number`                                 | outcome is `failure`, and `failed-check` is `validate`       | `false`    |
| `invalid-bool`        | `dry-run: yes`                                                | outcome is `failure`                                         | `false`    |
| `invalid-status`      | `statuses: running`                                           | outcome is `failure`                                         | `false`    |
| `unknown-workflow`    | `workflow: no-such-file.yaml`                                 | outcome is `failure` (the listing fails), outputs still set  | `false`    |
| `fail-on-error-false` | `workflow: no-such-file.yaml`, `fail-on-error: false`         | the listing still fails, which `fail-on-error` does not hide | `false`    |

The `released` column is `false` for every row until `v3.0.0` is released, because the released
action has the old input names. Each failure row follows the positive row on the same runner
(T12).

- **Verification script:** `dev/check_action_case.sh` reads a case and the step outputs from
  the environment and asserts them, so the local and the released runs use the same code (T6).
  Outputs are asserted by format and by invariant, never printed only (T16).
- **Level 3:** `nightly.yaml` calls `ci-action.yaml` with `use-released: true`, as today. The
  pinned release in the file is updated by `bot-pin-action.yaml`.
- **What CI cannot test, and what covers it (T11).** A real cancel changes the repository, so
  no CI job does it. It is covered by the unit tests (level 1) with the fake `gh`, and in
  production by `bot-cancel-stale-queued-runs.yaml`, which runs the released action hourly against
  this repository: a failing real cancel fails that workflow, which is visible on the repository.
- **Cells per run (T10):** 13 (general) + 10 (cases) on each of the PR, the push and the nightly
  of the released action. `max-parallel: 8`, `fail-fast: false`, `timeout-minutes: 5`.

### 6.4 Other checks, unchanged

`ci-format.yaml`, `ci-shell.yaml`, `ci-shell-bash32.yaml` (P7: bash 3.2 on macOS),
`ci-export.yaml` (P11), `ci-verify-workflows.yaml`, `lib-get-test-matrix.yaml`. The expected set
of exported files in `dev/check_export.sh` is unchanged: `LICENSE`, `action.yaml`, `scripts/`,
`scripts/cancel.sh`.

## 7. Repository, workflows and documentation

### Repository

| Path                        | Target                                                                                                                                                                                                                               |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `scripts/cancel.sh`         | At most 250 lines (section 5).                                                                                                                                                                                                       |
| `tests/*.bats`              | About 8 files by behaviour group, `tests/helpers/fake_gh`, `tests/action_cases.json`, `tests/action_readme_sync.bats`.                                                                                                               |
| `tests/fixtures/*.http`     | Removed, with the `-text` rule in `.gitattributes`.                                                                                                                                                                                  |
| `dev/`                      | `check_action_case.sh`, `check_bats_assertions.sh`, `check_export.sh`, `mutation_check.sh`, `mutants.txt`. `run_for_repos.sh` removed.                                                                                               |
| `dev/README.md` (250 lines) | Removed. What is useful (how to run the tests, how to add a mutation) goes to `CONTRIBUTING.md` in at most 30 lines.                                                                                                                 |
| `examples/`                 | Three files: `basic-usage.yaml`, `scheduled-cleanup.yaml`, `multi-repo-cleanup.yaml` (a matrix over repositories, which replaces `run_for_repos.sh`). `ci-integration.yaml` and `custom-permissions.yaml` are covered by the README. |
| `review/`                   | `testing.md` and this file.                                                                                                                                                                                                          |

### Workflows

- `bot-cancel-stale-queued-runs.yaml`: update to the new release and the new input names. Remove
  the `max_runs` input. Keep the hourly schedule.
- `bot-report-queued-runs.yaml`: unchanged, it is a report and not a use of the action.
- `ci.yaml`, `ci-*.yaml`, `nightly.yaml`: structure unchanged, `ci-action.yaml` rewritten as in
  section 6.3. Every job keeps `permissions`, `timeout-minutes` and pinned actions.
- Everything else (`security-*`, `bot-format-files`, `bot-pin-action`, `bot-sync-shared-makefile`)
  is unchanged.

### `README.md` (about 150 lines, down from 650)

1. What it does, in three lines, and the one-step usage example.
2. Inputs and outputs, as the two tables of section 3. The text is the one of `action.yaml`, and
   `tests/action_readme_sync.bats` checks it (T14).
3. Four examples: the default, a dry run, a filter on a workflow and a branch, and a scheduled
   cleanup. The multi-repository case links to `examples/multi-repo-cleanup.yaml`.
4. How it works, in the six steps of section 3, with the one rule (`updated_at` older than the
   limit) and its consequence for a re-run run.
5. Limitations: queued and similar statuses only, one repository, 1000 runs per status and
   per execution (and why it converges), a run that GitHub refuses to cancel stays in the queue
   and shows up as `skipped-count`, rate limits stop the execution and the next one continues.
6. Migrating from `v2`: the table of section 8.

The troubleshooting entries that quote log lines are removed. A log line is not an interface.
A short "A run is skipped (HTTP 409)" paragraph remains, with the manual workaround
(`gh api -X DELETE /repos/{repo}/actions/runs/{id}`) for the rare zombie run that the action no
longer deletes.

### `CLAUDE.md`

Update four things: the test rule (one file per behaviour group), the list of `dev/` helpers, the
sentence that says "Each function ... has its own `tests/<function_name>.bats` file", and the
target layout note ("The cases are in a JSON file" is now true, so remove "does not follow it
everywhere yet" for this repository). The shell rules (portable, `shellcheck`, `shfmt`, quote
everything, validate early) stay.

## 8. Breaking changes and migration

Release `v3.0.0` (an exact tag, no floating tag, P12). The `v2.0.0` release stays valid.

| Change                                                                                                                                 | Migration                                                                                          |
| -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Inputs renamed to kebab-case (`github_token` to `github-token`, `max_age_hours` to `max-age-hours`, `fail_on_error`, `dry_run`)        | Rename the keys.                                                                                   |
| `force_cancel_buffer_hours` removed, and the `/force-cancel` fallback with it                                                          | Delete the key. A run that `/cancel` refuses with 409 is counted in `skipped-count`.               |
| `delete_stuck_runs` removed                                                                                                            | Delete the key. Delete a zombie run by hand with the `gh api` command of the README.               |
| `max_runs` removed                                                                                                                     | Use `concurrency: { group: ..., cancel-in-progress: true }` in the workflow that creates the runs. |
| `max_cancellations` and `deferred_count` removed                                                                                       | Use `dry-run` first. The hourly schedule bounds the work of one execution to one backlog.          |
| `cancel_delay_seconds` removed                                                                                                         | Replaced by a fixed one-second pause between two cancel requests.                                  |
| Outputs renamed to kebab-case, and `found_count`, `would_cancel_count`, `deleted_count`, `deferred_count`, `listing_truncated` removed | Read `eligible-count` for the old `would_cancel_count`.                                            |
| The five tuning environment variables of the script                                                                                    | They were not reachable from the action. Gone.                                                     |
| `scripts/cancel.sh` called directly                                                                                                    | `dev/run_for_repos.sh` is removed. Use the matrix example.                                         |
| A rate limit stops the execution instead of retrying 3 times                                                                           | The unprocessed runs are in `failed-count` and the next execution cancels them.                    |
| A transient listing error fails the step at once (no retry)                                                                            | Next scheduled execution. A caller who needs more can wrap the step in a retry action.             |

Behaviour that does not change: the age is measured from `updated_at`; the threshold is
"strictly older than"; 404 and 409 are skipped; `fail-on-error` defaults to `true`; every input
is validated before any API call; `dry-run` writes nothing.

## 9. Decisions and risks

- **D1. Remove the force-cancel tier?** The recommendation is to remove it (finding 4). It is the
  only item that rests on a fact the repository does not contain. Before the change, search the
  logs of `bot-cancel-stale-queued-runs.yaml` for `Force-cancelling` followed by a 202. If one
  exists, keep one fallback, `/cancel` then `/force-cancel` on a 5xx, as the only tier, with no
  buffer input.
- **D2. Rename the inputs to kebab-case?** Recommended: one convention in the fleet, and the
  release is breaking anyway. If the cost for consumers is judged too high, keep `snake_case`;
  nothing else in this document depends on it.
- **D3. The fixed one-second pause.** It costs one second per cancelled run: a backlog of 300 runs
  takes five minutes, and the job has `timeout-minutes` to set for it. If that is too slow, make
  the pause apply only after the 20th request. The simpler rule is kept until a backlog proves
  it wrong.
- **R1. The `created` filter is a documented API feature, but a change by GitHub would make the
  listing return too much, not too little.** The `updated_at` test in `select_stale` is the
  authority, so the filter can only cost time. A level-1 test asserts that the `created` field is
  sent, and the nightly dry run on the released action shows a changed behaviour as a failure.
- **R2. The `(HTTP nnn)` suffix of `gh` errors is how the code is read.** This is the same
  assumption the current code makes for the listing. The level-1 tests pin the shape. If `gh`
  changes it, the unknown code is `failed`, which is the safe side (a loud failure, no wrong
  cancel).
- **R3. A smaller suite has fewer tests.** The count of tests goes from 1087 to about 150. The
  aim is that each of them describes a behaviour of section 3, and the mutation check (6.2) is the
  proof that the boundaries are covered. Coverage of behaviours, not the number of tests, is the
  measure.

## 10. Rejected alternatives

- **Keep every feature, only refactor.** It keeps the 14 inputs, the doubtful tier, the
  destructive deletion and six times more test code than script. The cost of each feature is paid
  on every change for ever, for a purpose (P1) it does not serve.
- **Rewrite in Python or JavaScript.** Python is not on every runner image, JavaScript needs a
  build step or a committed `dist/` (P11, P8). `gh` and `jq` are there, and with the server
  filter and one `jq` call the logic is about 100 lines of bash.
- **Several composite steps with step outputs.** Good for `read-json-action`, where each step
  has a different tool. Here the data (a list of runs) is large and flows through one pipeline,
  and a single script is the thing that runs on a laptop (T13).
- **Move the logic into `action.yaml` as `run:` blocks.** It cannot be sourced and unit-tested,
  which T5 and T13 require.
- **Keep the retry layers, but share one.** Smaller than today, but still about 80 lines and
  3 inputs of tuning for a case (a transient failure) that the hourly schedule already absorbs.
- **List everything, then filter in `jq`, without `created`.** Simpler to explain, and it
  is what the action does today. It downloads every young run to find the old ones and loses the
  old ones when the queue is over 1000 (finding 9).
- **Keep `max_runs` as a separate action.** The use case (prune a queue to the N most recent
  runs) is what `concurrency: cancel-in-progress` does at creation time, with no scheduled job.

## 11. Migration plan

One branch and one PR per step, each from an up-to-date `main` (CLAUDE.md). Each PR leaves `main`
releasable.

1. **Tests first.** Add `tests/helpers/fake_gh` and `tests/action_cases.json`, and a characterization
   suite of the current behaviour at the script boundary (the five rules that stay: threshold,
   dry run, 404 and 409, `fail-on-error`, validation). Nothing in the script changes. This is what
   makes steps 2 and 3 safe.
2. **Remove the features** (`delete_stuck_runs`, `max_runs`, `max_cancellations`,
   `cancel_delay_seconds`, force tier, tuning variables), with their tests, mutations and README
   text. Behaviour change: listed in section 8.
3. **Rewrite the core:** `jq` dates, `list_stale` with the `created` filter, `cancel_run` reading
   the code from `gh`, the one `require` table, the one summary. Delete the old functions and the
   old tests. The script is at most 250 lines at the end of this PR.
4. **Rename inputs and outputs** and the new `action.yaml` (section 4), update the bot workflow
   and the examples, rewrite the README and `CLAUDE.md`, remove `dev/run_for_repos.sh`,
   `dev/README.md` and `tests/fixtures/`.
5. **Rewrite `ci-action.yaml`** with the case table, remove the real cancels, add
   `dev/check_action_case.sh`, reduce `dev/mutants.txt`.
6. **Release `v3.0.0`**, then pin it in `ci-action.yaml` and in the bot workflow (the pin bot
   does it), and set `released: true` on the rows that the release supports.

Steps 2 and 3 can be one PR if the review is easy, but not with step 4: the rename is the part a
consumer sees, and a revert must be possible alone.
