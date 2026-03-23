# actionMonitor

![actionMonitor icon](docs/app-icon.svg)

`actionMonitor` is a macOS menu bar app for watching GitHub Actions workflows that matter to you. Configure the repositories and workflow files you want to monitor, sign in with GitHub or save a personal access token in Keychain, and get a compact status view from the menu bar.

![actionMonitor screenshot](docs/screenshot.svg)

## Features

- Monitor your own list of GitHub Actions workflows instead of a hardcoded repo list.
- Add, edit, delete, and reorder monitored workflows from the Settings window.
- Guide first-time users through onboarding with welcome, GitHub sign-in, first workflow setup, and a finish screen.
- Sign in with GitHub through browser OAuth for private repositories without manually pasting tokens.
- Keep a personal access token as a fallback for local builds or edge cases.
- Watch public repositories without authentication, or use GitHub sign-in for private repos and better rate-limit behavior.
- Keep workflow configuration on disk at `~/Library/Application Support/actionMonitor/monitored-workflows.json`.
- Use `--demo` on macOS to launch the app with sample workflows for screenshots or manual QA.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools or Xcode with Swift 6.1 support

## Build And Install

### Install locally

```bash
./scripts/install-local.sh
```

This builds a release app bundle and installs it to `~/Applications/actionMonitor.app`.

Before you build a live app with GitHub sign-in enabled, set both `GitHubOAuthClientID` and `GitHubOAuthClientSecret` in `Support/Info.plist` from your GitHub OAuth App. If either value is left blank, the app will still build, but browser sign-in stays disabled and the personal access token fallback remains available.

### Run from source

```bash
swift run actionMonitor
```

### Launch demo mode

```bash
swift run actionMonitor --demo
```

## First-Run Setup

1. Launch the app.
2. The onboarding window opens automatically until setup is complete.
3. Click `Continue` on the welcome step.
4. In `Connect GitHub`, choose one of these paths:
   - Click `Continue in Browser` for the recommended OAuth flow.
   - Or expand the personal access token fallback if you prefer manual token management.
5. Add your first workflow with:
   - Display name
   - GitHub owner or organization
   - Repository name
   - Branch
   - Workflow file name or path
   - Optional site URL
6. Finish onboarding, then refresh from the menu bar to fetch the latest workflow run.

If you skip onboarding, the app continues to work, but setup stays incomplete and onboarding will open again on the next launch.

## GitHub Sign-In Setup

1. Create or reuse a GitHub OAuth App.
2. Set the OAuth app callback URL to `http://127.0.0.1/oauth/callback`.
3. Copy the app's client ID into `Support/Info.plist` under `GitHubOAuthClientID`.
4. Copy the app's client secret into `Support/Info.plist` under `GitHubOAuthClientSecret`.
5. Build or install the app again so the bundled metadata includes both values.

During sign-in, `actionMonitor` opens the system browser, listens on a temporary loopback callback such as `http://127.0.0.1:8123/oauth/callback`, validates the returned OAuth state, and stores the resulting access token in Keychain.

`actionMonitor` requests the `repo` scope so it can read GitHub Actions workflow runs from private repositories.

## GitHub Access Guidance

- Public repositories usually work without authentication.
- Private repositories work best with browser sign-in, which stores the resulting access token in Keychain.
- A personal access token remains available as a fallback and is also stored in Keychain on macOS.
- Any authenticated path helps avoid stricter anonymous GitHub rate limits.

## Development

### Run tests

```bash
swift test
```

### Remove the local install

```bash
./scripts/uninstall-local.sh
```

## Release Notes

- Source distribution is the supported release format for now.
- The repository includes a macOS CI workflow that runs `swift test` on pushes and pull requests.
- The bundled app version is currently `0.1.0`.
