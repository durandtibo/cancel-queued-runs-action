# Contributing to cancel-queued-runs-action

Thank you for your interest in contributing to this project! We welcome contributions from the community.

## How to Contribute

### Reporting Issues

If you encounter a bug or have a feature request:

1. Check the [existing issues](https://github.com/durandtibo/cancel-queued-runs-action/issues) to see if it has already been reported
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
export MAX_AGE_HOURS=24

# Run the script
./scripts/cancel.sh
```

### Testing Multiple Repositories

For testing across multiple repositories:

1. Add repository names to `dev/repos.txt` (one per line in `owner/name` format)
2. Run: `./dev/run_for_repos.sh`

## Code Style

- Follow shell scripting best practices
- Use shellcheck to validate scripts
- Add comments for complex logic
- Keep functions small and focused

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](../CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Questions?

If you have questions, feel free to:
- Open an issue for discussion
- Reach out to the maintainers

Thank you for contributing! 🎉
