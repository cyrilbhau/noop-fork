// API ASSUMED BY THESE TESTS
//
// New, in Strand/Data/CoachPacketModel.swift and Strand/Data/CoachPacketPresenter.swift
// (specification §8.5 and §9.1; shared code, so it compiles for macOS):
//
//     struct CoachPacketCopyPlan: Equatable {
//         static let lifetimeSeconds: TimeInterval = 600
//         let text: String
//         let copiedAt: Date
//         var expiresAt: Date { copiedAt.addingTimeInterval(Self.lifetimeSeconds) }
//         var localOnly: Bool { true }
//     }
//     protocol CoachPacketPasteboardWriting { func write(_ plan: CoachPacketCopyPlan) }
//
//     @MainActor final class CoachPacketModel: ObservableObject {
//         enum State: Equatable { case idle, loading, ready(CoachPacketDocument), blocked, unavailable }
//         enum CopyState: Equatable { case none, copied(expiresAt: Date) }
//         @Published private(set) var state: State                 // .idle until the first load
//         @Published private(set) var copyState: CopyState         // .none until a copy
//         @Published private(set) var isRegenerating: Bool         // NOT IN §8.5, see behaviour 2
//         var clipboardHoldsEarlierPacket: Bool { get }            // NOT IN §8.5, see behaviour 5
//
//         init(assemble: @escaping @MainActor () async -> CoachPacketOutcome,
//              settings: CoachPacketSettings, pasteboard: CoachPacketPasteboardWriting,
//              now: @escaping () -> Date = { Date() })
//         func load() async
//         func setSection(_ section: CoachPacketSection, on: Bool) async
//         func setRangeDays(_ days: Int) async
//         func copy()
//         var shareText: String? { get }
//     }
//
//     /// What the packet sheet draws for one state of the model (§10.2). Pure.
//     struct CoachPacketSheetPresentation: Equatable {
//         enum Body: Equatable {
//             case skeleton                               // loading
//             case preview(text: String, dimmed: Bool)    // the exact text; dimmed while regenerating
//             case message(String)                        // blocked or unavailable
//         }
//         var body: Body
//         var statusLine: String?         // the size line, or the copied confirmation that replaces it
//         var caption: String?            // one of: stale clipboard, every section off, nothing measured
//         var scorecardCaption: String?   // under the Scorecard and Weigh-ins switches
//         var showsCopyAndShare: Bool     // false when blocked or unavailable: no text exists
//         var copyAndShareEnabled: Bool
//         var showsRetry: Bool            // "Try again", only when blocked or unavailable
//     }
//     extension CoachPacketPresenter {
//         static func sheet(state: CoachPacketModel.State, copyState: CoachPacketModel.CopyState,
//                           isRegenerating: Bool, clipboardHoldsEarlierPacket: Bool,
//                           scorecardEnabled: Bool, timeZone: TimeZone,
//                           locale: Locale) -> CoachPacketSheetPresentation
//     }
//
// The presenter's strings used below are assumed at the top of CoachPacketPresenterTests.swift.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `load()` with the flag off sets `.idle` and never calls `assemble`. From `.idle` a load
//     publishes `.loading` before it suspends. The flag is read from the `settings` given.
//  2. REGENERATING (§10.2: "the previous preview stays, dimmed, until the new one arrives; actions
//     disabled meanwhile"). A load that starts while the state is `.ready` leaves that state in
//     place and sets `isRegenerating` until its outcome is published. While it is true `shareText`
//     is nil and `copy()` does nothing: the text on screen no longer matches the stored choices.
//  3. `setSection` and `setRangeDays` store the choice before they suspend, clear `copyState`,
//     and reload. With the flag off they store nothing new to read and assemble nothing.
//  4. `copy()` reads `now()` once. Its plan's `copiedAt` is that reading.
//  5. STALE CLIPBOARD (§10.2: "the clipboard still holds the earlier text until it expires").
//     `clipboardHoldsEarlierPacket` is true when a copy was made, a section or the range changed
//     after it, and `now()` is before that copy's `expiresAt`. A new copy makes it false.
//  6. A load that ends `.blocked` or `.unavailable` clears nothing on the pasteboard and leaves
//     `copyState` as it was; `shareText` is nil and `copy()` does nothing.
//  7. Caption precedence, from the approved frames (design/round-s2-coach-packet/README.md,
//     decision 7): stale clipboard, then every section off, then nothing measured. One at most.
//  8. Blocked and unavailable draw no Copy and no Share (README decision 5), only "Try again".
//  9. Larger than the budget (§10.2, "not reachable by construction"): the status line differs
//     from the ordinary size line, still carries the size and the range, and the actions stay
//     enabled. Its wording is a proposal of the design round and is not pinned.
// 10. `CoachPacketDocument.nothingMeasured` as assumed at the top of CoachPacketAssemblerTests.swift.
//
// Not reachable from this target: `SystemCoachPacketPasteboard` and `GetCoachPacketIntent` are
// iPhone-only files. The writer is pinned through the protocol, the plan it is handed and the
// source scan; the action through `testTheIntentPathAndTheSheetPathReturnTheSameText`, which calls
// the one function the action returns, and through the source scan.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 2 (coach packet), specification §8.5, §9.1, §9.3, §10.2 and §12.3: the sheet model, every
// state of the sheet, the pasteboard plan and the Shortcuts path. Written before the
// implementation exists. Synthetic values only.

