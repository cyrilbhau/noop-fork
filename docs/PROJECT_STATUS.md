# Project status

Updated on **30 October 2026** against source checkpoint
[`158a5de3`](https://github.com/cyrilbhau/noop-fork/commit/158a5de303be6143a23e725e9b6523088c71fed8),
including Health Steps, independent strap-estimate, device/sync, and widget work. The earlier
publication audit covered [`e600df6a`](https://github.com/cyrilbhau/noop-fork/commit/e600df6a).
This is a development build, with no signed public iPhone release.

## Scope and evidence

The iPhone adaptation starts from upstream NOOP commit
[`8e4b0c16`](https://github.com/ryanbr/noop/commit/8e4b0c16e7640607600fa6bde5424095eba6034e).
At the audited `e600df6a` baseline, the adaptation added 44 commits across 205 files, including
the redesigned iPhone interface, Coach integration, workout imports, and widgets. Those historical
counts exclude the later integration and describe the source delta, not hardware validation.

| Area | Evidence and limits |
|---|---|
| iPhone interface | The redesigned app, including Your Cards and spacing updates, was built, installed in place and launched during development. Today, Sleep, Training, Health, Coach, and Profile are implemented. A classic-interface fallback remains. Acceptance of the latest update remains deferred. |
| Local collection and analytics | Inherited from NOOP. The development focus is WHOOP 4.0. Complete multi-night, locked-phone, workout, and reconnect/backfill acceptance remains open. |
| Coach | ChatGPT replies and retained sign-in were observed during development. API-key and Custom providers remain. Plan eligibility, real token expiry, and scheduled/background briefs need their own checks. |
| Workout imports | Text preview/save/reopen and Health workout-summary import were observed during development. Hevy CSV retains set metadata but skips duplicate start times rather than reconciling edits. |
| Live HealthKit | Reads Steps and workout summaries and blocks Health writes and physiological imports. The owner accepted an earlier Health Steps update; background refresh still needs device acceptance. Export-file imports are separate. |
| Steps | Motion-derived WHOOP 4.0 estimates remain separate even on Health-positive days; reliable phone-free counting has not been demonstrated. A local counted-walk check reports motion coverage and error. Imports and estimates have different provenance and must not be treated as interchangeable measurements. |
| Blood oxygen and temperature | WHOOP 4.0 blood oxygen is shown as not measured. Imported percentages are separate. Temperature conversion is provisional; absolute accuracy is unsupported. |
| Widgets and Live Activities | Implemented and compiled during development. Physical rendering, source labels, refresh timing, and freshness still require device acceptance. |
| Backups | Existing SQLite/`.noopbak` paths are inherited. An iPhone backup/restore rehearsal remains unverified. Restore replaces the database. |
| macOS and Android | Source retained from upstream, with shared Apple compilation considered during development. This adaptation's redesigned interface and Coach subscription connection target iPhone. |
| Other straps and Apple Watch | Inherited device code is not a validation claim for this adaptation. The iPhone scheme embeds widgets and excludes the watch app. |

These observations summarize earlier development records. They are not results of a new device
qualification during the publication cleanup. No new app build, installation, or hardware session
was run for the documentation change.

## Integrated source checkpoint — 30 October 2026

The checkpoint includes Health/Steps source repairs, independent owner-attributed estimates and
their Android twins, the backfill idle policy, widget artwork, and the accompanying documentation.
All 40 changed runtime/build-definition files match the frozen source of the previously signed
and installed update. This is source identity evidence, not fresh Android or hardware validation.
XcodeGen regeneration, whitespace, localization and detached-doc-comment checks passed; no new
application build, test suite, installation or device session was run for this checkpoint.
Further testing and acceptance remain deferred.

The [HRV source-isolation document](personal/HRV-SOURCE-ISOLATION-PLAN.md) remains an implementation
plan. The deferred Your Cards A3–A5 work and the acceptance checks below remain outstanding.

## Before relying on daily collection

Run a local build using [Getting started](GETTING_STARTED.md), then check:

1. Stored history after an ordinary sync, with timestamps and source attribution.
2. Locked-phone collection over several nights, including a workout and a reconnect.
3. Estimated steps against counted phone-free walks and a stationary trial.
4. Widget values and timestamps against the app after a foreground refresh.
5. A private backup and restore on a disposable test installation.

Keep original exports and the existing installation intact during testing. Build success, a live
heart-rate reading, or a plausible score cannot establish those results.

## Distribution and updates

The public-facing documentation is prepared; public redistribution remains pending the permission
review and history privacy decision described below. The current app/widget display name remains
**NOOP Cyril** and the scheme remains **NOOPiOS**. The public project name is **NOOP for iPhone**.

Upstream release badges, screenshots, and installation feeds have been removed from this project's
README because they describe a different build. The inherited in-app release check still queries
upstream NOOP and can be disabled in Settings. It does not deliver this adaptation's updates.

The [publication review](PUBLICATION_REVIEW.md) records the remaining repository-history and
provenance decisions before visibility is changed.
