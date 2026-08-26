# Contributing to Mist

Thanks for taking an interest in Mist. This is a small, focused macOS project, and clear bug reports, compatibility fixes, tests, and documentation improvements are especially useful.

## Before you start

- Read the [README](README.md) and check existing issues and pull requests.
- For a larger change, open an issue first so the direction can be discussed.
- Please keep changes focused. Avoid introducing a dependency unless there is a strong, documented reason.

## Local development

Requirements:

- macOS 14.0+
- Swift 6.0+ or Xcode 16+

Clone and verify the project:

```bash
git clone https://github.com/thr-33/Mist.git
cd Mist
swift test
```

Build a local app bundle with:

```bash
./scripts/build-app.sh
open dist/Mist.app
```

## Pull requests

1. Create a branch from `main`.
2. Make the smallest change that solves the problem.
3. Add or update tests for behavior changes.
4. Run `swift test` and, when the app bundle is affected, `./scripts/build-app.sh`.
5. Update the README or other documentation when user-facing behavior changes.
6. Describe the problem, the solution, and verification steps in the pull request.

The GitHub Actions test workflow must pass before merge. Reviewers may ask for a focused follow-up rather than a broad refactor.

## Reporting bugs

Please include:

- macOS version and Mac architecture
- Mist commit or version
- a minimal Markdown example, if relevant
- steps to reproduce and what you expected versus what happened
- screenshots or crash output when useful

Use the bug report template when opening an issue. Do not include private or sensitive document contents.

## Code style

Follow the surrounding Swift style and prefer clear, native Foundation/AppKit/SwiftUI solutions. Keep parser and renderer behavior covered by tests. Do not commit generated `dist/`, `.build/`, or local design artifacts.

## Code of conduct

By participating, you agree to keep discussions respectful, constructive, and welcoming. Please report serious or private concerns to the repository maintainer rather than posting sensitive details publicly.
