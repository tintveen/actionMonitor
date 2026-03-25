# Security Policy

## Supported versions

Only the latest tagged release and the current `main` branch are supported for security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub Security Advisories:

- [Report a vulnerability](https://github.com/tintveen/actionMonitor/security/advisories/new)

Do not open a public issue for credential leaks, auth bypasses, or token handling bugs.

## OAuth credential and token handling

`actionMonitor` is a distributed native macOS client. Any OAuth client secret shipped in the app bundle must be treated as recoverable and is not a security boundary.

Current design assumptions:

- Browser-based GitHub OAuth App sign-in
- Authorization code flow with PKCE
- Loopback redirect on `127.0.0.1`
- User tokens stored locally via the macOS Keychain for packaged app installs

## Secret leak response runbook

If a GitHub OAuth client secret or other live credential is exposed:

1. Revoke or rotate the leaked credential immediately in the upstream provider.
2. Remove the secret from the current branch.
3. Rewrite git history or cut a fresh public repository history so the leaked value is not retained in published commits.
4. Re-run `./scripts/check-secrets.sh`.
5. Publish a patched release and invalidate any affected tokens if needed.
