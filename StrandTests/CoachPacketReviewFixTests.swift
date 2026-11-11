// API ASSUMED BY THESE TESTS (stage 2 review fixes, rulings A20 and A21)
//
//     @MainActor struct CoachPacketAssembler {
//         init(..., identifiers: @escaping () -> [String]?)   // read once per assemble(); nil blocks
//     }
//
// The rest is the API assumed at the top of CoachPacketAssemblerTests.swift and
// CoachPacketModelTests.swift. Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// Ruling A20 through the assembler: one reading of the identifier list, an unreadable list blocks
/// the packet, and the scan sees free text before it is sanitised and cut.
@MainActor
final class CoachPacketAssemblerReviewFixTests: XCTestCase {
    private typealias H = CoachPacketHarness
    private let suites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func assembler(_ h: H, identifiers: @escaping () -> [String]?) -> CoachPacketAssembler {
        let now = h.clock.now
        return CoachPacketAssembler(repository: h.repo, provider: h.provider, scorecardSettings: h.scorecardSettings,
                                    settings: h.packetSettings, now: { now }, timeZone: { H.utc },
                                    effortScale: { .hundred }, identifiers: identifiers)
    }

    private func isBlocked(_ outcome: CoachPacketOutcome) -> Bool {
        if case .blocked = outcome { return true }
        return false
    }

    // MARK: Finding 2: the identifier list fails closed and is read once

    func testAnUnreadableIdentifierListBlocksThePacket() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let reads = CoachPacketBox(0)
        let outcome = await assembler(h, identifiers: { reads.value += 1; return nil }).assemble()
        XCTAssertTrue(isBlocked(outcome), "no identifier list means no packet: \(outcome)")
        XCTAssertEqual(reads.value, 1)
    }

    func testTheIdentifierListIsReadOnceAndThatReadingIsTheOneScanned() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        h.seedPhaseAndRules(name: "Fixture cut")
        let reads = CoachPacketBox(0)
        // Readable at the first call only: a second reading would scan with nothing.
        let outcome = await assembler(h, identifiers: {
            reads.value += 1
            return reads.value == 1 ? ["Fixture cut"] : nil
        }).assemble()
        XCTAssertTrue(isBlocked(outcome), "\(outcome)")
        XCTAssertEqual(reads.value, 1, "one assembly reads the identifier list once")
    }

    // MARK: Finding 3: an identifier in the form the packet prints it

    func testAnIdentifierWithADoubledSpaceIsFoundInTheNameAsPrinted() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        h.seedPhaseAndRules(name: "Fixture Band cut")
        let outcome = await assembler(h, identifiers: { ["Fixture  Band"] }).assemble()
        XCTAssertTrue(isBlocked(outcome), "\(outcome)")
    }

    // MARK: Finding 4: a value cut by the free-text limit

    func testASensitiveValueCutByTheFreeTextLimitStillBlocksThePacket() async throws {
        let nickname = "Fixture Person's Strap"
        let planted = ["Cut block planned with fixture.person@example-mail.com",
                       "Spring cut, numbers taken from \(nickname)",
                       "Phase one of the cut 12345678-1234-1234-1234-123456789ABC"]
        for value in planted {
            let asPhase = try await H.fixturePerson(scorecard: true, suites: suites)
            asPhase.seedPhaseAndRules(name: value)
            let phaseOutcome = await assembler(asPhase, identifiers: { [nickname] }).assemble()
            XCTAssertTrue(isBlocked(phaseOutcome), "phase \(value): \(phaseOutcome)")

            let asSport = try await H.fixturePerson(scorecard: true, suites: suites)
            _ = try await asSport.store.upsertWorkouts(
                [asSport.workout(-2, hour: 10, minute: 0, sport: value, source: "manual", minutes: 25, avgHr: nil,
                                 kcal: nil, distanceM: nil)], deviceId: H.deviceId)
            let sportOutcome = await assembler(asSport, identifiers: { [nickname] }).assemble()
            XCTAssertTrue(isBlocked(sportOutcome), "sport \(value): \(sportOutcome)")
        }

        let harmless = try await H.fixturePerson(scorecard: true, suites: suites)
        harmless.seedPhaseAndRules(name: "A long and entirely harmless phase name for the spring cut block")
        let outcome = await assembler(harmless, identifiers: { [nickname] }).assemble()
        guard case .ready = outcome else { return XCTFail("a harmless long name is still a packet: \(outcome)") }
    }
}

// MARK: - Ruling A21

/// Records every plan it is handed. No real pasteboard is touched.
private final class ReviewPasteboardSpy: CoachPacketPasteboardWriting {
    private(set) var plans: [CoachPacketCopyPlan] = []
    func write(_ plan: CoachPacketCopyPlan) { plans.append(plan) }
}

/// Returns the scripted outcomes in order.
@MainActor
private final class ReviewAssembleScript {
    private var outcomes: [CoachPacketOutcome] = []
    func then(_ outcome: CoachPacketOutcome) { outcomes.append(outcome) }
    func run() -> CoachPacketOutcome {
        guard !outcomes.isEmpty else {
            XCTFail("assemble was called more often than the test scripted")
            return .unavailable
        }
        return outcomes.removeFirst()
    }
}

