# Contributing

Thanks for helping improve `actionMonitor`.

## Local setup

1. Install Xcode 16.3+ or the Swift 6.1 command line tools.
2. Clone the repository.
3. Run `swift test`.
4. Install a local app build with `./scripts/install-local.sh`.

If you need private-repository access while developing, keep credentials out of git:

1. Copy `Support/Info.local.example.plist` to `Support/Info.local.plist`, or set `ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_ID` and `ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_SECRET` in your shell.
2. Never commit `Support/Info.local.plist` or any live credentials.

## Before opening a pull request

- Run `swift test`.
- Run `./scripts/check-secrets.sh` if you have `gitleaks` or Docker available.
- Verify docs and install steps still match the current behavior.
- Keep changes focused and explain user-visible impact in the PR description.

## Style notes

- The app targets macOS 14+ and Swift 6.1.
- Prefer small, readable changes over broad refactors.
- If auth, storage, or onboarding behavior changes, add or update tests.
