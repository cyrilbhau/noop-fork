import Combine
import Foundation
import StrandAnalytics

// Stage 2 (coach packet), specification §8.5 and §9.1: everything below the packet sheet. The
// sheet lives in StrandiOS; every rule it follows is held here so that it can be tested without a
// view, and so that this file compiles for macOS, which has no sheet.

// MARK: - The pasteboard item

/// One copy of the packet: the text, when it was copied and when the system removes it. The time
/// the sheet shows and the time handed to the system are this one `expiresAt`.
struct CoachPacketCopyPlan: Equatable {
    static let lifetimeSeconds: TimeInterval = 600
    let text: String
    let copiedAt: Date
    var expiresAt: Date { copiedAt.addingTimeInterval(Self.lifetimeSeconds) }
    /// Never offered to another device.
    var localOnly: Bool { true }
}

/// Puts a copy plan on the system pasteboard. The iPhone's writer is `SystemCoachPacketPasteboard`;
/// tests pass a recorder.
protocol CoachPacketPasteboardWriting {
    func write(_ plan: CoachPacketCopyPlan)
}

// MARK: - The sheet model

/// The packet sheet's state (specification §10.2). WHAT IS PREVIEWED IS WHAT LEAVES: `copy()` and
/// `shareText` use the document in `state` and never assemble again.
@MainActor
final class CoachPacketModel: ObservableObject {
    enum State: Equatable { case idle, loading, ready(CoachPacketDocument), blocked, unavailable }
    enum CopyState: Equatable { case none, copied(expiresAt: Date) }

    /// `.idle` until the first load, and whenever the flag is off.
    @Published private(set) var state: State = .idle
    /// `.copied` while the text on screen is the text this sheet last put on the clipboard.
    @Published private(set) var copyState: CopyState = .none
    /// True while a load is replacing a packet that is still on screen. The previous preview
    /// stays, and nothing may be copied or shared: it is no longer the text for the stored choices.
    @Published private(set) var isRegenerating = false
    /// When the earlier copy leaves the clipboard, once a control changed after that copy.
    @Published private var earlierCopyExpiresAt: Date?

    private let assemble: @MainActor () async -> CoachPacketOutcome
    private let settings: CoachPacketSettings
    private let pasteboard: CoachPacketPasteboardWriting
    private let now: () -> Date
    private var generation = 0
    /// The text the last `copy()` put on the clipboard.
    private var copiedText: String?
    private var expiryTick: Task<Void, Never>?

    init(assemble: @escaping @MainActor () async -> CoachPacketOutcome,
         settings: CoachPacketSettings, pasteboard: CoachPacketPasteboardWriting,
         now: @escaping () -> Date = { Date() }) {
        self.assemble = assemble
        self.settings = settings
        self.pasteboard = pasteboard
        self.now = now
    }

    deinit {
        expiryTick?.cancel()
    }

    // MARK: Loading

    /// Flag off: `.idle`, and nothing is assembled. Flag on: a fresh packet every time. The first
    /// load shows `.loading`; a load over a packet already on screen keeps it and sets
    /// `isRegenerating`. A load that finishes after a later one began publishes nothing.
    func load() async {
        generation += 1
        let request = generation
        guard settings.isEnabled else {
            if isRegenerating { isRegenerating = false }
            if state != .idle { state = .idle }
            return
        }
        forgetExpiredCopy()
        if case .ready = state {
            if !isRegenerating { isRegenerating = true }
        } else {
            if isRegenerating { isRegenerating = false }
            if state != .loading { state = .loading }
        }

        let outcome = await assemble()
        guard request == generation else { return }
        if isRegenerating { isRegenerating = false }
        guard settings.isEnabled else {
            state = .idle
            return
        }
        switch outcome {
        case .ready(let document):
            // Ruling A21: "Copied" means the text on screen. A reload that shows other text (the
            // foreground reload, a flag change, Try again) clears the confirmation. The stale-clipboard
            // caption stays tied to a changed control (CoachPacketModelTests, behaviour 5).
            if case .copied = copyState, document.text != copiedText { copyState = .none }
            state = .ready(document)
        case .blocked: state = .blocked
        case .unavailable: state = .unavailable
        }
    }

    /// The stored section choices, for the switches. The packet on screen names its own.
    var sections: Set<CoachPacketSection> { settings.sections }

    /// The stored range, for the range control.
    var rangeDays: Int { settings.rangeDays }

    /// Stores the choice before anything suspends, clears the copied confirmation and reloads.
    func setSection(_ section: CoachPacketSection, on: Bool) async {
        guard settings.isEnabled else { return await load() }
        objectWillChange.send()
        settings.setSection(section, on: on)
        controlChanged()
        await load()
    }

    /// Stores the range before anything suspends, clears the copied confirmation and reloads.
    func setRangeDays(_ days: Int) async {
        guard settings.isEnabled else { return await load() }
        objectWillChange.send()
        settings.rangeDays = days
        controlChanged()
        await load()
    }

    /// The text about to be shown differs from what was copied: the confirmation clears, and the
    /// clipboard is remembered as holding the earlier packet until that copy expires.
    private func controlChanged() {
        if case .copied(let expiresAt) = copyState {
            earlierCopyExpiresAt = expiresAt
            copyState = .none
        }
    }

    // MARK: Copy and share

    /// The document that may leave now: the previewed one, while it is the packet for the stored
    /// choices and has at least one section.
    private var leavingDocument: CoachPacketDocument? {
        guard !isRegenerating, case .ready(let document) = state, !document.sections.isEmpty else { return nil }
        return document
    }

    /// The previewed text for the share sheet; nil when nothing may leave.
    var shareText: String? { leavingDocument?.text }

    /// Hands the previewed text to the pasteboard as a local-only item that expires. One clock
    /// reading gives the plan's time, and the plan's expiry is the one the sheet shows.
    func copy() {
        guard let document = leavingDocument else { return }
        let plan = CoachPacketCopyPlan(text: document.text, copiedAt: now())
        pasteboard.write(plan)
        copiedText = document.text
        earlierCopyExpiresAt = nil
        copyState = .copied(expiresAt: plan.expiresAt)
        forgetWhenExpired(plan.expiresAt)
    }

    /// True after a copy and then a changed control, until that copy leaves the clipboard.
    var clipboardHoldsEarlierPacket: Bool {
        guard let earlierCopyExpiresAt else { return false }
        return now() < earlierCopyExpiresAt
    }

    /// The system removes the item at `expiresAt`. From then on the sheet says nothing about a
    /// clipboard that no longer holds the packet.
    private func forgetWhenExpired(_ expiresAt: Date) {
        expiryTick?.cancel()
        expiryTick = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CoachPacketCopyPlan.lifetimeSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.copyState == .copied(expiresAt: expiresAt) { self.copyState = .none }
            if self.earlierCopyExpiresAt == expiresAt { self.earlierCopyExpiresAt = nil }
        }
    }

    /// The same, checked against the clock at each load: a sleeping task does not advance while
    /// the app is suspended, and a sheet that comes back to the foreground reloads.
    private func forgetExpiredCopy() {
        let expiry: Date
        if case .copied(let expiresAt) = copyState { expiry = expiresAt }
        else if let earlierCopyExpiresAt { expiry = earlierCopyExpiresAt }
        else { return }
        guard now() >= expiry else { return }
        copyState = .none
        earlierCopyExpiresAt = nil
    }
}
