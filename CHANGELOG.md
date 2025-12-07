# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CHANGELOG.md to track version history and changes
- Enhanced documentation with architecture details

### Changed
- Improved documentation clarity and organization

## [1.7.0]

### Features
- Automatic cancellation of queued workflow runs
- Configurable maximum queue age (in hours)
- Cross-platform support (Linux and macOS)
- Force-cancel capability for extremely old runs
- Comprehensive unit test suite with BATS

### Documentation
- Comprehensive README with examples
- Security policy
- Contributing guidelines
- Code of conduct

---

## Release Notes

### Understanding Version Numbers

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

### How to Upgrade

To upgrade to a new version, update your workflow file:

```yaml
- uses: durandtibo/cancel-queued-runs-action@v1.7
```

Replace `v1.7` with the desired version tag. For production use, always pin to a specific
version rather than using `@main`.

[Unreleased]: https://github.com/durandtibo/cancel-queued-runs-action/compare/v1.7...HEAD
[1.7.0]: https://github.com/durandtibo/cancel-queued-runs-action/releases/tag/v1.7
