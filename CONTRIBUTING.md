# Contributing to cancel-queued-runs-action

Thank you for your interest in contributing to this project! We welcome contributions from the community.

## How to Contribute

### Reporting Issues

If you encounter a bug or have a feature request:

1. Check the [existing issues](https://github.com/durandtibo/cancel-queued-runs-action/issues)
   to see if it has already been reported
2. If not, create a new issue with a clear title and description
3. Include any relevant information:
   - Steps to reproduce (for bugs)
   - Expected behavior
   - Actual behavior
   - Your environment (OS, GitHub Actions runner version, etc.)

### Submitting Changes

1. **Fork the repository** and create your branch from `main`
2. **Make your changes**:
   - Follow the existing code style
   - Add or update tests if applicable
   - Update documentation as needed
3. **Test your changes**:
   - Run shellcheck on modified scripts: `shellcheck scripts/*.sh`
   - Run the unit tests: `bats --recursive tests` (see [Tests](#tests) below)
   - Check that the tests detect breakages of the script: `make mutation-check`
   - Test the action locally if possible
4. **Commit your changes**:
   - Use clear and descriptive commit messages
   - Reference any related issues
5. **Submit a pull request**:
   - Provide a clear description of the changes
   - Link to any related issues
   - Ensure CI checks pass

## Development Setup

### Prerequisites

- Bash shell (Linux or macOS)
- GitHub CLI (`gh`) installed and configured
- shellcheck for linting (optional but recommended)

### Local Testing

You can test the action locally by running:

```bash
# Set required environment variables
export GH_TOKEN="your-github-token"
export REPO="owner/repo"
export MAX_AGE_HOURS=24  # optional

# Run the script
./scripts/cancel.sh
```

### Running Tests

The project uses BATS (Bash Automated Testing System) for unit tests:

```bash
# Install BATS
# On Ubuntu/Debian:
sudo apt-get install bats

# On macOS:
brew install bats-core

# Run all tests
bats --recursive tests

# Run specific test file
bats tests/cancel_run.bats
```

## Tests

- One file per behaviour group in `tests/` (`validate.bats`, `select_stale.bats`, ...). They use one
  fake `gh`, `tests/helpers/fake_gh`: a table of `METHOD|GLOB|CODE|BODY` rules and a log of the
  calls (see the helpers in `tests/helpers/common.bash`). Time is injected, never mocked.
- The local bash can be 3.2 (macOS): a failing `[[ ... ]]` or `! cmd` that is not the last command
  of a test does not fail it. End such assertions with `|| false`; `make lint-bats` checks it.
- `make mutation-check` breaks `scripts/cancel.sh` on purpose, one decision at a time, and every
  mutation must make a test fail. The mutations are in `dev/mutants.txt`
  (`name@@test files@@sed -E expression`): add one when you add a decision, anchored on a short
  token, not on a whole line. `SURVIVED` means a test does not check what its name says.
- The action tests (`ci-action.yaml`) use the real `gh` and never cancel a run. Their cases are the
  rows of `tests/action_cases.json` (`id`, `inputs`, `expect`, `outputs`, `released`), checked by
  `dev/check_action_case.sh`: add a row, not a job. A row with an invalid value proves that an input
  reaches the script. The effect of an input is a unit test with the fake `gh`.
- `tests/action_readme_sync.bats` keeps the inputs and outputs of `action.yaml` and `README.md`
  identical (names, defaults and descriptions): update both.

## Code Style

- Follow shell scripting best practices
- Use shellcheck to validate scripts
- Add comments for complex logic
- Keep functions small and focused
- Update tests when modifying functionality
- Update documentation and examples when adding features

## Documentation

When making changes, please update relevant documentation:

- Update [README.md](README.md) for user-facing changes
- Add examples to [examples/](examples/) for new use cases (the history is in the
  [release notes](https://github.com/durandtibo/cancel-queued-runs-action/releases))

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you are expected to uphold this code.

## Questions?

If you have questions, feel free to:

- Open an issue for discussion
- Reach out to the maintainers

Thank you for contributing! 🎉
