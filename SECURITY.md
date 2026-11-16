# Security Policy

## Supported Versions

We release patches for security vulnerabilities. The following versions are currently supported:

| Version | Supported          |
| ------- | ------------------ |
| 2.0     | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

The `cancel-queued-runs-action` team takes security bugs seriously. We appreciate your efforts to
responsibly disclose your findings.

### Where to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities privately using
[GitHub Security Advisories](https://github.com/durandtibo/cancel-queued-runs-action/security/advisories/new).

### What to Expect

- We will acknowledge receipt of your report within **5 business days**.
- We will provide an initial assessment (including whether the report is accepted, and an
  estimated timeline for a fix) within **10 business days** of acknowledgment.

### What to Include

Please include the following information in your report:

- Type of issue (e.g., token exposure, injection vulnerability, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

This information will help us triage your report more quickly.

### Security Update Policy

- Security updates will be released as soon as possible
- Security updates will be clearly marked in release notes
- We will notify users through GitHub releases and other appropriate channels

## Security Best Practices

When using this action:

1. **Token Permissions**: Use `GITHUB_TOKEN` with minimal required permissions
   - Required: `actions: write`
   - Recommended: `contents: read`

2. **Pin Action Versions**: Use specific version tags instead of `@main`

   ```yaml
   # Good
   uses: durandtibo/cancel-queued-runs-action@v1.9

   # Avoid
   uses: durandtibo/cancel-queued-runs-action@main
   ```

3. **Review Permissions**: Always review and limit workflow permissions

   ```yaml
   permissions:
     actions: write
     contents: read
   ```

4. **Secrets Management**: Never hardcode tokens; always use GitHub secrets

   ```yaml
   github_token: ${{ secrets.GITHUB_TOKEN }} # Good
   ```

## Known Limitations

- This action requires `actions:write` permission to cancel workflow runs
- The action can only cancel runs in the repository it's configured for
- Very old workflow runs (several months old) may fail to cancel due to GitHub API limitations

## Dependencies

This action uses:

- GitHub CLI (`gh`) - pre-installed on GitHub Actions runners
- Standard Unix utilities (`bash`, `jq`, `date`)

We rely on GitHub-hosted runners' maintained environment and do not bundle external dependencies.
