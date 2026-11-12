import Foundation
import StrandAnalytics

// Stage 2 (coach packet), specification §10.2 and §11: every interface string of the stage and
// what the sheet draws for each state, so the views contain no copy and decide nothing. None of
// these strings states or implies a health outcome. The packet text itself is English, is never
// localised and never passes through here.

/// What the packet sheet draws for one state of the model (specification §10.2). Pure.
struct CoachPacketSheetPresentation: Equatable {
    enum Body: Equatable {
        /// Loading: a placeholder where the preview will be.
        case skeleton
        /// The exact text that will leave; dimmed while a newer packet is being assembled.
        case preview(text: String, dimmed: Bool)
        /// Blocked or unavailable: no text exists.
        case message(String)
    }

    var body: Body
    /// The size line, or the copied confirmation that replaces it.
    var statusLine: String?
    /// At most one of: stale clipboard, every section off, nothing measured.
    var caption: String?
    /// Under the Scorecard and Weigh-ins switches, while the scorecard is off in the app.
    var scorecardCaption: String?
    /// False when blocked or unavailable: there is nothing to copy or share.
    var showsCopyAndShare: Bool
    var copyAndShareEnabled: Bool
    /// "Try again", only when blocked or unavailable.
    var showsRetry: Bool
    /// True when `statusLine` is the copied confirmation, which the sheet marks with a check.
    var statusIsCopyConfirmation = false
    /// Packet v2: under the Events switch, read-only, "Private events: left out" or "... included".
    /// Worded from the document's captured choice; nil when the document has none. No count.
    var privateEventsCaption: String? = nil
    /// "Change this in Settings.", beside `privateEventsCaption` and only with it.
    var privateEventsHint: String? = nil
}

enum CoachPacketPresenter {
    // MARK: Settings card, Health row, sheet title, toolbar item

    static var title: String { String(localized: "Coach packet") }
    static var settingsBlurb: String {
        String(localized: "One block of text with your recent numbers, for pasting to your coach. Off by default. NOOP sends it nowhere.")
    }
    static var rowDetail: String { String(localized: "Copy your numbers for your coach") }
    static var toolbarAccessibilityLabel: String { title }
    /// Dismisses the sheet.
    static var doneAction: String { String(localized: "Done") }

    // MARK: Controls

    static var rangeLabel: String { String(localized: "Range") }

    static func rangeOption(_ days: Int) -> String { String(localized: "\(days) days") }

    static func sectionLabel(_ section: CoachPacketSection) -> String {
        switch section {
        case .scorecard: return String(localized: "Scorecard")
        case .weighIns: return String(localized: "Weigh-ins")
        case .recoverySleep: return String(localized: "Recovery and sleep")
        case .trends: return String(localized: "Trends")
        case .activity: return String(localized: "Activity")
        case .intake: return String(localized: "Intake")
        case .events: return String(localized: "Events")
        }
    }

    // MARK: Private events (packet v2; stage 5 §9.6 and §11)

    static var privateEventsLeftOut: String { String(localized: "Private events: left out") }
    static var privateEventsIncluded: String { String(localized: "Private events: included") }
    static var privateEventsChangeInSettings: String { String(localized: "Change this in Settings.") }

    // MARK: Size and copy

    /// "6.2 kB": thousands of bytes to one decimal, with the locale's decimal separator.
    private static func size(_ byteCount: Int, locale: Locale) -> String {
        String(format: "%.1f", locale: locale, Double(byteCount) / 1_000) + " kB"
    }

    /// "6.2 kB · 14 days".
    static func sizeLine(byteCount: Int, rangeDays: Int, locale: Locale) -> String {
        String(localized: "\(size(byteCount, locale: locale)) · \(rangeDays) days")
    }

    /// The size line of a packet above its budget, which no input should produce.
    static func sizeLineOverBudget(byteCount: Int, rangeDays: Int, locale: Locale) -> String {
        String(localized: "\(size(byteCount, locale: locale)) · \(rangeDays) days · larger than expected")
    }

    static var copyAction: String { String(localized: "Copy") }
    static var shareAction: String { String(localized: "Share") }
    static var retryAction: String { String(localized: "Try again") }

