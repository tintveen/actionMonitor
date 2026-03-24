# actionMonitor

![actionMonitor icon](docs/actionMonitor-icon.svg)

`actionMonitor` is a macOS menu bar app for watching GitHub Actions workflows that matter to you. Configure the workflows you want to monitor, connect GitHub in the browser, choose which accessible repositories this Mac can monitor, and get a compact status view from the menu bar.

![actionMonitor screenshot](docs/screenshot.svg)

## Features

- Monitor your own list of GitHub Actions workflows instead of a hardcoded repo list.
- Add, edit, delete, and reorder monitored workflows from the Settings window.
- Guide first-time users through onboarding with welcome, GitHub sign-in, first workflow setup, and a finish screen.
- Sign in with a GitHub OAuth App browser flow for private repositories without manually pasting tokens.
- Load the repositories your signed-in GitHub account can access, then choose which repos actionMonitor should monitor locally.
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

Before you build a live app with GitHub sign-in enabled, set both `GitHubOAuthAppClientID` and `GitHubOAuthAppClientSecret` in `Support/Info.plist` from your GitHub OAuth App. If either value is left blank, the app will still build, but browser sign-in stays disabled.

For local debugging, this plist-based setup is convenient. For a public macOS release, shipping the GitHub OAuth App client secret inside the app bundle is a known risk and should be treated as a temporary or explicitly accepted v1 tradeoff, not a clean long-term secret-management solution.

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
4. In `Connect GitHub`, click `Continue in Browser`.
5. After sign-in, open Settings and confirm the accessible repositories actionMonitor should monitor on this Mac.
6. Add your first workflow with:
   - Display name
   - GitHub owner or organization
   - Repository name
   - Branch
   - Workflow file name or path
   - Optional site URL
7. Finish onboarding, then refresh from the menu bar to fetch the latest workflow run.

If you skip onboarding, the app continues to work, but setup stays incomplete and onboarding will open again on the next launch.

## GitHub OAuth App Setup

1. Create or reuse a GitHub OAuth App.
2. Set the OAuth App homepage URL to `https://github.com/tintveen/actionMonitor`.
3. Set the authorization callback URL to `http://127.0.0.1/callback`.
4. Leave `Enable Device Flow` off.
5. Request the `repo` scope in the browser flow.
6. Copy the app's client ID into `Support/Info.plist` under `GitHubOAuthAppClientID`.
7. Copy the app's client secret into `Support/Info.plist` under `GitHubOAuthAppClientSecret`.
8. Build or install the app again so the bundled metadata includes both values.

During sign-in, `actionMonitor` opens the system browser, listens on a temporary loopback callback such as `http://127.0.0.1:8123/callback`, validates the returned PKCE state, exchanges the code for a GitHub OAuth access token, validates the account with `GET /user`, and stores the session in Keychain.

The browser flow uses a random free loopback port at runtime while keeping the registered callback URL at `http://127.0.0.1/callback`.

In local debug builds, auth diagnostics are written to stderr so you can confirm whether the client ID and client secret were detected, which callback URL was resolved, and which GitHub authorization URL the app attempted to open.

## GitHub Repositories Guidance

- Public repositories usually work without authentication.
- Private repositories work best with GitHub browser sign-in, which stores the resulting OAuth access token in Keychain.
- Repository access follows the signed-in user's actual GitHub access and may still be limited by org OAuth approval or SSO requirements.
- The bundled client secret is the biggest launch risk for a public native app.
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