/// Records every plan it is handed. No real pasteboard is touched.
private final class PasteboardSpy: CoachPacketPasteboardWriting {
    private(set) var plans: [CoachPacketCopyPlan] = []
    func write(_ plan: CoachPacketCopyPlan) { plans.append(plan) }
}

/// Holds an assembly until the test lets it finish.
@MainActor
private final class Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { continuations.count }
    func wait() async { await withCheckedContinuation { continuations.append($0) } }
    func open() {
        let held = continuations
        continuations = []
        held.forEach { $0.resume() }
    }
}

/// The outcomes `assemble` returns, in order, and how often it was called.
@MainActor
private final class AssembleScript {
    private var steps: [(outcome: CoachPacketOutcome, gate: Gate?)] = []
    private(set) var calls = 0
    func then(_ outcome: CoachPacketOutcome, gate: Gate? = nil) { steps.append((outcome, gate)) }
    func run() async -> CoachPacketOutcome {
        calls += 1
        guard !steps.isEmpty else {
            XCTFail("assemble was called more often than the test scripted")
            return .unavailable
        }
        let step = steps.removeFirst()
        if let gate = step.gate { await gate.wait() }
        return step.outcome
    }
}

@MainActor
final class CoachPacketModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var settings: CoachPacketSettings!
    private var script: AssembleScript!
    private var pasteboard: PasteboardSpy!
    private var clock: CoachPacketBox<Date>!
    private let suites = CoachPacketSuites()

    private static let generatedAt = Date(timeIntervalSince1970: 1_931_409_730)     // 2031-03-16T06:42:10Z
    private static let plusOne = TimeZone(secondsFromGMT: 3_600)!
    private static let british = Locale(identifier: "en_GB")

    override func setUp() {
        super.setUp()
        suiteName = "CoachPacketModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = CoachPacketSettings(defaults: defaults)
        settings.isEnabled = true
        script = AssembleScript()
        pasteboard = PasteboardSpy()
        clock = CoachPacketBox(Self.generatedAt.addingTimeInterval(20))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suites.removeAll()
        super.tearDown()
    }

    private func model() -> CoachPacketModel {
        let script = script!, clock = clock!
        return CoachPacketModel(assemble: { await script.run() }, settings: settings, pasteboard: pasteboard,
                                now: { clock.read() })
    }

    private func document(_ marker: String, rangeDays: Int = 14,
                          sections: Set<CoachPacketSection> = Set(CoachPacketSection.allCases),
                          nothingMeasured: Bool = false, byteCount: Int? = nil) -> CoachPacketDocument {
        let text = CoachPacketText.sample(marker)
        return CoachPacketDocument(text: text, byteCount: byteCount ?? text.utf8.count, generatedAt: Self.generatedAt,
                                   rangeDays: rangeDays, sections: sections, nothingMeasured: nothingMeasured)
    }

    private func present(_ model: CoachPacketModel, scorecardEnabled: Bool = true) -> CoachPacketSheetPresentation {
        CoachPacketPresenter.sheet(state: model.state, copyState: model.copyState,
                                   isRegenerating: model.isRegenerating,
                                   clipboardHoldsEarlierPacket: model.clipboardHoldsEarlierPacket,
                                   scorecardEnabled: scorecardEnabled, timeZone: Self.plusOne, locale: Self.british)
    }

    /// Starts `work` and returns once an assembly is held at `gate`.
    private func start(_ gate: Gate, _ work: @escaping @MainActor () async -> Void,
                       file: StaticString = #filePath, line: UInt = #line) async -> Task<Void, Never> {
        let before = gate.waiting
        let task = Task { @MainActor in await work() }
        for _ in 0..<10_000 where gate.waiting == before { await Task.yield() }
        XCTAssertEqual(gate.waiting, before + 1, "the assembly never started", file: file, line: line)
        return task
    }

    /// A model that has loaded `document`.
    private func ready(_ document: CoachPacketDocument) async -> CoachPacketModel {
        script.then(.ready(document))
        let model = model()
        await model.load()
        XCTAssertEqual(model.state, .ready(document))
        return model
    }

    // MARK: - Flag off

    func testFlagOffStaysIdleAndReadsNothing() async {
        settings.isEnabled = false
        let model = model()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.copyState, .none)
        await model.load()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(script.calls, 0, "with the flag off nothing is assembled, so nothing is read")
        XCTAssertNil(model.shareText)
        model.copy()
        XCTAssertEqual(pasteboard.plans, [], "with the flag off nothing reaches the pasteboard")
        XCTAssertEqual(model.copyState, .none)

        await model.setSection(.activity, on: false)
        await model.setRangeDays(7)
        XCTAssertEqual(script.calls, 0)
        XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(present(model).copyAndShareEnabled)
    }

    func testSwitchingTheFlagOffReturnsAReadyModelToIdle() async {
        let model = await ready(document("A"))
        settings.isEnabled = false
        await model.load()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(script.calls, 1, "the second load assembled nothing")
        XCTAssertNil(model.shareText)
        model.copy()
        XCTAssertEqual(pasteboard.plans, [])
    }

    // MARK: - Loading and ready

    func testLoadPublishesReady() async {
        let gate = Gate()
        let first = document("A")
        script.then(.ready(first), gate: gate)
        let model = model()
        XCTAssertEqual(model.state, .idle)

        let task = await start(gate) { await model.load() }
        XCTAssertEqual(model.state, .loading, "the first load shows the skeleton while it assembles")
        XCTAssertFalse(model.isRegenerating, "there is no earlier preview to keep")
        XCTAssertNil(model.shareText)
        var sheet = present(model)
        XCTAssertEqual(sheet.body, .skeleton)
        XCTAssertTrue(sheet.showsCopyAndShare, "the actions are visible while loading")
        XCTAssertFalse(sheet.copyAndShareEnabled, "and disabled")
        XCTAssertFalse(sheet.showsRetry)
        model.copy()
        XCTAssertEqual(pasteboard.plans, [], "nothing to copy while loading")

        gate.open()
        await task.value
        XCTAssertEqual(model.state, .ready(first))
        XCTAssertEqual(model.copyState, .none)
        XCTAssertEqual(script.calls, 1)
        sheet = present(model)
        XCTAssertEqual(sheet.body, .preview(text: first.text, dimmed: false), "the preview is the exact text")
        XCTAssertEqual(sheet.statusLine, CoachPacketPresenter.sizeLine(byteCount: first.byteCount, rangeDays: 14,
                                                                       locale: Self.british))
        XCTAssertNil(sheet.caption)
        XCTAssertNil(sheet.scorecardCaption)
        XCTAssertTrue(sheet.showsCopyAndShare && sheet.copyAndShareEnabled)
        XCTAssertFalse(sheet.showsRetry)
    }

    func testAnOvertakenLoadPublishesNothing() async {
        let gate = Gate()
        let slow = document("slow"), fast = document("fast")
        script.then(.ready(slow), gate: gate)
        script.then(.ready(fast))
        let model = model()

        let overtaken = await start(gate) { await model.load() }
        await model.load()
        XCTAssertEqual(model.state, .ready(fast))

        gate.open()
        await overtaken.value
        XCTAssertEqual(model.state, .ready(fast), "a load that finishes after a later one began publishes nothing")
        XCTAssertFalse(model.isRegenerating)
        XCTAssertEqual(model.shareText, fast.text)
        XCTAssertEqual(script.calls, 2)
    }

    func testAnOvertakenBlockedOutcomeDoesNotReplaceAReadyOne() async {
        let gate = Gate()
        let fast = document("fast")
        script.then(.blocked(findings: 2), gate: gate)
        script.then(.ready(fast))
        let model = model()
        let overtaken = await start(gate) { await model.load() }
        await model.load()
        gate.open()
        await overtaken.value
        XCTAssertEqual(model.state, .ready(fast))
    }

    /// §10.2 "Reopened later": a fresh packet each time the sheet opens. Nothing is cached.
    func testEveryLoadAssemblesAgain() async {
        let first = document("A"), second = document("B")
        let model = await ready(first)
        script.then(.ready(second))
        await model.load()
        XCTAssertEqual(script.calls, 2)
        XCTAssertEqual(model.state, .ready(second))
        XCTAssertEqual(model.shareText, second.text)
    }

    // MARK: - Sections and range

    func testChangingASectionStoresReloadsAndClearsTheCopiedState() async {
        let first = document("A")
        let second = document("B", sections: [.scorecard, .weighIns, .recoverySleep, .trends])
        let model = await ready(first)
        model.copy()
        XCTAssertEqual(pasteboard.plans.count, 1)
        guard case .copied = model.copyState else { return XCTFail("\(model.copyState)") }

        script.then(.ready(second))
        await model.setSection(.activity, on: false)
        XCTAssertEqual(settings.sections, [.scorecard, .weighIns, .intake, .recoverySleep, .trends, .events],
                       "the choice is stored")
        XCTAssertEqual(script.calls, 2, "and the packet is assembled again")
        XCTAssertEqual(model.state, .ready(second))
        XCTAssertEqual(model.copyState, .none, "the confirmation clears")
        XCTAssertEqual(pasteboard.plans.count, 1, "changing a control writes nothing to the pasteboard")
    }

    func testChangingTheRangeStoresReloadsAndClearsTheCopiedState() async {
        let model = await ready(document("A"))
        model.copy()
        let week = document("B", rangeDays: 7)
        script.then(.ready(week))
        await model.setRangeDays(7)
        XCTAssertEqual(settings.rangeDays, 7)
        XCTAssertEqual(script.calls, 2)
        XCTAssertEqual(model.state, .ready(week))
        XCTAssertEqual(model.copyState, .none)
        XCTAssertEqual(present(model).statusLine,
                       CoachPacketPresenter.sizeLine(byteCount: week.byteCount, rangeDays: 7, locale: Self.british))
    }

    /// The choice is in the settings before the assembly starts, so the assembly reads it.
    func testTheChoiceIsStoredBeforeTheAssemblyRuns() async {
        let model = await ready(document("A"))
        let gate = Gate()
        script.then(.ready(document("B")), gate: gate)
        let task = await start(gate) { await model.setSection(.trends, on: false) }
        XCTAssertFalse(settings.sections.contains(.trends), "stored before the reload suspends")
        gate.open()
        await task.value
    }

    func testRegeneratingKeepsThePreviousPreviewDimmedAndDisablesTheActions() async {
        let first = document("A"), second = document("B", rangeDays: 7)
        let model = await ready(first)
        let gate = Gate()
        script.then(.ready(second), gate: gate)

        let task = await start(gate) { await model.setRangeDays(7) }
        XCTAssertEqual(model.state, .ready(first), "the previous preview stays until the new one arrives")
        XCTAssertTrue(model.isRegenerating)
        XCTAssertNil(model.shareText, "the text on screen is not the text for the stored choices")
        model.copy()
        XCTAssertEqual(pasteboard.plans, [], "Copy is disabled while regenerating")
        var sheet = present(model)
        XCTAssertEqual(sheet.body, .preview(text: first.text, dimmed: true))
        XCTAssertTrue(sheet.showsCopyAndShare)
        XCTAssertFalse(sheet.copyAndShareEnabled)

        gate.open()
        await task.value
        XCTAssertEqual(model.state, .ready(second))
        XCTAssertFalse(model.isRegenerating)
        XCTAssertEqual(model.shareText, second.text)
        sheet = present(model)
        XCTAssertEqual(sheet.body, .preview(text: second.text, dimmed: false))
        XCTAssertTrue(sheet.copyAndShareEnabled)
    }

    func testASectionSwitchedOffIsNamedByTheNewPreview() async throws {
        // Through the real assembler: the header of the regenerated text names the section.
        let h = try await CoachPacketHarness.fixturePerson(scorecard: true, suites: suites)
        let assembler = h.assembler()
        let now = h.clock.now
        let model = CoachPacketModel(assemble: { await assembler.assemble() }, settings: h.packetSettings,
                                     pasteboard: pasteboard, now: { now })
        await model.load()
        let before = try XCTUnwrap(model.shareText)
        XCTAssertTrue(before.contains("switched-off: none\n"), before)

        await model.setSection(.activity, on: false)
        let after = try XCTUnwrap(model.shareText)
        XCTAssertTrue(after.contains("switched-off: activity\n"), after)
        XCTAssertFalse(after.contains("== ACTIVITY =="))
        guard case let .ready(document) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(document.sections, [.scorecard, .weighIns, .intake, .recoverySleep, .trends, .events])
        XCTAssertEqual(present(model).body, .preview(text: after, dimmed: false))
    }

    // MARK: - Copy

    func testCopyWritesExactlyThePreviewedText() async {
        let first = document("A")
        let model = await ready(first)
        // A later assembly would give other text. Copy must not ask for it.
        script.then(.ready(document("B")))
        model.copy()
        XCTAssertEqual(script.calls, 1, "copy does not assemble again: what was previewed is what leaves")
        XCTAssertEqual(pasteboard.plans.map(\.text), [first.text])
        XCTAssertEqual(pasteboard.plans.first.map { Data($0.text.utf8) }, Data(first.text.utf8), "byte for byte")
        XCTAssertEqual(model.state, .ready(first), "copying changes nothing that is previewed")
    }

    func testCopyPlanIsLocalOnlyAndExpiresInTenMinutes() async throws {
        XCTAssertEqual(CoachPacketCopyPlan.lifetimeSeconds, 600)
        let copiedAt = Date(timeIntervalSince1970: 1_931_409_750)
        let plan = CoachPacketCopyPlan(text: "fixture", copiedAt: copiedAt)
        XCTAssertTrue(plan.localOnly, "the item is never offered to another device")
        XCTAssertEqual(plan.expiresAt, copiedAt.addingTimeInterval(600))
        XCTAssertEqual(plan.expiresAt.timeIntervalSince(plan.copiedAt), 600)

        // The plan the model hands the writer is that plan, for the one clock reading.
        let model = await ready(document("A"))
        let reads = clock.reads
        model.copy()
        XCTAssertEqual(clock.reads, reads + 1, "one clock reading per copy")
        let written = try XCTUnwrap(pasteboard.plans.first, "copy handed the writer nothing")
        XCTAssertEqual(written, CoachPacketCopyPlan(text: CoachPacketText.sample("A"), copiedAt: clock.value))
        XCTAssertTrue(written.localOnly)
        XCTAssertEqual(written.expiresAt, clock.value.addingTimeInterval(600))
    }

    func testTheShownExpiryIsThePlansExpiry() async throws {
        let model = await ready(document("A"))
        // A clock that moves on after every reading: a second reading would give another time.
        clock.afterRead = { $0 = $0.addingTimeInterval(90) }
        model.copy()
        let plan = try XCTUnwrap(pasteboard.plans.first, "copy handed the writer nothing")
        XCTAssertEqual(model.copyState, .copied(expiresAt: plan.expiresAt),
                       "the time the sheet shows and the time given to the system are one value")

        // Copied 20 seconds after 07:42:10 in the sheet's zone: it leaves at 07:52.
        let sheet = present(model)
        XCTAssertEqual(sheet.statusLine, "Copied to this iPhone only. It leaves the clipboard at 07:52.")
        XCTAssertEqual(sheet.statusLine, CoachPacketPresenter.copied(expiresAt: plan.expiresAt, timeZone: Self.plusOne,
                                                                     locale: Self.british))
        XCTAssertEqual(sheet.body, .preview(text: plan.text, dimmed: false), "the preview stays as it was")
        XCTAssertTrue(sheet.copyAndShareEnabled)
        XCTAssertNil(sheet.caption)
    }

    func testASecondCopyHandsOverASecondPlanWithItsOwnExpiry() async throws {
        let model = await ready(document("A"))
        model.copy()
        clock.value = clock.value.addingTimeInterval(240)
        model.copy()
        XCTAssertEqual(pasteboard.plans.count, 2)
        let second = try XCTUnwrap(pasteboard.plans.last)
        XCTAssertEqual(second.copiedAt, clock.value)
        XCTAssertEqual(model.copyState, .copied(expiresAt: second.expiresAt))
        XCTAssertFalse(model.clipboardHoldsEarlierPacket, "no control changed, so nothing is stale")
    }

    func testCopiedThenAControlChangedSaysTheClipboardHoldsTheEarlierPacket() async throws {
        let first = document("A"), second = document("B", sections: [.scorecard, .weighIns, .recoverySleep, .activity])
        let model = await ready(first)
        XCTAssertFalse(model.clipboardHoldsEarlierPacket)
        model.copy()
        XCTAssertFalse(model.clipboardHoldsEarlierPacket, "the clipboard holds the packet on screen")
        let expiry = try XCTUnwrap(pasteboard.plans.first, "copy handed the writer nothing").expiresAt

        script.then(.ready(second))
        await model.setSection(.trends, on: false)
        XCTAssertEqual(model.copyState, .none)
        XCTAssertTrue(model.clipboardHoldsEarlierPacket)
        XCTAssertEqual(pasteboard.plans.map(\.text), [first.text], "the earlier text is still what was written")
        var sheet = present(model)
        XCTAssertEqual(sheet.caption, CoachPacketPresenter.staleClipboard)
        XCTAssertEqual(sheet.statusLine, CoachPacketPresenter.sizeLine(byteCount: second.byteCount, rangeDays: 14,
                                                                       locale: Self.british),
                       "the size line is back in place of the confirmation")
        XCTAssertEqual(sheet.body, .preview(text: second.text, dimmed: false))

        // Until it expires, and no longer.
        clock.value = expiry.addingTimeInterval(-1)
        XCTAssertTrue(model.clipboardHoldsEarlierPacket)
        clock.value = expiry.addingTimeInterval(1)
        XCTAssertFalse(model.clipboardHoldsEarlierPacket)
        XCTAssertNil(present(model).caption)

        // A new copy puts the packet on screen on the clipboard: nothing is stale.
        clock.value = Self.generatedAt.addingTimeInterval(60)
        model.copy()
        XCTAssertFalse(model.clipboardHoldsEarlierPacket)
        sheet = present(model)
        XCTAssertNil(sheet.caption)
        XCTAssertEqual(pasteboard.plans.last?.text, second.text)
    }

    // MARK: - Share

    func testShareTextIsThePreviewedText() async {
        let first = document("A")
        let model = await ready(first)
        script.then(.ready(document("B")))
        XCTAssertEqual(model.shareText, first.text)
        XCTAssertEqual(model.shareText, first.text, "asking twice gives the same text")
        XCTAssertEqual(script.calls, 1, "sharing does not assemble again")
        XCTAssertEqual(pasteboard.plans, [], "sharing does not write the pasteboard")
        XCTAssertEqual(model.copyState, .none)
        XCTAssertEqual(present(model).body, .preview(text: first.text, dimmed: false),
                       "the sheet beneath the share sheet is unchanged")
    }

    // MARK: - Every section off, nothing measured, scorecard off

    func testCopyAndShareAreUnavailableWithEverySectionOff() async {
        let empty = document("header and notes", sections: [])
        let model = await ready(empty)
        XCTAssertNil(model.shareText)
        model.copy()
        XCTAssertEqual(pasteboard.plans, [])
        XCTAssertEqual(model.copyState, .none)

        let sheet = present(model)
        XCTAssertEqual(sheet.body, .preview(text: empty.text, dimmed: false), "header and notes are still shown")
        XCTAssertEqual(sheet.caption, CoachPacketPresenter.everySectionOff)
        XCTAssertTrue(sheet.showsCopyAndShare)
        XCTAssertFalse(sheet.copyAndShareEnabled)
    }

    func testNothingMeasuredIsCaptionedAndStillCopies() async {
        let dashes = document("dashes", nothingMeasured: true)
        let model = await ready(dashes)
        var sheet = present(model)
        XCTAssertEqual(sheet.caption, CoachPacketPresenter.nothingMeasured)
        XCTAssertEqual(sheet.body, .preview(text: dashes.text, dimmed: false), "the packet is still valid")
        XCTAssertTrue(sheet.copyAndShareEnabled)
        XCTAssertEqual(model.shareText, dashes.text)
        model.copy()
        XCTAssertEqual(pasteboard.plans.map(\.text), [dashes.text])

        // Every section off outranks nothing measured: one caption at most.
        script.then(.ready(document("off", sections: [], nothingMeasured: true)))
        await model.load()
        sheet = present(model)
        XCTAssertEqual(sheet.caption, CoachPacketPresenter.everySectionOff)
    }

    func testScorecardOffInTheAppIsCaptionedUnderItsSwitches() async {
        let model = await ready(document("A"))
        XCTAssertNil(present(model, scorecardEnabled: true).scorecardCaption)
        let sheet = present(model, scorecardEnabled: false)
        XCTAssertEqual(sheet.scorecardCaption, CoachPacketPresenter.scorecardOff)
        XCTAssertNil(sheet.caption, "it is not one of the three captions under the size line")
        XCTAssertTrue(sheet.copyAndShareEnabled, "the packet says so in its own sections and may still leave")
    }

    // MARK: - Blocked and unavailable

    func testBlockedAndUnavailableOfferNoText() async {
        for (outcome, state, message) in [
            (CoachPacketOutcome.blocked(findings: 3), CoachPacketModel.State.blocked, CoachPacketPresenter.blocked),
            (CoachPacketOutcome.unavailable, CoachPacketModel.State.unavailable, CoachPacketPresenter.unavailable),
        ] {
            script = AssembleScript()
            pasteboard = PasteboardSpy()
            script.then(outcome)
            let model = model()
            await model.load()
            XCTAssertEqual(model.state, state)
            XCTAssertNil(model.shareText, "no text exists to share")
            model.copy()
            XCTAssertEqual(pasteboard.plans, [], "no text exists to copy")
            XCTAssertEqual(model.copyState, .none)

            let sheet = present(model)
            XCTAssertEqual(sheet.body, .message(message), "no preview")
            XCTAssertNil(sheet.statusLine)
            XCTAssertFalse(sheet.showsCopyAndShare)
            XCTAssertFalse(sheet.copyAndShareEnabled)
            XCTAssertTrue(sheet.showsRetry)

            // "Try again" is a load.
            let recovered = document("recovered")
            script.then(.ready(recovered))
            await model.load()
            XCTAssertEqual(model.state, .ready(recovered))
            XCTAssertEqual(script.calls, 2)
            XCTAssertFalse(present(model).showsRetry)
        }
    }

    /// A packet that turns out blocked after a change replaces the earlier preview: text that may
    /// not leave is not left on screen with its actions.
    func testAReadyPacketThatBecomesBlockedShowsNoPreview() async {
        let model = await ready(document("A"))
        script.then(.blocked(findings: 1))
        await model.setSection(.scorecard, on: true)
        XCTAssertEqual(model.state, .blocked)
        XCTAssertFalse(model.isRegenerating)
        XCTAssertNil(model.shareText)
        model.copy()
        XCTAssertEqual(pasteboard.plans, [])
        XCTAssertEqual(present(model).body, .message(CoachPacketPresenter.blocked))
    }

    // MARK: - Larger than the budget

    func testAPacketLargerThanTheBudgetSaysSoAndKeepsItsActions() async {
        let budget = CoachPacket.byteBudget(rangeDays: 14)
        let within = await ready(document("A", byteCount: budget))
        XCTAssertEqual(present(within).statusLine,
                       CoachPacketPresenter.sizeLine(byteCount: budget, rangeDays: 14, locale: Self.british),
                       "exactly the budget is within it")

        script = AssembleScript()
        let over = document("A", byteCount: budget + 1)
        let model = await ready(over)
        let sheet = present(model)
        let ordinary = CoachPacketPresenter.sizeLine(byteCount: budget + 1, rangeDays: 14, locale: Self.british)
        let line = sheet.statusLine
        XCTAssertNotEqual(line, ordinary, "the size line says the packet is larger than expected")
        XCTAssertTrue(line?.contains("14.1 kB") ?? false, "\(String(describing: line))")
        XCTAssertTrue(line?.contains("14") ?? false, "\(String(describing: line))")
        XCTAssertTrue(sheet.copyAndShareEnabled, "the actions stay enabled")
        XCTAssertEqual(model.shareText, over.text)
    }

    // MARK: - The Shortcuts action

    /// The action returns `CoachPacketAssembler.live()?.assemble()` and nothing else (§9.3): the
    /// function the sheet's model is given. For one state and one clock both give the same text,
    /// and the action's path never reaches the pasteboard.
    func testTheIntentPathAndTheSheetPathReturnTheSameText() async throws {
        let h = try await CoachPacketHarness.fixturePerson(scorecard: true, suites: suites)
        h.packetSettings.setSection(.trends, on: false)
        h.packetSettings.rangeDays = 28
        let assembler = h.assembler(scale: .whoop)

        // The sheet.
        let now = h.clock.now
        let model = CoachPacketModel(assemble: { await assembler.assemble() }, settings: h.packetSettings,
                                     pasteboard: pasteboard, now: { now })
        await model.load()
        let previewed = try XCTUnwrap(model.shareText)

        // The action: the same function, with the same stored sections and range. No parameters.
        let returned = try await h.document(assembler).text
        XCTAssertEqual(returned, previewed)
        XCTAssertEqual(Data(returned.utf8), Data(previewed.utf8))
        XCTAssertTrue(returned.contains("switched-off: trends\n"), "the stored section choice")
        XCTAssertTrue(returned.contains("(28 days; "), "the stored range")
        XCTAssertEqual(pasteboard.plans, [], "neither path wrote the pasteboard; only the sheet's Copy does")

        // Copy in the sheet then hands over exactly that text.
        model.copy()
        XCTAssertEqual(pasteboard.plans.map(\.text), [returned])
    }
}