    /// "Copied to this iPhone only. It leaves the clipboard at 07:52.": the hour and minute of
    /// `expiresAt` in `timeZone`, in the locale's short time style.
    static func copied(expiresAt: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return String(localized: "Copied to this iPhone only. It leaves the clipboard at \(formatter.string(from: expiresAt)).")
    }

    // MARK: Captions and messages

    static var staleClipboard: String { String(localized: "The clipboard still holds the earlier packet") }
    static var nothingMeasured: String { String(localized: "Nothing was measured in this range") }
    static var scorecardOff: String { String(localized: "The scorecard is off, so these sections say so") }
    static var everySectionOff: String { String(localized: "Switch on at least one section") }
    static var blocked: String {
        String(localized: "The packet was not created because it contained something that identifies a device or an account.")
    }
    static var unavailable: String { String(localized: "Your data could not be read. Try again.") }

    // MARK: The Shortcuts action

    static var intentTitle: String { String(localized: "Get Coach Packet") }
    static var intentDescription: String {
        String(localized: "Returns the coach packet as text, using the sections and range chosen in NOOP.")
    }
    static var intentSwitchedOff: String { String(localized: "Coach packet is switched off in NOOP.") }
    static var intentNotReady: String { String(localized: "NOOP is still starting. Run the shortcut again.") }
    static var intentBlocked: String { blocked }
    static var intentUnavailable: String { String(localized: "NOOP could not read your data.") }

    // MARK: The sheet

    /// The sheet for one state of the model. `clipboardHoldsEarlierPacket` and the copy state are
    /// the model's; `scorecardEnabled` is the scorecard's own flag.
    static func sheet(state: CoachPacketModel.State, copyState: CoachPacketModel.CopyState,
                      isRegenerating: Bool, clipboardHoldsEarlierPacket: Bool,
                      scorecardEnabled: Bool, timeZone: TimeZone, locale: Locale) -> CoachPacketSheetPresentation {
        // About two switches that stay usable in every state, so it does not depend on the text.
        let scorecardCaption = scorecardEnabled ? nil : scorecardOff
        switch state {
        case .idle, .loading:
            return CoachPacketSheetPresentation(
                body: .skeleton, statusLine: nil, caption: nil, scorecardCaption: scorecardCaption,
                showsCopyAndShare: true, copyAndShareEnabled: false, showsRetry: false)
        case .blocked, .unavailable:
            return CoachPacketSheetPresentation(
                body: .message(state == .blocked ? blocked : unavailable), statusLine: nil, caption: nil,
                scorecardCaption: scorecardCaption, showsCopyAndShare: false, copyAndShareEnabled: false,
                showsRetry: true)
        case .ready(let document):
            let everyOff = document.sections.isEmpty
            let statusLine: String
            var confirmsCopy = false
            if case .copied(let expiresAt) = copyState {
                statusLine = copied(expiresAt: expiresAt, timeZone: timeZone, locale: locale)
                confirmsCopy = true
            } else if document.byteCount > CoachPacket.byteBudget(rangeDays: document.rangeDays) {
                statusLine = sizeLineOverBudget(byteCount: document.byteCount, rangeDays: document.rangeDays,
                                                locale: locale)
            } else {
                statusLine = sizeLine(byteCount: document.byteCount, rangeDays: document.rangeDays, locale: locale)
            }
            // One caption at most, in the order of the approved frames.
            let caption: String?
            if clipboardHoldsEarlierPacket { caption = staleClipboard }
            else if everyOff { caption = everySectionOff }
            else if document.nothingMeasured { caption = nothingMeasured }
            else { caption = nil }
            // The caption names the choice the previewed text was built with, so it cannot disagree
            // with the text beneath it.
            let privateCaption = document.privateEventsIncluded.map { $0 ? privateEventsIncluded : privateEventsLeftOut }
            return CoachPacketSheetPresentation(
                body: .preview(text: document.text, dimmed: isRegenerating), statusLine: statusLine,
                caption: caption, scorecardCaption: scorecardCaption, showsCopyAndShare: true,
                copyAndShareEnabled: !isRegenerating && !everyOff, showsRetry: false,
                statusIsCopyConfirmation: confirmsCopy, privateEventsCaption: privateCaption,
                privateEventsHint: privateCaption == nil ? nil : privateEventsChangeInSettings)
        }
    }
}
