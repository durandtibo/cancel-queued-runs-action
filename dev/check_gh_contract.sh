#!/usr/bin/env bash
# Check the one thing of the real gh that scripts/cancel.sh relies on and that the fake gh of
# the tests only copies: a failed POST exits non-zero and writes "(HTTP nnn)" on stderr.
# It cancels the run 1 of this repository, which does not exist (nothing is cancelled).
#
# Environment variables: GITHUB_REPOSITORY (owner/name), GH_TOKEN (with actions: write).
# Exit codes: 0 - gh answered "(HTTP 404)"; 1 - it did not (the answer is printed).
set -euo pipefail

if err=$(gh api --method POST "/repos/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}/actions/runs/1/cancel" 2>&1 >/dev/null </dev/null); then
	echo "::error::gh api succeeded on a run that does not exist"
	exit 1
fi
if ! grep -qF '(HTTP 404)' <<<"$err"; then
	echo "::error::gh did not write '(HTTP 404)' on stderr: $err"
	exit 1
fi
echo "gh contract ok: $err"
