import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 2 (coach packet), specification §10.2, frames B1 to B17 of
// `design/round-s2-coach-packet/`. Top to bottom: title, range, seven section switches (packet v2
// adds Intake after Weigh-ins and Events last, with a read-only private-events caption under it),
// the size line, the preview, Copy, Share.
//
// The sheet draws a `CoachPacketSheetPresentation` and decides nothing: which parts exist, every
// word and whether an action is enabled are the presenter's, and the text is the model's. The
// preview is the exact text that will leave. It is not selectable: selecting part of it and using
// the system Copy would bypass the local-only, expiring item.

/// Geometry from `design/round-s2-coach-packet/packet.css` with no `NoopTheme` token.
private enum CoachPacketLayout {
    /// `.pv.dimmed`, `.pmeta.dimmed`: the earlier preview while a newer one is assembled.
    static let dimmedOpacity: Double = 0.38
    /// `.pv`: the preview inset is darker than the sheet.
    static let previewTint: Double = 0.34
    /// `.ax .psheet .pv`: the preview's height when the whole sheet scrolls.
    static let scrollingPreviewHeight: CGFloat = 330
    /// `.srow`: the least height of a section switch row.
    static let switchRowHeight: CGFloat = 40
}

/// What a debug demo fixes about the sheet. Nil in the app.
struct CoachPacketSheetDemo {
    let scorecardEnabled: Bool
    let timeZone: TimeZone
    let locale: Locale
    /// Presents the share sheet as soon as the packet is ready.
    var sharesAtOnce = false
}

/// The packet sheet, as the Health row and the scorecard toolbar item present it. It exists only
/// while the feature is on: when `noop.coachPacketEnabled` goes off it dismisses itself.
struct CoachPacketSheet: View {
    @StateObject private var model: CoachPacketModel
    @ObservedObject private var flag = CoachPacketSettings.flag
    @ObservedObject private var scorecardFlag = CutScorecardFlag.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shared: SharedText?
    private let demo: CoachPacketSheetDemo?

    /// The text handed to the share sheet: the previewed text at the moment Share was tapped.
    private struct SharedText: Identifiable {
        let id = UUID()
        let text: String
    }

    /// The app's sheet: a fresh model over the app's assembler and the system pasteboard.
    init() {
        _model = StateObject(wrappedValue: CoachPacketModel(
            assemble: { await CoachPacketAssembler.live()?.assemble() ?? .unavailable },
            settings: CoachPacketSettings(), pasteboard: SystemCoachPacketPasteboard()))
        demo = nil
    }

    /// For the debug demo, which opens the sheet on a model in a given state.
    init(model: CoachPacketModel, demo: CoachPacketSheetDemo) {
        _model = StateObject(wrappedValue: model)
        self.demo = demo
    }

    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    private var shown: CoachPacketSheetPresentation {
        CoachPacketPresenter.sheet(
            state: model.state, copyState: model.copyState, isRegenerating: model.isRegenerating,
            clipboardHoldsEarlierPacket: model.clipboardHoldsEarlierPacket,
            scorecardEnabled: demo?.scorecardEnabled ?? scorecardFlag.isEnabled,
            timeZone: demo?.timeZone ?? TimeZone.current, locale: demo?.locale ?? AppLanguage.activeLocale)
    }

