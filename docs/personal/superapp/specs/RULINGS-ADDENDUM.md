# Cross-stage rulings addendum

Written 11 November 2026 by the orchestrator, after two reconciliation passes over the seven
specifications and an independent re-check. These rulings are binding on every stage and override
any specification text that still disagrees with them. A test author or implementer who finds such
text follows the ruling and says so in the hand-off note.

| # | Ruling |
|---|---|
| A1 | **Settings and Health order.** Top to bottom: Scorecard, Coach packet, Intake, Body record, Events, Niggle log, Recovery context, Timeline. Each **Health row** is present only while its own flag is on. Each **Settings card is always drawn on iPhone**, because it holds that flag's switch. |
| A2 | **Stage 4 internal order.** 4-4a (catalogue), then 4-7 (laboratory units), then stage 1's work package 1-11 (the weigh-in-outranks-scan rule), then 4-4c, 4-5, 4-6 and the hotspot package. Work package 4-7 **creates** `Strand/Data/BodyRecordPresenter.swift` with the editor draft type and 4-5 extends it. In `Strand/Screens/LabBookView.swift` the order is 4-7's "Entered as" line first, then 4-6's CSV scope argument. |
| A3 | **The weigh-in-outranks-scan rule** lives in stage 1 §8.7 (ruling R44): `BodyMeasurementResolver.withoutOutrankedScans(_:asOf:)`, with `BodyMeasurementResolver.weighInSource`. No other specification restates it. It is implemented in stage 4's step, after 4-4a and before any stage 4 edit of the files it touches. |
| A4 | **Debug demo registry.** One registry element per stage, and an element may own several prefixes. Reserved: scorecard's existing unprefixed names; `packet-`; `intake-`; `bodyrecord-`, `scan-`, `compare-`, `bench-`, `labunits-`; `events-`; `niggle-`, `cutstress-`, `timeline-`; `labbook-`. No two elements may claim overlapping prefixes. |
| A5 | **Packet version 2 budget.** `8000 + 290 × rangeDays + PersonalEvents.packetByteAllowance` bytes, as stage 2 §7.12 gives it. Packet v2 is described in stage 2 §7.12 and §14.1. |
| A6 | **One order for every shared file:** Lab Book ownership, stage 2, stage 3, stage 4, stage 5, stage 6, then packet v2. The string catalogue has one writer at a time, and it runs last in each step. |
| A7 | **One Fixture Person** across all stages: stage 1 §13 is the reference for identity, dates, weights and waists. |
| A8 | **No Android work** (stage 1 ruling R43). Where a stage changes a contract shared with Android, the specification states the drift and nothing is written in Kotlin. |
