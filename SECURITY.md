# Security Policy

## Supported Versions

We release patches for security vulnerabilities. The following versions are currently supported:

| Version | Supported          |
|---------|--------------------|
| 1.5     | :white_check_mark: |
| < 1.5   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **durand.tibo+gh@gmail.com**

Include the following information:

- Type of issue (e.g., token exposure, injection vulnerability, etc.)
- Full paths of affected source files
- Location of the affected code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### What to Expect

After submitting a vulnerability report:

1. **Acknowledgment**: You'll receive a response within 48 hours acknowledging your report
2. **Assessment**: We'll investigate and assess the vulnerability
3. **Timeline**: We'll keep you informed about our progress
4. **Resolution**: Once fixed, we'll coordinate disclosure timing with you
5. **Credit**: With your permission, we'll credit you in the security advisory

## Security Best Practices

When using this action:

1. **Token Permissions**: Use `GITHUB_TOKEN` with minimal required permissions
    - Required: `actions: write`
    - Recommended: `contents: read`

2. **Pin Action Versions**: Use specific version tags instead of `@main`
   ```yaml
   # Good
   uses: durandtibo/cancel-queued-runs-action@v1.5
   
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
   github_token: ${{ secrets.GITHUB_TOKEN }}  # Good
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
