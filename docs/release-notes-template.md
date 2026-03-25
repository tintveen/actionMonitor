# actionMonitor Release Notes

## Highlights

- Public macOS release of `actionMonitor`
- Browser-based GitHub OAuth sign-in with PKCE and loopback redirect
- Local Keychain storage for packaged app installs
- Homebrew cask metadata included with the release assets

## Install

1. Download `actionMonitor-<version>-macos.zip` from this release.
2. Extract `actionMonitor.app`.
3. Move it to `/Applications`.
4. Launch the app and complete onboarding.

`actionMonitor` is currently distributed as an unsigned app. If macOS blocks it, open **System Settings > Privacy & Security** and allow the app to run, or remove quarantine manually:

```bash
xattr -d com.apple.quarantine "/Applications/actionMonitor.app"
```

## Auth notes

- Public repositories can be monitored without signing in.
- Private repository access currently uses GitHub OAuth App browser sign-in.
- The distributed app should be treated as a public native client. Any shipped client secret is operational configuration, not a security boundary.
