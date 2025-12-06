# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CONTRIBUTING.md with contribution guidelines
- SECURITY.md with security policy
- CHANGELOG.md for tracking version changes
- Additional documentation sections in README.md

### Changed
- Enhanced README.md with troubleshooting, FAQ, and limitations sections
- Improved inline documentation in scripts/cancel.sh
- Updated action.yaml with more detailed input descriptions
- Cleaned up .gitignore to remove Python-specific entries

## [1.5]

### Features
- Composite action to cancel GitHub Actions workflow runs queued longer than a configurable time
- Configurable maximum queue age (default: 24 hours)
- Cross-platform support (Linux and macOS runners)
- Works with both GNU date and BSD date
- Comprehensive error handling and status logging

### Documentation
- Initial README.md with usage examples
- Code of Conduct
- BSD 3-Clause License

[Unreleased]: https://github.com/durandtibo/cancel-queued-runs-action/compare/v1.5...HEAD
[1.5]: https://github.com/durandtibo/cancel-queued-runs-action/releases/tag/v1.5
