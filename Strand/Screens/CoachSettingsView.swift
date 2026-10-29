import SwiftUI
import StrandDesign

/// Coach settings, split out of `CoachView` so the coach screen is the conversation and nothing else
/// (#2243). Holds the surfaces that used to stack above the transcript: the data-sharing consent, the
/// two further opt-ins that depend on it, the editable coach instructions, and the morning brief.
///
/// Connection management (the provider pill, Update key, Clear conversation, Disconnect) stays on
/// `CoachView`, where both the conversation and the key editor are visible. The Kotlin twin
/// `CoachSettingsScreen` splits on the same line.
///
/// Presented as a sheet rather than pushed. CoachView appears in three places between the two
/// platforms (a macOS route, an iPhone tab root whose navigation bar is hidden, and an iPhone pillar
/// sheet), and a sheet is the one presentation that behaves the same in all three without depending on
/// an enclosing NavigationStack.
struct CoachSettingsView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    /// Morning-brief settings, read from `CoachBriefScheduler` on init exactly as `CoachView` did
    /// before the split. This screen can now be the first to render them.
    @State private var briefEnabled: Bool = CoachBriefScheduler.isEnabled
    @State private var briefMinutes: Int = CoachBriefScheduler.timeMinutes
    @State private var briefGenerating = false
    @State private var briefStatus: String?
    #if os(iOS)
    @State private var showChatGPTConnection = false
    /// The iPhone redesign switch (Settings). On by default; off restores the classic screen.
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true
    #endif

    /// The coach-instructions editor, collapsed until asked for.
    @State private var promptExpanded: Bool = false
    @State private var promptDraft: String = ""

    var body: some View {
        settingsScreen
        // Opening this screen is the moment a stale catalogue is worth refreshing: a key exists here by
        // definition, and the picker above is about to be read. Rate-limited and silent on failure.
        .task { await coach.refreshModelsIfStale() }
        #if os(iOS)
        .sheet(isPresented: $showChatGPTConnection) {
            ChatGPTConnectionView(session: coach.chatGPTSession,
                                  hasConversation: !coach.messages.isEmpty,
                                  onProfileChanged: { coach.clearConversation() })
        }
        #endif
    }

    /// The redesigned screen on iPhone (mockup D2) with the redesign on; the classic one otherwise and on
    /// macOS. The model refresh task and the ChatGPT sheet on `body` serve both.
    @ViewBuilder private var settingsScreen: some View {
        #if os(iOS)
        if redesignEnabled {
            redesignSettingsScreen
        } else {
            classicSettingsScreen
        }
        #else
        classicSettingsScreen
        #endif
    }

    private var classicSettingsScreen: some View {
        // Literals, not String(localized:): `title`/`subtitle` are LocalizedStringKey, which converts
        // from a string LITERAL only, so a String value does not type-check here. The catalog keys are
        // these exact English strings.
        //
        // Done goes in the scaffold's `trailing` slot rather than a .toolbar. ScreenScaffold is a bare
        // ScrollView with no NavigationStack, so a toolbar item presented in a sheet would render
        // nowhere, and a macOS sheet has no swipe-to-dismiss: that combination would leave this screen
        // with no way out. (#2206 is the same mistake in the other direction.)
        ScreenScaffold(title: "Coach settings",
                       subtitle: "What the coach may read, how it is told to answer, and when it writes to you.",
                       topBackground: liquidScaffoldSky(),
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                               .accessibilityLabel("Close coach settings")
                       }) {
            modelBar
            #if os(iOS)
            if coach.provider == .chatGPT {
                NoopButton("ChatGPT subscription", systemImage: "person.crop.circle", kind: .secondary) {
                    showChatGPTConnection = true
                }
            }
            #endif
            consentBar
            // v5: a SECOND opt-in, only meaningful once data access is on, folds a summary of the
            // new on-device signals (your strongest patterns + Lab Book) into the coach context.
            if coach.dataConsent { onDeviceSignalsBar }
            if coach.dataConsent && coach.provider == .gemini { multimodalChartBar }
            systemPromptBar
            morningBriefBar
        }
    }

    /// Which model answers, and the control that refreshes the list of them.
    ///
    /// This lives HERE rather than on the setup card because of where a key exists. `setupCard` renders
    /// only while `isConfigured` is false, which for a cloud provider means no key is stored, and the
    /// Refresh control is `.disabled(!coach.canRefreshModels)` — gated on having a key inside a screen that only
    /// appears when there is none. So for OpenAI, Anthropic and Gemini that button was permanently
    /// disabled and the live catalogue those three publish was unreachable. A key exists by definition
    /// on this screen, so the picker and the refresh both work.
    ///
    /// The PROVIDER deliberately stays on the setup card. A stored key records which provider it
    /// belongs to and is never sent anywhere else, so switching provider here would leave a key that
    /// cannot be used and a screen that cannot fix it. Kotlin twin: `CoachModelCard`.
    private var modelBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(coach.provider.displayName) · \(coach.modelDisplayName(coach.model))")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    Button {
                        Task { await coach.refreshModels() }
                    } label: {
                        Label("Refresh models", systemImage: "arrow.clockwise")
                            .font(StrandFont.footnote)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(StrandPalette.accent)
                    .disabled(!coach.canRefreshModels)
                    .accessibilityLabel("Refresh models from provider")
                }
                Picker("Model", selection: $coach.model) {
                    ForEach(coach.availableModels, id: \.self) { m in
                        Text(verbatim: coach.modelDisplayName(m)).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Model")
            }
        }
    }

    /// Explicit, revocable permission for the coach to read & send the user's data. Off by default.
    /// A frosted Charge-tinted card so it reads as part of the green Coach world, not a flat panel.
    private var consentBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.dataConsent ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(coach.dataConsent ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Let the coach use my data")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    // The ON line NAMES what a session carries rather than saying "workouts" and
                    // leaving the reader to guess how much that is: the sport, how long, how far and how
                    // hard, per session. This toggle is the only place someone is asked to agree to it.
                    // Android says the same sentence (#2033).
                    Text(coach.dataConsent
                         ? "On: your charge, rest, HRV and workouts are sent to the provider, each workout with its sport, duration, distance and heart rate."
                         : "Off: the coach answers generally and sends none of your metrics.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.dataConsent)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Let the coach use my data")
            }
        }
    }

    /// The v5 second opt-in: include a SUMMARY of the new on-device signals (strongest n-of-1 patterns +
    /// Lab Book markers). Summary-only, never raw readings, so the no-raw-egress posture holds.
    private var onDeviceSignalsBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.includeOnDeviceSignals ? "checklist.checked" : "checklist")
                    .foregroundStyle(coach.includeOnDeviceSignals ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Also share my patterns & Lab Book")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(coach.includeOnDeviceSignals
                         ? "On: a short summary of your strongest patterns and logged health numbers is added. Summaries only, never raw readings."
                         : "Off: only your core metrics are shared, not your patterns or Lab Book.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.includeOnDeviceSignals)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Also share my patterns and Lab Book with the coach")
            }
        }
    }

    /// K11: Third opt-in — send a chart image alongside the text when using Gemini's multimodal
    /// API. Only shown when the provider is Gemini. OFF by default.
    private var multimodalChartBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.multimodalChartEnabled ? "photo.badge.checkmark" : "photo")
                    .foregroundStyle(coach.multimodalChartEnabled ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send chart image to Gemini")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(coach.multimodalChartEnabled
                         ? "On: a chart snapshot of your trends is sent with each question. Gemini can analyze the visual."
                         : "Off: only text is sent. Enable to let Gemini see your charts.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.multimodalChartEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Send chart image to Gemini")
            }
        }
    }

    /// Editable system prompt, the instructions that frame the coach. Collapsed by default; expanding
    /// reveals a TextEditor bound to the engine (edits persist to UserDefaults and take effect on the
    /// next message) plus a Reset-to-default control.
    private var systemPromptBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: promptExpanded ? 10 : 0) {
                Button {
                    withAnimation(StrandMotion.fade) {
                        promptExpanded.toggle()
                        if promptExpanded { promptDraft = coach.customSystemPrompt }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(coach.hasCustomSystemPrompt ? StrandPalette.accent : StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Coach instructions")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text(coach.hasCustomSystemPrompt
                                 ? "Customised. Your edited instructions frame every reply."
                                 : "Edit how the coach thinks and talks. Takes effect on your next message.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: promptExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(promptExpanded ? "Collapse coach instructions" : "Edit coach instructions")

                if promptExpanded {
                    TextEditor(text: $promptDraft)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(8)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onChangeCompat(of: promptDraft) { newValue in
                            coach.customSystemPrompt = newValue
                        }
                        .accessibilityLabel("Coach instructions editor")

                    HStack {
                        Spacer()
                        Button {
                            coach.resetSystemPrompt()
                            promptDraft = coach.customSystemPrompt
                        } label: {
                            Label("Reset to default", systemImage: "arrow.uturn.backward")
                                .font(StrandFont.footnote)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StrandPalette.accent)
                        .disabled(!coach.hasCustomSystemPrompt)
                        .accessibilityLabel("Reset coach instructions to default")
                    }
                }
            }
        }
    }

    /// K5: the scheduled morning-brief notification settings — enable toggle, time-of-day picker, and an
    /// explicit "Generate now" button. Mirrors the `ScheduledDebugExport` settings row shape (TestCentreView).
    private var morningBriefBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: briefEnabled ? "sunrise.fill" : "sunrise")
                        .foregroundStyle(briefEnabled ? StrandPalette.accent : StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Morning brief").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Text(briefEnabled
                             ? "Your selected provider generates a readiness and training brief, delivered as a local notification."
                             : "Off: nothing is generated or sent on a schedule.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $briefEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Morning brief")
                }
                .onChangeCompat(of: briefEnabled) { on in briefEnabledChanged(on) }

                if briefEnabled {
                    Divider().overlay(StrandPalette.hairline)
                    HStack {
                        Text("Time").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: briefTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityLabel("Morning brief time")
                    }
                    Group {
                        #if os(iOS)
                        Text("NOOP uses your selected Coach connection to generate the brief. iPhone decides when background work runs, so delivery may be later than the selected time.")
                        #else
                        Text("At \(Platform.deviceNounPhrase == "Mac" ? "this time" : "or soon after"), NOOP will use your key to generate today's brief. Best-effort: \(Platform.deviceNounPhrase) decides exactly when a backgrounded app wakes.")
                        #endif
                    }
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    NoopButton(briefGenerating ? "Generating…" : "Generate now", systemImage: "sparkles", kind: .secondary) {
                        generateBriefNow()
                    }
                    .disabled(briefGenerating)
                    if let briefStatus {
                        Text(briefStatus).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    /// The brief switch moved: schedule or cancel it, reverting with a reason when notifications are off.
    private func briefEnabledChanged(_ on: Bool) {
        CoachBriefScheduler.setEnabled(on, generateBrief: { await coach.generateBrief() }) { outcome in
            if outcome == .denied {
                briefEnabled = false
                briefStatus = "Notifications are off for NOOP — enable them in Settings first."
            }
        }
    }

    private var briefTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = briefMinutes / 60
                c.minute = briefMinutes % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                briefMinutes = m
                CoachBriefScheduler.setTimeMinutes(m, generateBrief: { await coach.generateBrief() })
            }
        )
    }

    private func generateBriefNow() {
        Task {
            briefGenerating = true
            briefStatus = nil
            defer { briefGenerating = false }
            let text = await CoachBriefScheduler.generateNow { await coach.generateBrief() }
            if let text {
                coach.appendGeneratedBrief(text)
            } else {
                briefStatus = "Couldn't generate a brief right now — check your connection and data access."
            }
        }
    }
}

