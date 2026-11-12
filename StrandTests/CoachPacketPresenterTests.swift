// API ASSUMED BY THESE TESTS
//
// New, in Strand/Data/CoachPacketPresenter.swift. Specification §11 says the presenter "owns every
// one of these" strings and gives no signatures; these are the test author's:
//
//     enum CoachPacketPresenter {
//         // Settings card title and switch, Health row title, sheet title, toolbar item label.
//         static var title: String                    // "Coach packet"
//         static var settingsBlurb: String
//         static var rowDetail: String                // "Copy your numbers for your coach"
//         static var toolbarAccessibilityLabel: String   // "Coach packet"
//
//         static var rangeLabel: String               // "Range"
//         static func rangeOption(_ days: Int) -> String              // "14 days"
//         static func sectionLabel(_ section: CoachPacketSection) -> String
//         /// "6.2 kB · 14 days": the size in thousands of bytes to one decimal, then the range.
//         static func sizeLine(byteCount: Int, rangeDays: Int, locale: Locale) -> String
//
//         static var copyAction: String               // "Copy"
//         static var shareAction: String              // "Share"
//         static var retryAction: String              // "Try again"
//         /// "Copied to this iPhone only. It leaves the clipboard at 07:52.": hours and minutes of
//         /// `expiresAt` in `timeZone`, in the locale's short time style.
//         static func copied(expiresAt: Date, timeZone: TimeZone, locale: Locale) -> String
//         static var staleClipboard: String
//         static var nothingMeasured: String
//         static var scorecardOff: String
//         static var everySectionOff: String
//         static var blocked: String
//         static var unavailable: String
//
//         // The Shortcuts action (§9.3, §10.4). The iPhone-only intent file takes its words here.
//         static var intentTitle: String              // "Get Coach Packet"
//         static var intentDescription: String
//         static var intentSwitchedOff: String
//         static var intentNotReady: String
//         static var intentBlocked: String            // the blocked sentence of the sheet
//         static var intentUnavailable: String
//     }
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. The size is bytes divided by 1,000 with one decimal and the unit "kB" (design round README,
//     decision 8). The decimal separator follows `locale`.
//  2. The test host runs in English, as for every other presenter test in this target, so each
//     string is compared with its English source in §11.
//  3. No string of the presenter states or implies a health outcome, gives an instruction about
//     food or training, or carries an exclamation mark (§11, last sentence).

import XCTest
import StrandAnalytics
@testable import Strand

// Stage 2 (coach packet), specification §11 and §12.3: one test per row of the strings table, and
// the size line. Written before the implementation exists.
@MainActor
final class CoachPacketPresenterTests: XCTestCase {
    private static let british = Locale(identifier: "en_GB")
    private static let plusOne = TimeZone(secondsFromGMT: 3_600)!
    private static let blockedSentence =
        "The packet was not created because it contained something that identifies a device or an account."

    // MARK: - §11, row by row

    func testSettingsCardTitleAndSwitch() {
        XCTAssertEqual(CoachPacketPresenter.title, "Coach packet")
    }

    func testSettingsBlurb() {
        XCTAssertEqual(CoachPacketPresenter.settingsBlurb,
                       "One block of text with your recent numbers, for pasting to your coach. Off by default. NOOP sends it nowhere.")
    }

    func testRowAndSheetTitle() {
        XCTAssertEqual(CoachPacketPresenter.title, "Coach packet", "the row and the sheet share the card's title")
    }

    func testRowDetail() {
        XCTAssertEqual(CoachPacketPresenter.rowDetail, "Copy your numbers for your coach")
    }

    func testToolbarItemAccessibilityLabel() {
        XCTAssertEqual(CoachPacketPresenter.toolbarAccessibilityLabel, "Coach packet")
    }

    func testRangeLabelAndOptions() {
        XCTAssertEqual(CoachPacketPresenter.rangeLabel, "Range")
        XCTAssertEqual(CoachPacketSettings.allowedRanges.map(CoachPacketPresenter.rangeOption),
                       ["7 days", "14 days", "28 days"])
    }

    func testSectionSwitches() {
        XCTAssertEqual(CoachPacketSection.allCases.map(CoachPacketPresenter.sectionLabel),
                       ["Scorecard", "Weigh-ins", "Intake", "Recovery and sleep", "Trends", "Activity", "Events"])
        XCTAssertEqual(CoachPacketSection.allCases.count, 7, "packet v2 adds the intake and events switches")
    }

    func testSizeLine() {
        XCTAssertEqual(CoachPacketPresenter.sizeLine(byteCount: 6_221, rangeDays: 14, locale: Self.british),
                       "6.2 kB · 14 days")
    }

    func testActions() {
        XCTAssertEqual(CoachPacketPresenter.copyAction, "Copy")
        XCTAssertEqual(CoachPacketPresenter.shareAction, "Share")
        XCTAssertEqual(CoachPacketPresenter.retryAction, "Try again")
    }

    func testCopied() {
        // 06:52:30 UTC is 07:52 in a zone one hour ahead.
        let expiry = Date(timeIntervalSince1970: 1_931_410_350)
        XCTAssertEqual(CoachPacketPresenter.copied(expiresAt: expiry, timeZone: Self.plusOne, locale: Self.british),
                       "Copied to this iPhone only. It leaves the clipboard at 07:52.")
        // The zone given decides the time shown, not the device's.
        let kolkata = CoachPacketPresenter.copied(expiresAt: expiry, timeZone: TimeZone(identifier: "Asia/Kolkata")!,
                                                  locale: Self.british)
        XCTAssertEqual(kolkata, "Copied to this iPhone only. It leaves the clipboard at 12:22.")
        let american = CoachPacketPresenter.copied(expiresAt: expiry, timeZone: Self.plusOne,
                                                   locale: Locale(identifier: "en_US"))
        XCTAssertTrue(american.contains("7:52"), american)
        XCTAssertFalse(american.contains(":30"), "minutes, never seconds: \(american)")
    }

    func testStaleClipboard() {
        XCTAssertEqual(CoachPacketPresenter.staleClipboard, "The clipboard still holds the earlier packet")
    }

    func testNothingMeasured() {
        XCTAssertEqual(CoachPacketPresenter.nothingMeasured, "Nothing was measured in this range")
    }

    func testScorecardOff() {
        XCTAssertEqual(CoachPacketPresenter.scorecardOff, "The scorecard is off, so these sections say so")
    }

    func testAllOff() {
        XCTAssertEqual(CoachPacketPresenter.everySectionOff, "Switch on at least one section")
    }

    func testBlocked() {
        XCTAssertEqual(CoachPacketPresenter.blocked, Self.blockedSentence)
    }

    func testUnavailable() {
        XCTAssertEqual(CoachPacketPresenter.unavailable, "Your data could not be read. Try again.")
    }

    func testIntentTitleAndDescription() {
        XCTAssertEqual(CoachPacketPresenter.intentTitle, "Get Coach Packet")
        XCTAssertEqual(CoachPacketPresenter.intentDescription,
                       "Returns the coach packet as text, using the sections and range chosen in NOOP.")
    }

    func testIntentErrors() {
        XCTAssertEqual(CoachPacketPresenter.intentSwitchedOff, "Coach packet is switched off in NOOP.")
        XCTAssertEqual(CoachPacketPresenter.intentNotReady, "NOOP is still starting. Run the shortcut again.")
        XCTAssertEqual(CoachPacketPresenter.intentUnavailable, "NOOP could not read your data.")
        XCTAssertEqual(CoachPacketPresenter.intentBlocked, Self.blockedSentence,
                       "the action and the sheet say the same thing about a blocked packet (§10.4)")
    }

    // MARK: - The size line

    func testSizeLineFormatsKilobytes() {
        func size(_ bytes: Int, _ days: Int) -> String {
            CoachPacketPresenter.sizeLine(byteCount: bytes, rangeDays: days, locale: Self.british)
        }
        // The three ranges of the design round's fixture, and the ends.
        XCTAssertEqual(size(4_877, 7), "4.9 kB · 7 days")
        XCTAssertEqual(size(6_221, 14), "6.2 kB · 14 days")
        XCTAssertEqual(size(7_971, 28), "8.0 kB · 28 days")
        XCTAssertEqual(size(11_080, 14), "11.1 kB · 14 days")
        XCTAssertEqual(size(1_000, 7), "1.0 kB · 7 days")
        XCTAssertEqual(size(940, 7), "0.9 kB · 7 days", "thousands of bytes, not 1,024")
        XCTAssertEqual(size(0, 7), "0.0 kB · 7 days")
        XCTAssertEqual(CoachPacketPresenter.sizeLine(byteCount: 6_221, rangeDays: 14, locale: Locale(identifier: "de_DE")),
                       CoachPacketPresenter.sizeLine(byteCount: 6_221, rangeDays: 14, locale: Self.british)
                        .replacingOccurrences(of: "6.2", with: "6,2"),
                       "the decimal separator is the locale's")
    }

    // MARK: - What no string may say

    func testNoStringStatesAHealthOutcomeOrShouts() {
        var strings = [
            CoachPacketPresenter.title, CoachPacketPresenter.settingsBlurb, CoachPacketPresenter.rowDetail,
            CoachPacketPresenter.toolbarAccessibilityLabel, CoachPacketPresenter.rangeLabel,
            CoachPacketPresenter.copyAction, CoachPacketPresenter.shareAction, CoachPacketPresenter.retryAction,
            CoachPacketPresenter.staleClipboard, CoachPacketPresenter.nothingMeasured, CoachPacketPresenter.scorecardOff,
            CoachPacketPresenter.everySectionOff, CoachPacketPresenter.blocked, CoachPacketPresenter.unavailable,
            CoachPacketPresenter.intentTitle, CoachPacketPresenter.intentDescription,
            CoachPacketPresenter.intentSwitchedOff, CoachPacketPresenter.intentNotReady,
            CoachPacketPresenter.intentBlocked, CoachPacketPresenter.intentUnavailable,
            CoachPacketPresenter.sizeLine(byteCount: 6_221, rangeDays: 14, locale: Self.british),
            CoachPacketPresenter.copied(expiresAt: Date(timeIntervalSince1970: 1_931_410_350), timeZone: Self.plusOne,
                                        locale: Self.british),
        ]
        strings += CoachPacketSection.allCases.map(CoachPacketPresenter.sectionLabel)
        strings += CoachPacketSettings.allowedRanges.map(CoachPacketPresenter.rangeOption)
        for string in strings {
            XCTAssertFalse(string.isEmpty)
            XCTAssertFalse(string.contains("!"), string)
            let lowered = string.lowercased()
            for word in ["should", "must", "warning", "healthy", "unhealthy", "risk", "diagnos", "calorie", "eat ",
                         "streak", "great", "well done"] {
                XCTAssertFalse(lowered.contains(word), "\"\(string)\" says \"\(word)\"")
            }
        }
        // The blurb's promise is the one the stage keeps: the app sends the packet nowhere.
        XCTAssertTrue(CoachPacketPresenter.settingsBlurb.contains("NOOP sends it nowhere."))
        XCTAssertTrue(CoachPacketPresenter.settingsBlurb.contains("Off by default."))
    }

    // MARK: - The sheet for states that need no model

    private func ready(_ document: CoachPacketDocument, copy: CoachPacketModel.CopyState = .none,
                       regenerating: Bool = false, stale: Bool = false, scorecard: Bool = true) -> CoachPacketSheetPresentation {
        CoachPacketPresenter.sheet(state: .ready(document), copyState: copy, isRegenerating: regenerating,
                                   clipboardHoldsEarlierPacket: stale, scorecardEnabled: scorecard,
                                   timeZone: Self.plusOne, locale: Self.british)
    }

    private func document(sections: Set<CoachPacketSection> = Set(CoachPacketSection.allCases),
                          nothingMeasured: Bool = false, rangeDays: Int = 14) -> CoachPacketDocument {
        let text = CoachPacketText.sample("presenter")
        return CoachPacketDocument(text: text, byteCount: 6_221, generatedAt: Date(timeIntervalSince1970: 1_931_409_730),
                                   rangeDays: rangeDays, sections: sections, nothingMeasured: nothingMeasured)
    }

    /// Caption precedence of the approved frames: stale clipboard, every section off, nothing
    /// measured. One caption at most, for all eight combinations.
    func testOneCaptionAtMostByPrecedence() {
        for stale in [false, true] {
            for allOff in [false, true] {
                for nothing in [false, true] {
                    let sheet = ready(document(sections: allOff ? [] : Set(CoachPacketSection.allCases),
                                               nothingMeasured: nothing), stale: stale)
                    let expected = stale ? CoachPacketPresenter.staleClipboard
                        : allOff ? CoachPacketPresenter.everySectionOff
                        : nothing ? CoachPacketPresenter.nothingMeasured : nil
                    XCTAssertEqual(sheet.caption, expected, "stale \(stale), all off \(allOff), nothing \(nothing)")
                    XCTAssertEqual(sheet.copyAndShareEnabled, !allOff)
                }
            }
        }
    }

    func testTheSheetForEachStateOfTheModel() {
        func sheet(_ state: CoachPacketModel.State) -> CoachPacketSheetPresentation {
            CoachPacketPresenter.sheet(state: state, copyState: .none, isRegenerating: false,
                                       clipboardHoldsEarlierPacket: false, scorecardEnabled: true,
                                       timeZone: Self.plusOne, locale: Self.british)
        }
        let loading = sheet(.loading)
        XCTAssertEqual(loading.body, .skeleton)
        XCTAssertNil(loading.statusLine)
        XCTAssertNil(loading.caption)
        XCTAssertTrue(loading.showsCopyAndShare)
        XCTAssertFalse(loading.copyAndShareEnabled)
        XCTAssertFalse(loading.showsRetry)

        let one = document()
        XCTAssertEqual(ready(one), CoachPacketSheetPresentation(
            body: .preview(text: one.text, dimmed: false), statusLine: "6.2 kB · 14 days", caption: nil,
            scorecardCaption: nil, showsCopyAndShare: true, copyAndShareEnabled: true, showsRetry: false))
        XCTAssertEqual(ready(one, regenerating: true), CoachPacketSheetPresentation(
            body: .preview(text: one.text, dimmed: true), statusLine: "6.2 kB · 14 days", caption: nil,
            scorecardCaption: nil, showsCopyAndShare: true, copyAndShareEnabled: false, showsRetry: false))
        XCTAssertEqual(ready(one, scorecard: false).scorecardCaption, CoachPacketPresenter.scorecardOff)

        let expiry = Date(timeIntervalSince1970: 1_931_410_350)
        XCTAssertEqual(ready(one, copy: .copied(expiresAt: expiry)).statusLine,
                       "Copied to this iPhone only. It leaves the clipboard at 07:52.",
                       "the confirmation replaces the size line")

        for (state, message) in [(CoachPacketModel.State.blocked, CoachPacketPresenter.blocked),
                                 (CoachPacketModel.State.unavailable, CoachPacketPresenter.unavailable)] {
            XCTAssertEqual(sheet(state), CoachPacketSheetPresentation(
                body: .message(message), statusLine: nil, caption: nil, scorecardCaption: nil,
                showsCopyAndShare: false, copyAndShareEnabled: false, showsRetry: true))
        }

        // The flag is off: there is no sheet, and nothing in it may be acted on.
        let idle = sheet(.idle)
        XCTAssertFalse(idle.copyAndShareEnabled)
        XCTAssertFalse(idle.showsRetry)
        if case .preview = idle.body { XCTFail("with the flag off there is no text to preview") }
    }

    /// The scorecard caption is about two switches that stay usable, so it shows while loading
    /// too. It is hidden only when no control is about a section, which is never.
    func testTheScorecardCaptionDoesNotDependOnTheText() {
        for state in [CoachPacketModel.State.loading, .ready(document()), .ready(document(sections: []))] {
            let sheet = CoachPacketPresenter.sheet(state: state, copyState: .none, isRegenerating: false,
                                                   clipboardHoldsEarlierPacket: false, scorecardEnabled: false,
                                                   timeZone: Self.plusOne, locale: Self.british)
            XCTAssertEqual(sheet.scorecardCaption, CoachPacketPresenter.scorecardOff, "\(state)")
        }
    }
}
