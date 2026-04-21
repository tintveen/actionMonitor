# Public Launch Checklist

## Before making the repository public

- Rotate the GitHub OAuth App secret that was previously committed.
- Push the scrubbed history, not the old secret-bearing history.
- Verify `Support/Info.plist` is blank for OAuth credentials.
- Run `./scripts/check-secrets.sh`.
- Run `swift test`.
- Build a fresh release archive with `./scripts/package-release.sh`.

## GitHub repository metadata

- Description: `Menu bar app for monitoring GitHub Actions workflows on macOS`
- Topics: `macos`, `swift`, `swiftui`, `github-actions`, `menu-bar`, `devtools`
- Social preview image: use the real screenshot once it is available

## Release assets

- Upload `dist/actionMonitor-<version>-macos.zip`
- Upload `dist/actionmonitor.rb`
- Upload `dist/release-metadata.txt`
- Copy the generated SHA-256 into `tintveen/homebrew-tap` or any other external Homebrew tap if you move the cask there

## Post-release checks

- Download the zip on a clean Mac and confirm the app launches
- Verify browser sign-in still works
- Verify Homebrew cask install works from the published cask location
