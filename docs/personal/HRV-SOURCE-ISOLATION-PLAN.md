# HRV source isolation implementation plan

30 October 2026, Asia/Kolkata. Status: proposed implementation; application code is unchanged.

HRV readings and their comparisons must retain the provider, statistic and sampling method that produced them. Switching between WHOOP, Apple Health or another provider must not silently change the meaning of an HRV history, personal range or recovery explanation. Implement one shared resolution model in Swift and Kotlin, then use it across Recovery, Today, Health and HRV detail views.

## Confirmed behavior and scope

- The normal WHOOP dashboard and Charge baseline read imported and computed WHOOP buckets separately from Apple Health. Apple recovery already folds earlier Apple observations independently. The audit does not establish that Apple SDNN currently contaminates the normal WHOOP Charge score. See [Repository](../../Strand/Data/Repository.swift) `refresh` and [IntelligenceEngine](../../Strand/Data/IntelligenceEngine.swift) `watchRecoveries`.
- The generic resolver declares WHOOP `hrv` compatible with Apple `hrv`, allowing one resolved series to contain both methods. Health also retains the source of its selected value while folding a history chosen across sources. See `appleCompatibleKey` in [Repository](../../Strand/Data/Repository.swift) and [VitalSignsSummary](../../Strand/Screens/VitalSignsSummary.swift).
- The redesigned Recovery model pairs a merged `avgHrv` with the current shared baseline. Its factors have no HRV identity. A carried score can also receive the selected day's sleep input rather than the carried night's input. See [ScoreDetailData](../../StrandiOS/Redesign/ScoreDetailData.swift).
- Recovery explanations reconstruct NOOP contribution points even when the displayed score came from WHOOP. An imported vendor score cannot be explained by rerunning NOOP's formula. The classic HRV insight also considers later observations when viewing historical dates. See [ChargeBreakdownWiring](../../Strand/Screens/ChargeBreakdownWiring.swift) and `hrvBaselineDeltaPct` in [TodayView](../../Strand/Screens/TodayView.swift).
- Android Health Connect averages RMSSD readings but writes compatibility daily rows into `my-whoop`. A namespace alone therefore does not prove historical provenance. See [HealthConnectImporter](../../android/app/src/main/java/com/noop/ingest/HealthConnectImporter.kt).

The personal iPhone build's automatic Health sync imports only steps and workouts. Preserve this restriction and its blocked Health writes. Manual Apple XML and Shortcuts imports remain separate routes through which HRV can enter the store; include both in the repair and regression fixtures.

## HRV identity

Introduce a pure `HRVSeriesIdentity` and `HRVObservation` model in the shared analytics layer, with a Kotlin twin. Each observation carries its effective day, value in milliseconds, storage namespace and identity. The identity contains a logical provider, statistic and versioned sampling protocol.

| Input | Statistic | Protocol distinction |
| --- | --- | --- |
| WHOOP export | RMSSD | Vendor sleep summary |
| NOOP computation | RMSSD | Actual configured sleep window, aggregation and recipe revision |
| Apple Health XML or physiological sync | SDNN | Daily aggregate of Health samples |
| Health Connect | RMSSD | Daily aggregate of Health Connect samples |
| Manual or legacy input without proven method | Unknown | Unknown |

WHOOP exposes its recovery HRV as `hrv_rmssd_milli`; HealthKit's `heartRateVariabilitySDNN` represents SDNN. These are separate statistics. [WHOOP documentation](https://developer.whoop.com/docs/developing/user-data/recovery/), [Apple documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn).

Matching units or statistics alone do not establish compatibility. Health Connect daily RMSSD and WHOOP overnight RMSSD remain separate series. Imported WHOOP and NOOP computations remain distinguishable even when both use RMSSD. A change between NOOP sleep-window modes must change the protocol identity.

Do not infer method from value magnitude, `avgSdnn`, a `-noop` suffix or current settings. WHOOP rows can contain both RMSSD and SDNN. Apple Health is a data provider and does not by itself establish that an Apple Watch produced a reading. Label existing combined-provider data as an aggregate; do not claim original-device separation where import aggregation has already discarded it. Preserving individual upstream writers is a separate extension.

Normalize only proven aliases of the same physical provider. Readding the same strap must not fragment its history, while unrelated straps or providers must not merge because their names look similar.

## Persistence and legacy data