/// Ruling A21: "Copied" means the text on screen. A reload that shows different text clears it;
/// the stale-clipboard caption stays tied to a changed control.
@MainActor
final class CoachPacketModelReviewFixTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var settings: CoachPacketSettings!
    private var script: ReviewAssembleScript!
    private var pasteboard: ReviewPasteboardSpy!
    private var clock: CoachPacketBox<Date>!

    private static let generatedAt = Date(timeIntervalSince1970: 1_931_409_730)     // 2031-03-16T06:42:10Z

    override func setUp() {
        super.setUp()
        suiteName = "CoachPacketModelReviewFixTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = CoachPacketSettings(defaults: defaults)
        settings.isEnabled = true
        script = ReviewAssembleScript()
        pasteboard = ReviewPasteboardSpy()
        clock = CoachPacketBox(Self.generatedAt.addingTimeInterval(20))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func model() -> CoachPacketModel {
        let script = script!, clock = clock!
        return CoachPacketModel(assemble: { script.run() }, settings: settings, pasteboard: pasteboard,
                                now: { clock.read() })
    }

    private func document(_ marker: String) -> CoachPacketDocument {
        let text = CoachPacketText.sample(marker)
        return CoachPacketDocument(text: text, byteCount: text.utf8.count, generatedAt: Self.generatedAt,
                                   rangeDays: 14, sections: Set(CoachPacketSection.allCases), nothingMeasured: false)
    }

    private func present(_ model: CoachPacketModel) -> CoachPacketSheetPresentation {
        CoachPacketPresenter.sheet(state: model.state, copyState: model.copyState,
                                   isRegenerating: model.isRegenerating,
                                   clipboardHoldsEarlierPacket: model.clipboardHoldsEarlierPacket,
                                   scorecardEnabled: true, timeZone: TimeZone(secondsFromGMT: 3_600)!,
                                   locale: Locale(identifier: "en_GB"))
    }

    /// What the sheet draws for `document` when nothing was copied.
    private func uncopied(_ document: CoachPacketDocument) -> CoachPacketSheetPresentation {
        CoachPacketPresenter.sheet(state: .ready(document), copyState: .none, isRegenerating: false,
                                   clipboardHoldsEarlierPacket: false, scorecardEnabled: true,
                                   timeZone: TimeZone(secondsFromGMT: 3_600)!, locale: Locale(identifier: "en_GB"))
    }

    /// A model showing A that copied it.
    private func copiedA() async -> CoachPacketModel {
        script.then(.ready(document("A")))
        let model = model()
        await model.load()
        model.copy()
        XCTAssertNotEqual(model.copyState, .none)
        return model
    }

    func testCopiedThenAReloadWithDifferentTextSaysTheClipboardHoldsTheEarlierPacket() async {
        let model = await copiedA()
        clock.value = clock.value.addingTimeInterval(180)          // back from another app, inside ten minutes
        script.then(.ready(document("B")))
        await model.load()
        XCTAssertEqual(model.state, .ready(document("B")))
        XCTAssertEqual(model.copyState, .none, "the copied confirmation names text no longer on screen")
        XCTAssertEqual(pasteboard.plans.map(\.text), [document("A").text])
        // The sheet is the one for B with no copy: no confirmation beside text that was not copied.
        XCTAssertEqual(present(model), uncopied(document("B")))
    }

    func testCopiedThenBlockedThenTryAgainWithDifferentTextClearsTheConfirmation() async {
        let model = await copiedA()
        script.then(.blocked(findings: 1))
        await model.load()
        XCTAssertEqual(model.state, .blocked)
        script.then(.ready(document("B")))
        await model.load()
        XCTAssertEqual(model.copyState, .none)
        XCTAssertEqual(pasteboard.plans.count, 1, "nothing but the one copy reached the pasteboard")
        XCTAssertEqual(present(model), uncopied(document("B")))
    }

    func testCopiedThenAReloadWithTheSameTextKeepsTheConfirmation() async {
        let model = await copiedA()
        let copied = model.copyState
        script.then(.ready(document("A")))
        await model.load()
        XCTAssertEqual(model.copyState, copied)
        XCTAssertNotEqual(present(model), uncopied(document("A")), "the confirmation is still shown")
    }

    func testANewCopyAfterTheReloadConfirmsTheNewText() async {
        let model = await copiedA()
        script.then(.ready(document("B")))
        await model.load()
        model.copy()
        XCTAssertNotEqual(model.copyState, .none)
        XCTAssertFalse(model.clipboardHoldsEarlierPacket)
        XCTAssertEqual(pasteboard.plans.map(\.text), [document("A").text, document("B").text])
        // And a reload that brings back A, which is no longer on the clipboard, clears it again.
        script.then(.ready(document("A")))
        await model.load()
        XCTAssertEqual(model.copyState, .none)
        XCTAssertEqual(present(model), uncopied(document("A")))
    }

    func testAChangedControlAfterACopyStillCaptionsTheEarlierPacket() async {
        let model = await copiedA()
        script.then(.ready(document("B")))
        await model.setRangeDays(7)
        XCTAssertEqual(model.copyState, .none)
        XCTAssertTrue(model.clipboardHoldsEarlierPacket)
        XCTAssertEqual(present(model).caption, CoachPacketPresenter.staleClipboard)
    }
}