    var body: some View {
        let shown = shown
        NavigationStack {
            Group {
                if stacks {
                    // Largest text sizes: the controls stack and the whole sheet scrolls; the
                    // preview keeps its own size and scrolls both ways inside it.
                    ScrollView {
                        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                            controls(shown)
                            content(shown).frame(height: CoachPacketLayout.scrollingPreviewHeight)
                            actions(shown)
                        }
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.vertical, NoopTheme.Layout.l)
                    }
                } else {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                        controls(shown)
                        content(shown).frame(maxHeight: .infinity)
                        actions(shown)
                    }
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .padding(.top, NoopTheme.Layout.s)
                    .padding(.bottom, NoopTheme.Layout.s)
                }
            }
            .background(NoopTheme.sheet.ignoresSafeArea())
            .navigationTitle(Text(verbatim: CoachPacketPresenter.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text(verbatim: CoachPacketPresenter.doneAction)
                            .noopFont(.body, color: false)
                            .foregroundStyle(NoopTheme.textPrimary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $shared) { CoachPacketShareSheet(text: $0.text) }
        .sensoryFeedback(trigger: model.copyState) { _, new in
            if case .copied = new { return .success }
            return nil
        }
        // A fresh packet each time the sheet opens, and when the app returns to the foreground
        // with the sheet open.
        .task { await model.load() }
        .onChangeCompat(of: scenePhase) { phase in
            if phase == .active { Task { await model.load() } }
        }
        // The scorecard's own switch decides what two sections say, so the text follows it.
        .onChangeCompat(of: scorecardFlag.isEnabled) { _ in
            if demo == nil { Task { await model.load() } }
        }
        .onChangeCompat(of: flag.isEnabled) { enabled in
            if demo == nil, !enabled { dismiss() }
        }
        .onChangeCompat(of: model.state) { _ in
            if demo?.sharesAtOnce == true, shared == nil, let text = model.shareText {
                shared = SharedText(text: text)
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ shown: CoachPacketSheetPresentation) -> some View {
        rangeControl
        sectionSwitches(shown)
        status(shown)
    }

    private var rangeControl: some View {
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.s))
            : AnyLayout(HStackLayout(spacing: NoopTheme.Layout.m))
        return layout {
            Text(verbatim: CoachPacketPresenter.rangeLabel)
                .noopFont(.bodySmall, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(selection: Binding(
                get: { model.rangeDays },
                set: { days in Task { await model.setRangeDays(days) } }
            )) {
                ForEach(CoachPacketSettings.allowedRanges, id: \.self) { days in
                    Text(verbatim: CoachPacketPresenter.rangeOption(days)).tag(days)
                }
            } label: {
                Text(verbatim: CoachPacketPresenter.rangeLabel)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text(verbatim: CoachPacketPresenter.rangeLabel))
        }
    }

    private func sectionSwitches(_ shown: CoachPacketSheetPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CoachPacketSection.allCases, id: \.self) { section in
                Toggle(isOn: Binding(
                    get: { model.sections.contains(section) },
                    set: { on in Task { await model.setSection(section, on: on) } }
                )) {
                    Text(verbatim: CoachPacketPresenter.sectionLabel(section))
                        .noopFont(.listTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(NoopTheme.recovery)
                .frame(minHeight: CoachPacketLayout.switchRowHeight)
                // Under the two switches it is about: Scorecard and Weigh-ins.
                if section == .weighIns, let caption = shown.scorecardCaption {
                    Text(verbatim: caption)
                        .noopFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, NoopTheme.Layout.s)
                }
                // Packet v2: read-only, no control. Worded from the choice the previewed text was
                // built with; the setting itself is changed in Settings.
                if section == .events, let caption = shown.privateEventsCaption {
                    VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                        Text(verbatim: caption)
                            .noopFont(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hint = shown.privateEventsHint {
                            Text(verbatim: hint)
                                .noopFont(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.bottom, NoopTheme.Layout.s)
                }
            }
        }
        .padding(.horizontal, FormKitLayout.fieldHorizontal)
        .padding(.vertical, NoopTheme.Layout.xs)
        .background {
            RoundedRectangle(cornerRadius: NoopTheme.Layout.l, style: .continuous).fill(NoopTheme.control)
        }
    }

    /// The size line, or the copied confirmation that replaces it, and at most one caption.
    @ViewBuilder
    private func status(_ shown: CoachPacketSheetPresentation) -> some View {
        if shown.statusLine != nil || shown.caption != nil || shown.body == .skeleton {
            VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                if let line = shown.statusLine {
                    let copied = shown.statusIsCopyConfirmation
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
                        if copied {
                            Image(systemName: "checkmark")
                                .noopFont(.footnote, color: false)
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: line)
                            .noopFont(.footnote, color: false)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(copied ? NoopTheme.textPrimary : NoopTheme.textSecondary)
                    .opacity(isDimmed(shown) ? CoachPacketLayout.dimmedOpacity : 1)
                } else if shown.body == .skeleton {
                    // Holds the size line's place while the first packet is assembled.
                    Text(verbatim: CoachPacketPresenter.sizeLine(byteCount: 0, rangeDays: model.rangeDays,
                                                                 locale: demo?.locale ?? AppLanguage.activeLocale))
                        .noopFont(.footnote)
                        .noopSkeleton(true, cornerRadius: NoopTheme.Layout.xs)
                        .accessibilityHidden(true)
                }
                if let caption = shown.caption {
                    Text(verbatim: caption)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func isDimmed(_ shown: CoachPacketSheetPresentation) -> Bool {
        if case .preview(_, let dimmed) = shown.body { return dimmed }
        return false
    }

    // MARK: Preview

    @ViewBuilder
    private func content(_ shown: CoachPacketSheetPresentation) -> some View {
        switch shown.body {
        case .skeleton:
            previewSurface
                .noopSkeleton(true, cornerRadius: FormKitLayout.fieldRadius)
                .accessibilityHidden(true)
        case .preview(let text, let dimmed):
            ScrollView([.vertical, .horizontal]) {
                // Verbatim: the packet text is never localised. Fixed monospaced size, so no line
                // re-wraps at a larger text size and no number is truncated.
                Text(verbatim: text)
                    .font(StrandFont.mono)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(NoopTheme.Layout.m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { previewSurface }
            .clipShape(RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous))
            // No animation: the change of state is the only change (and so nothing to reduce).
            .opacity(dimmed ? CoachPacketLayout.dimmedOpacity : 1)
        case .message(let message):
            VStack(spacing: NoopTheme.Layout.m) {
                Image(systemName: model.state == .blocked ? "lock.shield" : "info.circle")
                    .noopFont(.statNumber, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: message)
                    .noopFont(.body, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NoopTheme.Layout.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous).fill(NoopTheme.control)
            }
        }
    }

    private var previewSurface: some View {
        RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
            .fill(NoopTheme.canvas.opacity(CoachPacketLayout.previewTint))
            .overlay {
                RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
                    .strokeBorder(NoopTheme.separator, lineWidth: FormKitLayout.hairline)
            }
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ shown: CoachPacketSheetPresentation) -> some View {
        VStack(spacing: NoopTheme.Layout.s) {
            if shown.showsCopyAndShare {
                Button { model.copy() } label: {
                    Label { Text(verbatim: CoachPacketPresenter.copyAction) } icon: { Image(systemName: "doc.on.doc") }
                }
                .buttonStyle(NoopPrimaryButton())
                .disabled(!shown.copyAndShareEnabled)
                Button {
                    if let text = model.shareText { shared = SharedText(text: text) }
                } label: {
                    Label { Text(verbatim: CoachPacketPresenter.shareAction) } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .buttonStyle(NoopSecondaryButton())
                .disabled(!shown.copyAndShareEnabled)
            }
            if shown.showsRetry {
                Button { Task { await model.load() } } label: {
                    Label { Text(verbatim: CoachPacketPresenter.retryAction) } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(NoopPrimaryButton())
            }
        }
    }
}