// MARK: - iPhone redesign (mockup D2, design/round3/coach-profile.html)

#if os(iOS)
/// Geometry from mockup D2 with no `NoopTheme` token.
private enum CoachSettingsRedesignLayout {
    static let connectionIcon: CGFloat = 52
    static let statusDot: CGFloat = 7
    static let editorMinHeight: CGFloat = 140
    static let editorMaxHeight: CGFloat = 240
}

extension CoachSettingsView {

    /// The redesigned settings sheet. Every switch is the engine's own binding (the data-sharing consent
    /// stays its own toggle, separate from signing in), and the brief uses the same scheduler calls.
    fileprivate var redesignSettingsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Coach settings")
                        .noopFont(.navTitle)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .noopFont(.button, color: false)
                        .foregroundStyle(NoopTheme.textPrimary)
                        .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                        .accessibilityLabel("Close coach settings")
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.s)

                redesignConnectionCard
                    .padding(.top, NoopTheme.Layout.m)
                redesignModelCard
                    .padding(.top, NoopTheme.Layout.cardGap)

                NoopSectionHeader("What Coach can see")
                FormKitCard {
                    FormKitToggleRow("Let the coach use my data",
                                     detail: coach.dataConsent
                                        ? "On: your charge, rest, HRV and workouts are sent to the provider, each workout with its sport, duration, distance and heart rate."
                                        : "Off: the coach answers generally and sends none of your metrics.",
                                     isOn: $coach.dataConsent, showsDivider: false)
                    if coach.dataConsent {
                        FormKitToggleRow("Also share my patterns & Lab Book",
                                         detail: coach.includeOnDeviceSignals
                                            ? "On: a short summary of your strongest patterns and logged health numbers is added. Summaries only, never raw readings."
                                            : "Off: only your core metrics are shared, not your patterns or Lab Book.",
                                         isOn: $coach.includeOnDeviceSignals)
                    }
                    if coach.dataConsent && coach.provider == .gemini {
                        FormKitToggleRow("Send chart image to Gemini",
                                         detail: coach.multimodalChartEnabled
                                            ? "On: a chart snapshot of your trends is sent with each question. Gemini can analyze the visual."
                                            : "Off: only text is sent. Enable to let Gemini see your charts.",
                                         isOn: $coach.multimodalChartEnabled)
                    }
                }

                NoopSectionHeader("Coach instructions")
                redesignInstructionsCard

                NoopSectionHeader("Morning brief")
                redesignBriefCard

                if coach.provider == .chatGPT {
                    FormKitFootnote("Your sign-in lives in this iPhone's Keychain. It is never in backups or widgets.")
                }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .formKitAmbient(.coachConnection)
    }

    /// Which provider answers and whether it is connected. On the ChatGPT plan the card opens the
    /// subscription screen (the classic "ChatGPT subscription" button).
    @ViewBuilder
    private var redesignConnectionCard: some View {
        let content = HStack(spacing: NoopTheme.Layout.m) {
            DomainIcon(systemImage: "sparkles", color: NoopTheme.coach, size: CoachSettingsRedesignLayout.connectionIcon)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: coach.provider.displayName)
                    .noopFont(.listTitle)
                HStack(spacing: NoopTheme.Layout.s) {
                    Circle()
                        .fill(coach.isConfigured ? NoopTheme.recovery : NoopTheme.textTertiary)
                        .frame(width: CoachSettingsRedesignLayout.statusDot, height: CoachSettingsRedesignLayout.statusDot)
                        .accessibilityHidden(true)
                    if coach.provider == .chatGPT, let profile = coach.chatGPTSession.activeProfile {
                        Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                            .noopFont(.footnote)
                            .lineLimit(1)
                    } else {
                        Text(coach.isConfigured ? "Connected" : "Not connected")
                            .noopFont(.footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if coach.provider == .chatGPT { FormKitChevron() }
        }
        if coach.provider == .chatGPT {
            Button { showChatGPTConnection = true } label: {
                NoopGlassCard { content }
            }
            .buttonStyle(.noopPress)
            .accessibilityHint(Text("ChatGPT subscription"))
            .formKitGutter()
        } else {
            NoopGlassCard { content }
                .formKitGutter()
        }
    }

    /// The model picker and its refresh (see `modelBar` for why it lives here), plus where history is kept.
    private var redesignModelCard: some View {
        FormKitCard {
            FormKitControlRow("Model", showsDivider: false) {
                Picker("Model", selection: $coach.model) {
                    ForEach(coach.availableModels, id: \.self) { m in
                        Text(verbatim: coach.modelDisplayName(m)).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(NoopTheme.textSecondary)
                .accessibilityLabel("Model")
            }
            FormKitDivider()
            Button {
                Task { await coach.refreshModels() }
            } label: {
                Label("Refresh models", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .noopFont(.listTitle, color: false)
                    .foregroundStyle(coach.canRefreshModels ? NoopTheme.textPrimary : NoopTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!coach.canRefreshModels)
            .accessibilityLabel("Refresh models from provider")
            FormKitControlRow("Conversation history") {
                FormKitValue("On this iPhone")
            }
        }
    }

    /// The editable system prompt: same engine binding, same reset, collapsed until asked for.
    private var redesignInstructionsCard: some View {
        FormKitCard {
            Button {
                withAnimation(NoopTheme.Motion.reduced) {
                    promptExpanded.toggle()
                    if promptExpanded { promptDraft = coach.customSystemPrompt }
                }
            } label: {
                FormKitControlRow("Coach instructions",
                                  detail: coach.hasCustomSystemPrompt
                                    ? "Customised. Your edited instructions frame every reply."
                                    : "Edit how the coach thinks and talks. Takes effect on your next message.",
                                  showsDivider: false) {
                    Image(systemName: promptExpanded ? "chevron.up" : "chevron.down")
                        .noopFont(.footnote, color: false)
                        .fontWeight(.semibold)
                        .foregroundStyle(NoopTheme.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(promptExpanded ? "Collapse coach instructions" : "Edit coach instructions")
            if promptExpanded {
                TextEditor(text: $promptDraft)
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: CoachSettingsRedesignLayout.editorMinHeight,
                           maxHeight: CoachSettingsRedesignLayout.editorMaxHeight)
                    .padding(NoopTheme.Layout.s)
                    .background(RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
                        .fill(NoopTheme.control))
                    .onChangeCompat(of: promptDraft) { newValue in
                        coach.customSystemPrompt = newValue
                    }
                    .accessibilityLabel("Coach instructions editor")
                Button {
                    coach.resetSystemPrompt()
                    promptDraft = coach.customSystemPrompt
                } label: {
                    Label("Reset to default", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(coach.hasCustomSystemPrompt ? NoopTheme.textPrimary : NoopTheme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .disabled(!coach.hasCustomSystemPrompt)
                .accessibilityLabel("Reset coach instructions to default")
            }
        }
    }

    /// The scheduled brief: same switch, time and "Generate now" as the classic card. iOS decides when the
    /// background work runs, and the copy says so plainly.
    private var redesignBriefCard: some View {
        FormKitCard {
            FormKitToggleRow("Morning brief",
                             detail: briefEnabled
                                ? "Your selected provider generates a readiness and training brief, delivered as a local notification."
                                : "Off: nothing is generated or sent on a schedule.",
                             isOn: $briefEnabled, showsDivider: false)
                .onChangeCompat(of: briefEnabled) { on in briefEnabledChanged(on) }
            if briefEnabled {
                FormKitControlRow("Time", detail: "Timing is up to iOS, so it can arrive late") {
                    DatePicker("", selection: briefTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Morning brief time")
                }
                FormKitDivider()
                Button(briefGenerating ? "Generating…" : "Generate now") { generateBriefNow() }
                    .buttonStyle(NoopSecondaryButton())
                    .disabled(briefGenerating)
                    .padding(.vertical, FormKitLayout.rowVertical)
                if let briefStatus {
                    Text(briefStatus)
                        .noopFont(.footnote)
                        .padding(.bottom, FormKitLayout.rowVertical)
                }
            }
        }
    }
}
#endif
