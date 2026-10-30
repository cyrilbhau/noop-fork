# Publication review

Review date: **30 October 2026**. Repository: `cyrilbhau/noop-fork`.
Source baseline reviewed: `e600df6a`. Visibility remains **private**.

## Prepared

- Public name: **NOOP for iPhone**, selected by the owner.
- README describes this adaptation's work, source setup, scope, and limitations.
- Upstream downloads, star/release badges, screenshots, and community support promises are removed
  from the landing page.
- Direct upstream and earlier research credits are preserved and clarified.
- Root `LICENSE` and `Required Notice: Copyright 2026 NoopApp` are unchanged.
- Exact license texts are preserved for the six resolved Apple dependencies, including transitives.
- Setup instructions follow the committed baseline and use each developer's own signing identity.
- Issue and security guidance route reports to this adaptation and discourage sharing private data.
- Ignore rules cover environment variants, exported signing material, and local agent worktrees.
- GitHub About text and topics identify the iPhone adaptation, and its own issue tracker is enabled.

GitHub reports `fork: false`, with no parent/source repository. This is already a standalone GitHub
repository; its code still derives from NOOP and that lineage remains credited.

## Resolve before changing visibility

### Inherited source permission

Source comparison confirms implementation lineage through `ryanbr/noop` from
[`johnmiddleton12/wearable`](https://github.com/johnmiddleton12/wearable), formerly `my-whoop`.
Three current source files have the same Git blobs as that project's published revision
`890e0c96beb817ab0cec3aaf7d9a06c530025355`:

- [WhoopProtocol/Schema.swift](https://github.com/johnmiddleton12/wearable/blob/890e0c96beb817ab0cec3aaf7d9a06c530025355/Packages/WhoopProtocol/Sources/WhoopProtocol/Schema.swift)
- [WhoopProtocol/Values.swift](https://github.com/johnmiddleton12/wearable/blob/890e0c96beb817ab0cec3aaf7d9a06c530025355/Packages/WhoopProtocol/Sources/WhoopProtocol/Values.swift)
- [WhoopStore/Cursors.swift](https://github.com/johnmiddleton12/wearable/blob/890e0c96beb817ab0cec3aaf7d9a06c530025355/Packages/WhoopStore/Sources/WhoopStore/Cursors.swift)

Nine source/resource blobs matched at NOOP's initial import. The earlier vendored/adapted credits
therefore reflect observed source lineage; the inherited blanket facts-only/no-code-copied account
does not describe all of the code.

No `LICENSE`, `COPYING`, or `NOTICE` file was found in that referenced project's current tree,
and its repository metadata reports no license. Its disclaimer describes personal/educational use;
a redistribution grant or separate permission has **not been verified**. Resolve the applicable
terms or permission for the inherited source before public source or binary redistribution.
NOOP's license does not establish permission to relicense another author's code. GitHub's
[licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
explains the distinction between a public repository and a license grant.

### Personal commit metadata and handoffs

The available history includes **56 owner-authored commits with a personal email address**,
including the source baseline. Values are deliberately omitted from this report.
Current and historical personal handoffs also contain local checkout paths, planning/subscription
dates, installation acceptance, and owner preferences.

Choose one publication strategy:

1. **Separate sanitized public history:** keep this development repository private and prepare a
   source snapshot for a separate public repository. Omit private handoffs, old binaries, local
   configuration, and shared signing material; preserve licenses, credits, and the exact upstream
   baseline. Use a GitHub noreply address for its commits.
2. **Retain the existing history:** explicitly accept that all reachable historical email addresses,
   personal notes, branches, and tags become public. Editing current files does not remove old copies.

A cleanup branch or pull request does not sanitize the repository's other refs. No history has been
rewritten, no branch/tag removed, and no visibility changed by this preparation.

## Other findings

### Android test signing identity

`android/fork-debug.keystore` contains a private signing key protected by the standard Android
debug password, which is present in the build configuration. It was inherited and is deliberately
used for test/staging artifacts; it is not a verified production credential. Treat the signing
identity as public and untrusted. See [SECURITY.md](../SECURITY.md).

The current real-release build guard requires separate signing configuration. For a sanitized
public snapshot, omit this key and let local debug builds generate local keys. Changing an identity
can affect updates to existing Android installations; no signing key was rotated here.

### Historical binaries

Seven old `dist/NOOP-v2.8.2…2.8.8-macos.zip` blobs remain in history. No such release artifact is
tracked in the current tree. Archive entry checks found app signatures but no embedded provisioning
profiles or obvious personal-data entry names. This is historical release baggage, not a demonstrated
private-key or health-data leak.

### Branches, updates, and distribution

The default branch is `personal/iphone-baseline`. Existing CI workflows largely filter for
upstream's `main`; the absence of checks here is not a passing build. Adapt those filters before
relying on pull-request CI for application changes.

The in-app release checker and inherited release feeds still refer to upstream NOOP. Public docs
explain that distinction. No release workflow was dispatched and no binary was published.

## Verification and limits

The audit examined the tracked tree, available refs, **18,844 text blobs** (approximately 1.36 GB),
and **3,330 commit messages**. Targeted patterns found no GitHub/AWS/OpenAI credential-format
matches, PEM private keys, JWTs, or concrete Apple UDIDs. No private measured health records were
confirmed in the personal notes. The binary Android test key was checked separately and is
documented above.

This is a targeted audit of available local history, not proof that every credential or sensitive
artifact is absent. Remote-only refs and artifacts were not exhaustively inspected. The scan counts
describe the pre-cleanup source; the documentation commit will add further blobs.

Documentation checks cover relative links, issue-template YAML, ignore rules, preserved license
texts, and whitespace. Source helper commands and feature claims were checked against the
committed baseline. No new application build, installation, or Bluetooth validation was performed.
The existing dirty app/test/personal-note changes were left separate from this preparation.

The later 30 October WIP checkpoint integrates those app/test changes and updates current setup
and status documentation for Health Steps support. This report's source-lineage and historical
privacy audit remains scoped to `e600df6a`; the integration is not a new history audit or permission
decision. Repository visibility remains private.
