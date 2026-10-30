# Security policy

NOOP for iPhone is maintained separately from upstream NOOP. It stores strap readings and imports
locally and operates no backend or telemetry service. Relevant boundaries include Bluetooth frames,
SQLite storage, file imports, optional Coach requests, and provider credentials. The inherited
release check contacts GitHub by default. See the
[network inventory](docs/PRIVACY_SECURITY.md#11-network-paths-canonical-inventory) for details.

## Reporting a vulnerability

If **Security → Report a vulnerability** is available on
[this repository](https://github.com/cyrilbhau/noop-fork), use it for a private report. Availability
depends on the repository's private vulnerability reporting setting.

If private reporting is unavailable, open an issue containing a short, non-exploitable description
of the affected component and impact. Request a private reporting route before sharing exploit
details, credentials, or personal data. Do not attach health exports, backups, tokens, or unreviewed
device logs to a public issue.

A useful report identifies the source commit, affected platform, reproduction conditions, impact,
and any suggested fix. There is no guaranteed response time. Fixes target the current maintained
source; older local builds need to be rebuilt to receive them.

Report dependency vulnerabilities to the relevant dependency maintainers as well; the
[Apple dependency inventory](LICENSES/README.md) identifies the pinned packages.

## Signing and local configuration

Each iPhone build uses its developer's own ignored bundle-prefix and signing configuration. Never
commit certificates with private keys, provisioning profiles, OAuth sessions, API keys, or health
data. Keep exports outside the checkout. An ignore rule does not remove a file from existing Git
history.

`android/fork-debug.keystore` is an inherited, committed **public test signing identity**, with its
standard debug password in the build configuration. Treat that key as public: it establishes no
publisher authenticity and must never sign a trusted production release. The Android build guards
real release builds behind separate local signing configuration. Its presence in history is
recorded in the [publication review](docs/PUBLICATION_REVIEW.md).
