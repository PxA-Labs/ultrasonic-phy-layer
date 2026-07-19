# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Bug Fixes

- **ci:** Skip Flutter/CMake steps when project files don't exist yet
- **ci:** Repair changelog workflow download and extraction
- **ci:** Replace manual download with official git-cliff action
- **ci:** Resolve git-cliff URL via GitHub API instead of pinned action
- **ci:** Remove invalid sort_commits value in cliff.toml
- **ci:** Replace job-level hashFiles with step-level checks to fix CI parsing
- Macos missing stdlib.h, msvc __attribute__ guard, lint-pr permissions, remove dep-review
- Ci triggers and workflow stability
- Conditional -lm for non-Windows, missing stdlib.h in test_css_demodulate
- Add missing stdlib.h in test_cfo/ofdm_modulate/ofdm_demodulate, pass --config Release for MSVC multi-config generator
- Export DLL symbols on Windows via SW_BUILD_DLL compile definition
- Build static lib on Windows to avoid DLL symbol export issues
- Lcov coverage — use --ignore-errors for missing gcda files, fix path
- Remove over-broad lcov exclude patterns that stripped all records
- Replace broken action-semantic-pull-request with inline validation script

### CI

- Add GitHub Actions workflows (CI, Build, Release, Dependabot)
- Add auto-changelog with git-cliff
- Add benchmarking, cross-platform matrix, coverage, static analysis, and PR linting
- Retrigger workflows [skip ci]
- Retrigger workflows
- Add benchmarking, cross-platform matrix, coverage, static analysis, and PR linting

### Documentation

- Update MIT License and add mathematical model of physical layer
- Upgrade README with badges, acoustic channel data insights, and math models
- Add core developers and project organization
- Add production documents (PRD, tech stack, CI/CD, roadmap)
- Move MATHEMATICAL_MODEL.md to docs/ and update README links
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Add SECURITY.md (#45)
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Remove emojis from README headings (#47)
- Update CHANGELOG.md [skip ci]

### Features

- Add project skeleton for native C DSP library and Flutter app
- Professional CI/CD pipeline with cross-platform matrix, benchmarks, coverage, and static analysis (#46)

### Maintenance

- Change license from MIT to Apache 2.0
- Merge main into feat/ci-benchmarking