Use the existing [scoreInputProvenance](../../Packages/WhoopStore/Sources/WhoopStore/ScoreInputProvenanceStore.swift) table for metric key `hrv` and the actual input provider. Add a nullable, versioned HRV method identifier through a new GRDB migration and matching Room migration. The identifier maps to the statistic and sampling protocol above. Keep `sourceId` as a provider identifier; device cleanup and provider lookup already depend on that meaning.

Persist HRV values and identity atomically on every authoritative importer and computation path. Cover WHOOP CSV, Apple XML, live Health physiology when enabled, Shortcuts, wearable imports and Health Connect. Shortcuts must declare or reliably establish the HRV method; generic `hrv` alone remains unknown. For Health Connect, always retain its authoritative HRV series under `health-connect`, including overlap days. Any compatibility rows retained for other metrics must not become proven WHOOP HRV.

To retain signed contribution chips for new NOOP scores, persist a small versioned recovery explanation payload alongside the recovery provenance in the same transaction. A nullable payload column on the existing provenance row is sufficient. It must contain the effective day, actual input identities, relevant input values, baseline states, seed policy, recipe revision and numeric driver outputs identified by stable term keys. Produce it during scoring; do not store localized text or reconstruct it from mutable settings later. The saved recovery and explanation must succeed or roll back together.

Existing values and vendor scores remain intact. Backfill metadata only from durable evidence or authoritative recomputation/reimport. Do not classify old `my-whoop` rows from their namespace, sparse shape or overlap with Health Connect. Legacy readings with unknown identity remain visible, but cannot receive a guessed method-specific range or numeric score attribution. An old backup without the new fields must open with those fields absent.

Recompute the active analysis window where retained raw inputs can establish identity. Older history does not require a full rewrite. Preserve existing legacy RR snapshots without stamping them with today's window setting. Before changing the owner's installed build, use an authoritative WHOOP export or retained raw inputs in a disposable fixture to establish how existing useful comparisons will be recovered. An unavailable legacy range should say that its method is unavailable, rather than imply a measured health change or reset the stored score.

## Baseline and explanation rules

1. A raw HRV personal range, delta, calibration count and chart statistic use only the selected series identity. Another source's data cannot fill a missing reading or advance that series' calibration.
2. Preserve the existing explicit WHOOP vendor seed policy for computed Charge: a 21-calendar-day window, imported values winning overlap while seeding, and handoff at 14 valid own nights. Whitelist its WHOOP RMSSD protocols. Apple SDNN, Health Connect daily RMSSD, unknown methods and unrelated vendors cannot enter that seed pool. Identify a seeded score baseline as import-seeded.
3. Distinguish a raw series' personal range from the baseline that actually produced a recovery score. In the score explanation, use the saved score baseline and disclose seeding. In HRV detail, use the exact series' own range. Do not present the two as the same quantity during handoff.
4. Preserve the existing strap calibration gates, Apple/source-only recovery gates, staleness rules and recalibration epochs. Keep the separate seven-valid-observation recovery gate where it currently applies.
5. Resolve the winning score and its effective day before selecting factors. Carrying yesterday's score carries yesterday's inputs and context. A historical descriptive range uses eligible observations no later than the effective day; it cannot read future days. An exact score explanation uses its saved snapshot instead of a newly folded range.
6. Imported vendor scores show attributed observed factors and available ranges, without NOOP contribution chips. Legacy computed scores without a matching explanation payload also omit those chips. Raw values remain available.

## Implementation sequence

### 1 Establish failing fixtures

Add mixed-method and mixed-provider fixtures before changing production behavior. Reproduce a mismatch whose numbers fall inside the current 0.5x to 2x suppression guard, a carried score with a different selected-day sleep input, and imported recovery incorrectly receiving NOOP points. Pin established WHOOP-only scoring and seed handoff outputs as regression fixtures.

### 2 Add identity and persistence

Implement the pure identity types and compatibility policy, then the nullable storage additions and typed explanation payload. Add migrations, schema-oracle updates, rollback and backup coverage on both platforms. Extend the existing provenance transaction rather than adding an independent metadata write. Keep storage work separately reviewable from the UI changes.

### 3 Repair ingestion and resolution

Stamp identity at the source adapters, before merging or rehoming loses it. Retain independent source histories. Remove `hrv` from generic WHOOP-to-Apple fallback in Swift, Kotlin and the local-access resolver. Also stop the independent Apple-preferred fallback to Health Connect for HRV: it currently joins Apple SDNN and Health Connect RMSSD, including when Apple data arrives through an import or restored backup on Android. Give consumers that need multiple HRV sources a typed grouped result rather than a flat sequence of numbers. Audit callers of the old `.values` projection and of merged `avgHrv`; other metric fallback behavior stays as it is.

