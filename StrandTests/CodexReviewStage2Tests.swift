// API ASSUMED BY THESE TESTS (stage 2, independent review C10)
//
//     @MainActor struct CoachPacketAssembler {
//         init(..., identifiers: @escaping () -> [String]?,
//              storeReadable: (@MainActor () async -> Bool)? = nil)   // nil: the repository's store handle
//     }
//     enum CoachPacketShortcutResult: Equatable { case text(String), switchedOff, notReady, blocked, unavailable }
//     @MainActor enum CoachPacketShortcut {
//         static func run(settings:attempts:isReady:pause:assemble:) async -> CoachPacketShortcutResult
//     }
//
// The rest is the API assumed at the top of CoachPacketAssemblerTests.swift and
// CoachPacketModelTests.swift. Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// Records every plan it is handed. No real pasteboard is touched.
private final class CodexReviewPasteboardSpy: CoachPacketPasteboardWriting {
    private(set) var plans: [CoachPacketCopyPlan] = []
    func write(_ plan: CoachPacketCopyPlan) { plans.append(plan) }
}

/// C10 P1: switching the feature off revokes every way text leaves the app, including a Shortcuts
/// request already waiting and a sheet already showing a packet.
@MainActor
final class CodexReviewStage2FlagRevocationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var settings: CoachPacketSettings!

    override func setUp() {
        super.setUp()
        suiteName = "CodexReviewStage2Tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = CoachPacketSettings(defaults: defaults)
        settings.isEnabled = true
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func document(_ marker: String) -> CoachPacketDocument {
        let text = "NOOP coach packet\nmarker: \(marker)\n"
        return CoachPacketDocument(text: text, byteCount: text.utf8.count,
                                   generatedAt: Date(timeIntervalSince1970: 1_931_409_730), rangeDays: 14,
                                   sections: Set(CoachPacketSection.allCases), nothingMeasured: false)
    }

    func testTheShortcutReturnsNoTextWhenTheFlagGoesOffWhileItWaitsForTheApp() async {
        var ready = false
        var assemblies = 0
        let result = await CoachPacketShortcut.run(
            settings: settings, attempts: 8, isReady: { ready },
            pause: {
                // Switched off while the action waits, then the app becomes ready.
                self.settings.isEnabled = false
                ready = true
            },
            assemble: {
                assemblies += 1
                return .ready(self.document("SYNTHETIC_FIXTURE"))
            })
        XCTAssertEqual(result, .switchedOff)
        XCTAssertEqual(assemblies, 0, "nothing is assembled once the feature is off")
    }

    func testTheShortcutReturnsNoTextWhenTheFlagGoesOffDuringAssembly() async {
        let result = await CoachPacketShortcut.run(
            settings: settings, attempts: 8, isReady: { true }, pause: {},
            assemble: {
                self.settings.isEnabled = false
                return .ready(self.document("SYNTHETIC_FIXTURE"))
            })
        XCTAssertEqual(result, .switchedOff)
    }

    func testTheShortcutStillReturnsTheTextWhileTheFlagStaysOn() async {
        let result = await CoachPacketShortcut.run(
            settings: settings, attempts: 8, isReady: { true }, pause: {},
            assemble: { .ready(self.document("SYNTHETIC_FIXTURE")) })
        XCTAssertEqual(result, .text(document("SYNTHETIC_FIXTURE").text))
    }

    func testAShownPacketCannotBeCopiedOrSharedOnceTheFlagIsOff() async {
        let pasteboard = CodexReviewPasteboardSpy()
        let shown = document("SYNTHETIC_FIXTURE")
        let model = CoachPacketModel(assemble: { .ready(shown) }, settings: settings, pasteboard: pasteboard)
        await model.load()
        XCTAssertEqual(model.shareText, shown.text, "while on, the shown packet may leave")

        settings.isEnabled = false
        XCTAssertNil(model.shareText, "share must refuse while the feature is off")
        model.copy()
        XCTAssertEqual(pasteboard.plans, [], "copy must refuse while the feature is off")
        XCTAssertEqual(model.copyState, .none)
    }
}

/// C10 P2: a store that cannot be read gives the unavailable state, never a packet of dashes.
@MainActor
final class CodexReviewStage2UnreadableStoreTests: XCTestCase {
    private typealias H = CoachPacketHarness
    private let suites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func assembler(_ h: H, storeReadable: (@MainActor () async -> Bool)?) -> CoachPacketAssembler {
        let now = h.clock.now
        return CoachPacketAssembler(repository: h.repo, provider: h.provider, scorecardSettings: h.scorecardSettings,
                                    settings: h.packetSettings, now: { now }, timeZone: { H.utc },
                                    effortScale: { .hundred }, identifiers: { [] }, storeReadable: storeReadable)
    }

    func testAnUnreadableStoreIsUnavailableNotAnEmptyPacket() async throws {
        let h = try await H.empty(scorecard: true, suites: suites)
        let unreadable = assembler(h, storeReadable: { false })
        let outcome = await unreadable.assemble()
        XCTAssertEqual(outcome, .unavailable, "an unreadable store must not be exported as nothing measured")
        let input = await unreadable.input()
        XCTAssertNil(input, "no renderer input exists for a store that could not be read")
    }

    func testAStoreThatStopsBeingReadableDuringAssemblyIsUnavailable() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let probes = CoachPacketBox(0)
        // Readable when assembly begins, unreadable once the reads are done.
        let outcome = await assembler(h, storeReadable: {
            probes.value += 1
            return probes.value == 1
        }).assemble()
        XCTAssertEqual(outcome, .unavailable)
    }

    func testAReadableStoreGivesTheSamePacketWithOrWithoutTheProbe() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let probed = await assembler(h, storeReadable: { true }).assemble()
        let byHandle = await assembler(h, storeReadable: nil).assemble()
        guard case .ready(let document) = byHandle else { return XCTFail("a readable store is a packet: \(byHandle)") }
        XCTAssertEqual(probed, byHandle)
        XCTAssertFalse(document.nothingMeasured)
    }
}
