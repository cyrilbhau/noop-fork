# Contributing to NOOP for iPhone

This repository develops an iPhone adaptation of [NOOP](https://github.com/ryanbr/noop).
Read [AGENTS.md](AGENTS.md) for repository rules and the
[extended contributor guide](docs/CONTRIBUTING.md) for architecture, Bluetooth safety, design
tokens, and cross-platform contracts. [Getting started](docs/GETTING_STARTED.md) covers a local
iPhone build with a separate app identity.

## Scope

The adaptation focuses on iPhone UI, workout workflows, Coach, and widgets. The inherited macOS
and Android implementations remain in the tree. Shared Apple sources must compile for both
Apple targets. Protocol, analytics, persistence, and backup changes must preserve the applicable
Swift/Kotlin parity contracts.

Keep upstream and third-party credits intact. Contributions retain the repository's
[PolyForm Noncommercial 1.0.0 terms](LICENSE); dependency code retains its own license.
New copied code, assets, fonts, or protocol references need an identified origin and applicable
terms. See [ATTRIBUTION.md](ATTRIBUTION.md) and [NOTICE](NOTICE).

## Validate the change

Use checks that cover the code changed. Run package tests for package changes, compile **NOOPiOS**
for iPhone code, and compile **Strand** when shared Apple sources change. Android logic needs its
corresponding JVM checks. Package tests alone do not compile the apps.

For a quick protocol check:

```bash
cd Packages/WhoopProtocol
swift build
swift test
```

For the local unsigned iPhone Simulator build, after configuring the unique app identity:

```bash
bash Tools/personal/ios.sh build
```

The existing workflow files contain upstream `main` branch filters. Until those filters are adapted
to this repository's default branch, a pull request here may not trigger all checks. Record the
commands actually run and their results; an absent check is not a passing check.

Bluetooth, background delivery, widget freshness, and backup/restore require real-device checks.
State what was observed and what remains unverified. Scoring changes need the evidence described in
[the validation protocol](docs/VALIDATION_PROTOCOL.md).

## Send a change or report a problem

Keep each pull request focused and fill in the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
Describe the resulting behavior, verification, and known limitations. Reference upstream issues
with full URLs so a local issue number is not mistaken for an upstream report.

Use [this repository's issues](https://github.com/cyrilbhau/noop-fork/issues) for the adaptation.
Include the source commit, iOS version, strap model, steps to reproduce, and whether the redesigned
or classic interface is active. A minimal reproduction or synthetic example is preferable to a
personal data export. Review diagnostic excerpts for tokens, device identifiers, names, locations,
and health data before sharing. Full health exports, backups, and unreviewed logs do not belong in
public issues. See [SECURITY.md](SECURITY.md) for sensitive findings.

Upstream NOOP maintains its own community and release channels. Contributors to this adaptation
should not expect upstream maintainers to support its additions.

Do not commit generated Xcode projects, build output, local signing configuration, private keys,
provisioning profiles, databases, or personal exports. The committed Swift package lockfile is
intentional. Follow the [Code of Conduct](CODE_OF_CONDUCT.md) in project discussions.