Version the HRV policy in the analysis watermark or add a durable repair marker so the raw-data watermark cannot skip the upgrade. Include relevant method/policy revisions in day-cache signatures. A repair marker clears only after successful atomic persistence. Metadata-only changes must invalidate repository, series and view caches even when scalar values are unchanged.

### 4 Wire the product surfaces

Create one resolved HRV comparison object containing the observation, effective day, identity, matching history/range, calibration state and optional score context. Use it in the redesigned Recovery factors, shared Charge breakdown, Liquid and classic Today insights, Health band/sparkline, Trends and HRV detail.

Show concise source and method text such as `WHOOP import · RMSSD` or `Apple Health · SDNN`; include window detail where it changes interpretation. Allow independent series to remain inspectable and do not connect incompatible points into one continuous line or pool their summary statistics. Reuse the existing VO2 method-break pattern where appropriate.

Factor taps must preserve the selected series and effective date. Extend the source-aware metric route/catalog so a requested Apple HRV detail cannot silently fall back to the first WHOOP HRV catalog entry. Extract Recovery factor construction into a shared pure helper so macOS-hosted app tests exercise the iPhone model's decisions.

### 5 Validate and prepare delivery

Run the focused suites below, both Apple app builds and Android verification in an equipped environment. Inspect real rendered states using synthetic records. Prepare the implementation for review with its schema, analytics and UI changes clearly separated. Device installation is a later delivery action; this plan does not require changing the working app or its populated database.

## Acceptance cases

| Case | Required result |
| --- | --- |
| Add or change Apple SDNN beside WHOOP RMSSD | WHOOP range, count, delta and eligible score inputs remain unchanged; reciprocal assertion for Apple |
| Same-day records from both providers | Both original series survive; each displayed value retains its own identity |
| Plausible numeric overlap between incompatible methods | Isolation still applies even when a magnitude guard would accept the comparison |
| Selected source lacks HRV | No borrowing from a different statistic or protocol |
| WHOOP to Apple to WHOOP selection | Each series restores its own history and range |
| WHOOP and Health Connect both use RMSSD | Daily aggregate and overnight series remain separate |
| Apple SDNN and Health Connect RMSSD coexist after Android import or restore | Apple-preferred HRV cannot silently borrow Health Connect values; both series remain inspectable |
| WHOOP vendor seed at 13 and 14 valid own nights | Existing handoff policy and established WHOOP-only outputs are preserved |
| Change NOOP sleep-window mode | Context changes and caches invalidate; old observations keep their recorded method |
| Historical or carried score | Factors use the effective score day; later data cannot enter a historical descriptive range |
| Imported vendor score or legacy score without context | Observations remain visible; no fabricated signed contribution points |
| Unknown legacy provenance | No guessed method or range; raw values and stored scores survive |
| Failed metadata/value transaction | Neither half is published; retry remains possible |
| Metadata-only update, restore or same-strap alias change | Correct refresh, provenance retention and stable alias grouping |
| Personal automatic Health sync | Steps/workouts restriction and blocked Health writes remain enforced |

## Verification

Extend existing `ChargeBaselinesTests`, `WatchRecoveryTests`, `ChargeBreakdownWiringTests`, `TodayHrvBaselineDeltaTests`, `VitalSourceResolutionTests`, carry tests, provenance store tests and migration/backup suites. Add a pure resolver suite and HRV chart segmentation tests following `Vo2MaxTrendProvenanceTests`. Cover Apple XML, Shortcuts and Health Connect adapter behavior directly.

Generate Swift oracle outputs for identity grouping, eligibility, tie-breaking and seed handoff; use identical literals in Kotlin tests. Run targeted Swift package and macOS-hosted `StrandTests` suites. Compile both `Strand` and `NOOPiOS` with the personal widget graph. Run the focused Android JVM suites and full Kotlin compilation; report unavailable toolchains as unrun checks rather than passes. Package tests do not validate the iPhone screen.

Render WHOOP-only, Apple-only, mixed-source, unknown legacy, calibrating, carried and historical states, including large Dynamic Type and source-specific navigation. A repeatable automated fixture must establish isolation; visual inspection alone cannot establish numerical correctness.

Implementation must preserve the dirty checkout's existing steps and device/sync work, personal app identity, saved history, credentials and Health consent boundaries. The repair does not change BLE commands, firmware, HRV formulas or vendor scores. It changes which observations may be compared and makes score explanations traceable to their actual inputs.
