import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach, the one feature in NOOP that talks to the network.
///
/// Provider access is opt-in: iPhone can use a ChatGPT subscription; hosted API
/// providers use a key. Health summaries require separate consent. Credentials
/// stay in the Keychain; requests go directly to the selected provider.
///
/// This screen compiles against `AICoachEngine`'s public API (the macos-core agent's
/// contract): `hasKey`, `provider` / `provider.modelOptions`, `model`, `messages`,
/// `sending`, `errorText`, `setKey(_:)`, `clearKey()`, and `send(_:)`.
struct CoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    /// K8: used by "Save to Journal" — saves the coach advice as a journal entry with the text
    /// in the notes field, so it appears alongside other journal entries in Insights.
    @EnvironmentObject var repo: Repository

    /// Draft text in the composer (the question being typed).
    /// K15: the composer draft is persisted to UserDefaults so it survives an app relaunch.
    /// Restored on first appear, saved on every change. Keyed identically to the Android twin.
    private static let draftKey = "coach.composerDraft"
    @State private var draft: String = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    /// Pending key text in the setup card (never persisted here, handed to `setKey`).
    @State private var keyDraft: String = ""
    /// The replacement key, typed into the editor a rejection or Update key opens. Separate from
    /// `keyDraft` so the
    /// setup card's own field is untouched, and cleared on save so a secret does not sit in view state
    /// after it has been stored. Twin of the Kotlin `keyFix`.
    @State private var keyFix: String = ""
    @State private var showKeyEditor = false
    /// Whether the model selector is in free-text "Custom…" mode.
    @State private var customModel: Bool = false
    /// The id typed in the "Custom…" field.
    @State private var customModelDraft: String = ""
    @FocusState private var composerFocused: Bool

    /// K2: confirmation gate for the destructive "Clear conversation" toolbar action.
    @State private var showClearConfirm = false
    /// #2243: the coach settings, presented as a sheet. See `CoachSettingsView` for why a sheet
    /// rather than a push.
    @State private var showSettings = false

    // K4: on-device voice input for the composer (iOS only). macOS gets a no-op stub via
    // `#if os(iOS)` guards — the shared file keeps compiling for both targets.
    #if os(iOS)
    @StateObject private var voiceInput = CoachVoiceInput()
    @State private var showChatGPTConnection = false
    /// The iPhone redesign switch (Settings). On by default; off restores the classic screen.
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true
    #endif

    /// Sentinel tag for the "Custom…" entry in the model Picker.
    private let customModelTag = "__custom__"

    /// Contextual suggestion chips, derived from today's bands by `AICoachEngine.suggestions`
    /// (→ `CoachSuggestions`). Falls back to a stable generic set when there is no data. Recomputed
    /// on each body evaluation so a fresh sync immediately updates the chips.
    private var suggestions: [String] { coach.suggestions }

    var body: some View {
        coachScreen
        // macOS only. On iOS these actions live in `connectionMenu` instead, because this bar is hidden for
        // a primary tab root and VISIBLE in the pillar sheet, so leaving them here would render nothing
        // on the Coach tab and a duplicate of the menu in the sheet. One control per platform, reachable
        // in both of iOS's presentations. The `#if` sits on the CHAIN rather than inside the builder:
        // `ToolbarContentBuilder` is not relied on to accept an empty body, and the one other
        // conditional toolbar here (CoupledView) always yields an item on both platforms. (#2206)
        #if os(macOS)
        .toolbar {
            if coach.isConfigured {
                ToolbarItem {
                    Button {
                        toggleKeyEditor()
                    } label: {
                        Label("Update key", systemImage: "key.fill")
                    }
                }
                // K2: wipe the persisted + in-memory conversation. Confirmed, since it's destructive.
                ToolbarItem {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear conversation", systemImage: "trash")
                    }
                    .help("Clear the saved conversation")
                    .accessibilityLabel("Clear conversation")
                    .disabled(coach.messages.isEmpty)
                }
                ToolbarItem {
                    Button(role: .destructive) {
                        coach.disconnect()
                        keyDraft = ""
                    } label: {
                        Label("Disconnect", systemImage: "gearshape")
                    }
                    .help("Forget the saved key and disconnect")
                    .accessibilityLabel("Disconnect provider")
                }
            }
        }
        #endif
        // #2243: coach settings. `repo` rides along because the scaffold's environment is not
        // inherited by a sheet's own view tree.
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
                .environmentObject(coach)
                .environmentObject(repo)
        }
        #if os(iOS)
        .sheet(isPresented: $showChatGPTConnection) {
            ChatGPTConnectionView(
                session: coach.chatGPTSession,
                hasConversation: !coach.messages.isEmpty,
                onUse: {
                    coach.provider = .chatGPT
                    Task { await coach.refreshModels() }
                },
                onProfileChanged: { coach.clearConversation() }
            )
        }
        #endif
        .confirmationDialog(
            "Clear conversation?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { coach.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved conversation from this device. Coach history is your own notes, not medical advice.")
        }
        // K2 + K5 ordering matters and every step gates on an EMPTY transcript, so this is ONE `.task`
        // running sequentially (separate `.task`s can interleave at their await points on the same
        // actor): restore whatever the prior launch persisted, THEN surface a brief the scheduled
        // notification already generated (if any), THEN the interactive first-open brief — so
        // `startBriefIfNeeded` only ever runs over the network when BOTH of the above left the
        // transcript genuinely empty.
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            coach.retireStaleConversationIfNeeded()
            // Gated on the transcript BEFORE consuming. `consumeStoredBrief()` clears the unconsumed
            // flag, and `surfaceScheduledBrief` then drops the text if a transcript exists, so a brief
            // that arrived on a day with a conversation already open was consumed and thrown away, gone
            // for good. Android checked first and so only ever failed to SHOW it (#2087).
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
            await coach.startBriefIfNeeded()
        }
        // #1862: a question handed over by the Today launcher sheet. Cleared BEFORE sending so a view
        // rebuild mid-flight cannot send it twice, and gated on `isConfigured` so an unconfigured handoff
        // (which the launcher does not produce, but a future caller might) degrades to showing setup
        // rather than a failed request.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { return }
            await coach.send(prompt)
        }
        // K15: persist the composer draft so it survives an app relaunch.
        .onChangeCompat(of: draft) { newValue in
            UserDefaults.standard.set(newValue, forKey: Self.draftKey)
        }
        .onChangeCompat(of: coach.provider) { _ in
            showKeyEditor = false
            customModel = false
        }
        // K14: haptic feedback when a reply arrives (sending goes true → false).
        .onChangeCompat(of: coach.sending) { isSending in
            if !isSending && !coach.messages.isEmpty {
                triggerReplyHaptic()
            }
        }
        // A consent toggle AFTER the initial load re-checks the brief (the original `.task(id:)`
        // behaviour); the guard inside `startBriefIfNeeded` (messages.isEmpty) keeps this a no-op once
        // a conversation exists.
        .onChangeCompat(of: coach.dataConsent) { _ in
            Task { await coach.startBriefIfNeeded() }
        }
    }

    /// The redesigned conversation on iPhone (mockup D1) with the redesign on; the classic screen
    /// otherwise and on macOS. Both share every modifier on `body` (sheets, the brief/restore task, the
    /// pending-prompt handoff, draft persistence), so the switch changes presentation only.
    @ViewBuilder private var coachScreen: some View {
        #if os(iOS)
        if redesignEnabled {
            redesignCoachScreen
        } else {
            classicCoachScreen
        }
        #else
        classicCoachScreen
        #endif
    }

    private var classicCoachScreen: some View {
        ScreenScaffold(title: "Coach",
                       subtitle: "Ask about your charge, effort, rest and workouts, grounded in your own numbers.",
                       // Liquid finish: the same full-bleed day-of-sky backdrop Today + the other liquid
                       // tabs carry, so Coach sits in one atmosphere. Static + non-interactive; the frosted
                       // message/setup cards below sit on the opaque canvas and stay legible.
                       topBackground: liquidScaffoldSky()) {
            #if os(iOS)
            if coach.provider != .chatGPT {
                NoopButton("ChatGPT subscription", systemImage: "person.crop.circle", kind: .secondary) {
                    showChatGPTConnection = true
                }
            }
            #endif
            if coach.isConfigured {
                connectedHeader
                #if os(iOS)
                if coach.provider == .chatGPT { chatGPTPlanBar }
                #endif
                transcript
                if let error = coach.errorText, !error.isEmpty {
                    errorBanner(error)
                }
                if coach.provider != .chatGPT && (coach.keyRejected || showKeyEditor) { keyRepairPanel }
                // K7: show follow-up chips after each assistant reply (when the transcript is
                // non-empty and the last message is from the assistant and not mid-send);
                // otherwise show the initial contextual chips.
                if showFollowUpChips {
                    followUpChips
                } else {
                    suggestionChips
                }
                composer
                // K12: show a rough token estimate when the draft is non-empty.
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let tokens = coach.estimatedTokens(forDraft: draft) {
                    tokenEstimateBar(tokens)
                }
                privacyFootnote
            } else {
                setupCard
            }
        }
    }

    // MARK: - Setup (no key yet)

    private var setupCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text("Connect a provider")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                }

                providerIntroduction
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Provider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").strandOverline()
                    Picker("Provider", selection: $coach.provider) {
                        ForEach(AIProvider.selectableProviders) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #else
                    .pickerStyle(.segmented)
                    #endif
                    .accessibilityLabel("Provider")
                }

                if coach.provider == .chatGPT {
                    #if os(iOS)
                    NoopButton("Continue with ChatGPT", kind: .primary) {
                        showChatGPTConnection = true
                    }
                    Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.accent)
                    Text("Signing in does not grant access to your health data. Coach's data-sharing settings remain separate.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                    #endif
                } else {
                    legacyProviderFields
                }

                // Whatever the last attempt from THIS card ran into. The setup card had no error line
                // at all, so every way it can fail before a key is committed failed silently: a Refresh
                // the provider turned away, a Connect to a server that wants auth. The wearer saw a
                // button do nothing. No repair affordance beside it, unlike the chat: the key field is
                // already on screen, which is the whole point of the card.
                if let error = coach.errorText, !error.isEmpty {
                    errorBanner(error)
                }

                Divider().overlay(StrandPalette.hairline)
                privacyFootnote
            }
        }
    }

    @ViewBuilder
    private var providerIntroduction: some View {
        #if os(iOS)
        Text("Use your ChatGPT subscription or connect another provider with your own API key.")
        #else
        Text("Coach uses your own API key. Pick a provider, paste a key, and choose a model. Your key is stored securely in the Keychain and never leaves \(Platform.deviceNounPhrase) except as the request you make.")
        #endif
    }

    @ViewBuilder
    private var legacyProviderFields: some View {
        // Server URL (Custom / local LLM only)
        if coach.provider == .custom {
            VStack(alignment: .leading, spacing: 6) {
                Text("Server URL").strandOverline()
                TextField("http://localhost:11434/v1", text: $coach.customBaseURL)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .disableAutocorrection(true)
                    .accessibilityLabel("Server URL")
                Text("Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, or your own gateway. Stays on your network; nothing leaves \(Platform.deviceNounPhrase).")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Key header").strandOverline()
                Picker("Key header", selection: $coach.customAuthHeader) {
                    ForEach(CustomAIAuthHeader.allCases) { header in
                        Text(header.displayName).tag(header)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Key header")
                Text("Use Bearer for most local servers; use x-api-key for gateways that require the key in that header.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Model
        modelSelector

        // Key
        VStack(alignment: .leading, spacing: 6) {
            Text(coach.provider == .custom ? "API key (optional)" : "API key").strandOverline()
            SecureField(coach.provider == .custom
                        ? "Only if your server requires one"
                        : "Paste your \(coach.provider.displayName) API key", text: $keyDraft)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                .onSubmit { coach.provider == .custom ? connectCustom() : saveKey() }
                .accessibilityLabel("API key")
        }

        HStack {
            if coach.provider == .custom {
                NoopButton("Connect", systemImage: "link", kind: .primary, action: connectCustom)
                    .disabled(coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                NoopButton("Save key", systemImage: "key.fill", kind: .primary, action: saveKey)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
    }

    /// Model selector: a Picker over `coach.availableModels` with a free-text "Custom…" path and a
    /// "Refresh models" button that fetches the provider's live list.
    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model").strandOverline()
                Spacer()
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
                .help("Fetch the available models from \(coach.provider.displayName) using your saved key")
                .accessibilityLabel("Refresh models from provider")
            }

            Picker("Model", selection: modelPickerSelection) {
                ForEach(coach.availableModels, id: \.self) { m in
                    Text(verbatim: coach.modelDisplayName(m)).tag(m)
                }
                Divider()
                Text("Custom…").tag(customModelTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Model")

            if customModel {
                HStack(spacing: 8) {
                    TextField("Enter a model id", text: $customModelDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onSubmit(applyCustomModel)
                        .accessibilityLabel("Custom model id")

                    Button("Use", action: applyCustomModel)
                        .buttonStyle(NoopButtonStyle(.secondary))
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Use custom model")
                }
            }
        }
    }

    /// Bridges the model Picker to `coach.model`, with a "Custom…" sentinel that opens the free-text
    /// field instead of selecting a real id.
    private var modelPickerSelection: Binding<String> {
        Binding(
            get: { customModel ? customModelTag : coach.model },
            set: { newValue in
                if newValue == customModelTag {
                    customModel = true
                    if customModelDraft.isEmpty { customModelDraft = coach.model }
                } else {
                    customModel = false
                    coach.model = newValue
                }
            }
        )
    }

    private func applyCustomModel() {
        let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setCustomModel(trimmed)
        customModel = false
    }

    // MARK: - Connected state

    private var connectedHeader: some View {
        HStack(spacing: 10) {
            StatePill("\(coach.provider.displayName) · \(coach.modelDisplayName(coach.model))", tone: .accent, showsDot: true)
            Spacer()
            if coach.sending {
                StatePill("Thinking", tone: .accent, pulsing: true)
            }
            // #2243: the way through to what used to be stacked under this header.
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Coach settings"))
            #if os(iOS)
            connectionMenu
            #endif
        }
    }

    #if os(iOS)
    private var chatGPTPlanBar: some View {
        HStack(alignment: .top, spacing: NoopMetrics.gap) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Using ChatGPT plan")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let profile = coach.chatGPTSession.activeProfile {
                    Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Spacer()
            Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.accent)
        }
    }

    /// #2206: the same connection actions the toolbar above carries, drawn where iPhone can reach them.
    ///
    /// `RootTabView.tab(...)` wraps every primary tab root in a NavigationStack and applies
    /// `.toolbar(.hidden, for: .navigationBar)`, because each screen draws its own in-content header.
    /// So Clear conversation and Disconnect were being placed into a bar this platform never shows, and
    /// rendered nowhere. At the time, Disconnect was the only route back to the setup card: `isConfigured`
    /// gates that card away the moment a key is saved. The
    /// result was a key that could be set once and then never changed, with reinstalling the app the
    /// only way out, which on an offline-first app costs the wearer their entire history.
    ///
    /// macOS keeps the toolbar and does not get this, so its behaviour is untouched. On iOS the toolbar
    /// route is withdrawn rather than kept alongside: CoachView is presented twice on this platform, as
    /// a primary tab whose bar is hidden and as a pillar sheet whose bar is NOT (it draws a Done button
    /// and only hides the bar's background). Keeping both would render nothing on the tab and two of
    /// everything in the sheet. One control, reachable in both presentations.
    ///
    /// A menu rather than a bare button because it needs two taps to reach a destructive action,
    /// matching the protection the toolbar's separation gives, and because both actions belong to the
    /// same connection.
    ///
    /// Worth knowing before changing `disconnect()`: neither `hasKey` nor `isConfigured` is published,
    /// since `hasKey` reads the Keychain on each evaluation. The setup card reappears because
    /// `disconnect()` ALSO assigns the published `messages`, which is what re-evaluates the body. A
    /// future disconnect that stopped clearing the transcript would clear the key and leave this screen
    /// showing a chat for a connection that no longer exists. macOS has depended on the same coupling
    /// since its toolbar button existed, so this is a latent edge being written down, not a new one.
    private var connectionMenu: some View {
        Menu {
            connectionMenuItems
        } label: {
            // Same affordance DevicesView uses for its per-device menu, headline size included. The
            // size is not decoration here: the report this came from was that the option could not be
            // FOUND, so a control that matches the one the wearer has already learned, at a size worth
            // aiming at, is doing part of the work.
            Image(systemName: "ellipsis.circle")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityLabel("Connection")
    }

    /// The connection actions, shared by the classic menu above and the redesigned header's menu, so
    /// both presentations offer the identical set.
    @ViewBuilder private var connectionMenuItems: some View {
            if coach.provider == .chatGPT {
                Button {
                    showChatGPTConnection = true
                } label: {
                    Label("ChatGPT subscription", systemImage: "person.crop.circle")
                }
            } else {
                Button {
                    toggleKeyEditor()
                } label: {
                    Label("Update key", systemImage: "key.fill")
                }
            }
            Button {
                showClearConfirm = true
            } label: {
                Label("Clear conversation", systemImage: "trash")
            }
            .disabled(coach.messages.isEmpty)
            Button(role: .destructive) {
                coach.disconnect()
                keyDraft = ""
            } label: {
                Label("Disconnect", systemImage: "gearshape")
            }
    }
    #endif

    private var transcript: some View {
        StrandCard(padding: 16) {
            if coach.messages.isEmpty {
                emptyTranscript
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lazy so off-screen bubbles aren't all resident/laid-out at once; with the
                        // `maxStoredMessages` cap the transcript is already bounded, this keeps render cost flat.
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(coach.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if coach.sending {
                                typingIndicator.id("typing")
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // #697 parity: this screen builds its OWN ScrollView rather than going through
                    // ScreenScaffold, so it never inherited the scaffold's horizontal-bounce suppression and
                    // could still rubber-band left-right on a purely vertical scroll. Same modifier, same
                    // guard. `.basedOnSize` permits horizontal bounce only when content genuinely overflows
                    // the width, so nothing that is meant to scroll sideways is affected. (#1532 follow-up)
                    #if os(iOS)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    #endif
                    .frame(minHeight: 220, maxHeight: 460)
                    .onChangeCompat(of: coach.messages.count) { _ in
                        scrollToEnd(proxy)
                    }
                    .onChangeCompat(of: coach.sending) { _ in
                        scrollToEnd(proxy)
                    }
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask your first question")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Coach reads a summary of your last two weeks plus 30-day averages and recent workouts, then answers in plain language. Try a suggestion below.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: 520, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            // LLM replies arrive as Markdown (bold, lists, headings, tables),             // rendered with the chat-bubble-sized Strand theme. User bubbles stay
            // verbatim `Text` so typed `*`/`#` never turn into surprise formatting.
            // The reply sits on a frosted Charge-tinted surface, a card, not a flat box.
            // K8: context menu (long-press / right-click) with Copy, Share, and Save actions.
            HStack {
                Markdown(message.text)
                    .markdownTheme(.strand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: 16)
                    .frame(maxWidth: 560, alignment: .leading)
                    // K8: Copy / Share / Save context menu on assistant replies.
                    .contextMenu { assistantReplyActions(message.text) }
                Spacer(minLength: 48)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(message.text)")
        }
    }

    /// K8: Copy / Share / Save to Journal on an assistant reply. Shared by the classic and redesigned
    /// bubbles so both offer the same actions.
    @ViewBuilder
    private func assistantReplyActions(_ text: String) -> some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        ShareLink(item: text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            saveAdvice(text)
        } label: {
            Label("Save to Journal", systemImage: "square.and.pencil")
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(StrandPalette.accent)
            Text("Coach is thinking…")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: 16)
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        StrandCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StrandPalette.statusCritical)
                    .accessibilityHidden(true)
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    /// The inline replacement-key editor, shown after a rejection or an Update key action.
    ///
    /// Saving goes through `setKey`, which replaces the stored key and leaves the transcript alone. The
    /// existing route was the Disconnect button, which also wipes the conversation and un-commits a
    /// custom provider: far more than correcting a typo asks for, and named for an outcome the wearer
    /// is trying to avoid. Twin of the Kotlin editor in `CoachChat`.
    private var keyRepairPanel: some View {
        StrandCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if coach.keyRejected {
                    Text("Paste the corrected key. Your conversation is kept.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecureField("Paste your \(coach.provider.displayName) API key", text: $keyFix)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .onSubmit(saveRepairedKey)
                    .accessibilityLabel(coach.keyRejected ? Text("Corrected API key") : Text("API key"))
                HStack {
                    NoopButton("Update key", systemImage: "key.fill", kind: .primary, action: saveRepairedKey)
                        .disabled(keyFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if showKeyEditor && !coach.keyRejected {
                        Button("Cancel") { toggleKeyEditor() }
                    }
                }
            }
        }
    }

    /// Store the corrected key and drop it from view state. `setKey` clears the error and the rejection
    /// flag, which is what closes this panel.
    private func saveRepairedKey() {
        let trimmed = keyFix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        guard coach.errorText == nil else { return }
        keyFix = ""
        showKeyEditor = false
    }

    private func toggleKeyEditor() {
        showKeyEditor.toggle()
        if !showKeyEditor { keyFix = "" }
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { prompt in
                    Button {
                        send(prompt)
                    } label: {
                        Text(prompt)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(StrandPalette.surfaceInset, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    }
                    // Liquid tap response: the physical settle-inward every tappable liquid
                    // affordance gets, replacing the flat `.plain` press.
                    .buttonStyle(LiquidPressStyle())
                    .disabled(coach.sending)
                    .accessibilityLabel("Suggested prompt: \(prompt)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// K7: True when follow-up chips should show instead of the initial contextual chips —
    /// i.e. the transcript is non-empty, the last message is from the assistant, and a reply
    /// is not currently in flight.
    private var showFollowUpChips: Bool {
        guard let last = coach.messages.last, !coach.sending else { return false }
        return last.role == .assistant
    }

    /// K7: Follow-up suggestion chips shown after each assistant reply, so the user can dig
    /// deeper without typing. Uses the static `AICoachEngine.followUpSuggestions` list.
    private var followUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AICoachEngine.followUpSuggestions, id: \.self) { prompt in
                    Button {
                        send(prompt)
                    } label: {
                        Text(prompt)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(StrandPalette.surfaceInset, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(LiquidPressStyle())
                    .disabled(coach.sending)
                    .accessibilityLabel("Follow-up prompt: \(prompt)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// K12: A subtle token estimate shown below the composer when the draft is non-empty.
    /// Uses the ~4 chars/token heuristic — an estimate only, not an exact tokenizer count.
    private func tokenEstimateBar(_ tokens: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 10))
                .foregroundStyle(StrandPalette.textTertiary)
            Text("~\(tokens) tokens")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textTertiary)
            if tokens > 8000 {
                Text("· may exceed small context windows")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.top, 2)
    }

    /// The input bar, a frosted overlay surface holding the field + Send, so the composer reads as a
    /// distinct docked surface above the canvas rather than two floating controls.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Coach about your data…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(composerFocused ? StrandPalette.focusRing : StrandPalette.hairline, lineWidth: 1))
                .onSubmit { send(draft) }
                .accessibilityLabel("Question")

            // K4: on-device voice input (iOS only). macOS compiles this section out entirely.
            #if os(iOS)
            micButton
            #endif

            // Docked icon-only send affordance: a crisp accent-filled square sized to the
            // composer row (not the full 48pt control height), so it routes through the same
            // token fill/label colours as the button system without overpowering the field.
            Button {
                send(draft)
            } label: {
                Group {
                    if coach.sending {
                        ProgressView().controlSize(.small).tint(StrandPalette.goldDeepText)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(width: 44, height: 38)
                .foregroundStyle(StrandPalette.goldDeepText)
                .background(StrandPalette.accent,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(coach.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(8)
        .background(NoopPanelSurface(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }

    // MARK: - K4: Voice input (iOS only)

    #if os(iOS)
    /// Mic button: starts/stops on-device speech recognition. Disabled when the locale lacks
    /// on-device support or permission is denied; tapping when permission is not yet determined
    /// triggers the system prompt.
    private var micButton: some View {
        Button {
            toggleVoice()
        } label: {
            Group {
                if voiceInput.isRecording {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(StrandPalette.statusCritical)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canUseVoice ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                }
            }
            .frame(width: 36, height: 38)
            .background(StrandPalette.surfaceInset,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!micButtonEnabled)
        .help(voiceInput.statusMessage ?? "Ask out loud")
        .accessibilityLabel(voiceInput.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityHint(voiceInput.statusMessage ?? "Transcribes your question on-device")
        .task {
            // Pre-check on appear so the button reflects the right state without a tap.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { _ in }
            }
        }
    }

    /// Whether the mic button is tappable: not while sending, and only if voice is either
    /// already usable or permission hasn't been asked yet (first tap triggers the prompt).
    private var canUseVoice: Bool { voiceInput.canUseVoice }
    private var micButtonEnabled: Bool {
        !coach.sending && (canUseVoice || voiceInput.authorization == .notDetermined)
    }

    private func toggleVoice() {
        if voiceInput.isRecording {
            voiceInput.stopTranscribing { finalText in
                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Append to the draft (not replace) so a user can speak into existing text.
                    draft = draft.isEmpty ? trimmed : "\(draft) \(trimmed)"
                }
            }
        } else {
            // First tap with undetermined permission triggers the system prompt; if granted,
            // start transcribing immediately on the next tap. If already authorized, start now.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { state in
                    if state == .authorized {
                        voiceInput.startTranscribing { partial in
                            draft = partial
                        }
                    }
                }
            } else {
                voiceInput.startTranscribing { partial in
                    draft = partial
                }
            }
        }
    }
    #endif

    /// Where Coach's requests go, per provider. Shared by both layouts' footnotes.
    @ViewBuilder private var privacyFootnoteText: some View {
        if coach.provider == .chatGPT {
            Text("ChatGPT requests use your plan allowance. Metric summaries require your separate data-sharing consent.")
        } else {
            Text(coach.provider == .custom
                 ? "Coach talks only to the server URL you set. Point it at a local model (Ollama, LM Studio, llama.cpp) to keep everything on your own machine. Nothing is sent until you ask."
                 : "This is the only feature that leaves \(Platform.deviceNounPhrase). It sends a summary of your metrics to \(coach.provider.displayName) using your own key. Nothing is sent until you ask.")
        }
    }

    private var privacyFootnote: some View {
        Label {
            privacyFootnoteText
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        keyDraft = ""
    }

    /// Commit the Custom (local) provider: save an optional key, then connect on the entered URL.
    private func connectCustom() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            coach.setKey(trimmed)
            keyDraft = ""
        }
        coach.connectCustom()
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        Task { await coach.send(trimmed) }
    }

    /// K14: Trigger a subtle haptic when the Coach reply arrives. On iOS, a light impact feedback.
    /// macOS doesn't have an equivalent simple API, so it's a no-op there.
    private func triggerReplyHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// K8: Save a coach reply to the journal as a note, so it appears alongside other journal
    /// entries in Insights and can be reviewed later. Uses the existing journal API with a
    /// fixed question ("Coach advice") and the reply text in the notes field.
    private func saveAdvice(_ text: String) {
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(
                day: day,
                question: "Coach advice",
                answeredYes: true,
                notes: text
            )
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(StrandMotion.fade) {
            if coach.sending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = coach.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - iPhone redesign (mockup D1, design/round3/coach-profile.html)

#if os(iOS)
/// Geometry from mockup D1 with no `NoopTheme` token.
private enum CoachRedesignLayout {
    static let bubbleRadius: CGFloat = 20
    static let bubbleTail: CGFloat = 6
    static let bubbleHorizontal: CGFloat = 15
    static let bubbleVertical: CGFloat = 12
    static let bubbleInset: CGFloat = 48
    static let messageGap: CGFloat = 12
    static let inputHeight: CGFloat = 50
    static let inputLeading: CGFloat = 18
    static let inputTrailing: CGFloat = 8
    static let sendSymbol: CGFloat = 20
    static let micSymbol: CGFloat = 19
    static let micWidth: CGFloat = 38
    static let composerFade: Double = 0.92
    static let dot: CGFloat = 7
    static let dotGap: CGFloat = 4
    static let dotRise: CGFloat = 4
    static let dotCycle: Double = 1.2
    static let dotStagger: Double = 0.15
    static let dotRestOpacity: Double = 0.4
    static let headerVertical: CGFloat = 4
    static let scopeTint: Double = 0.16
}

extension CoachView {

    /// The redesigned conversation. Presentation only: sending, streaming, consent, voice input, the key
    /// editor and the connection actions are the same calls the classic screen makes.
    fileprivate var redesignCoachScreen: some View {
        VStack(spacing: 0) {
            redesignCoachHeader
            if coach.isConfigured {
                redesignTranscript
                    .safeAreaInset(edge: .bottom, spacing: 0) { redesignComposerArea }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                        if coach.provider != .chatGPT { chatGPTSubscriptionChip }
                        redesignSetupCard
                    }
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .padding(.vertical, NoopTheme.Layout.l)
                }
            }
        }
        .formKitAmbient(.coach)
    }

    // MARK: Header

    /// Title with the connection underneath, the connection menu (#2206: the only route to Update key,
    /// Clear conversation and Disconnect on this platform) and the Coach settings sheet.
    private var redesignCoachHeader: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            if coach.isConfigured {
                Menu {
                    connectionMenuItems
                } label: {
                    FormKitIconFace(systemImage: "ellipsis")
                }
                .accessibilityLabel("Connection")
            } else {
                Color.clear.frame(width: NoopTheme.Layout.minTouchTarget, height: NoopTheme.Layout.minTouchTarget)
            }
            VStack(spacing: 0) {
                Text("Coach")
                    .noopFont(.navTitle)
                    .accessibilityAddTraits(.isHeader)
                if coach.isConfigured {
                    Text(verbatim: "\(coach.provider.displayName) · \(coach.modelDisplayName(coach.model))")
                        .noopFont(.caption, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            if coach.isConfigured {
                NoopIconButton(systemImage: "slider.horizontal.3", accessibilityLabel: "Coach settings") {
                    showSettings = true
                }
            } else {
                Color.clear.frame(width: NoopTheme.Layout.minTouchTarget, height: NoopTheme.Layout.minTouchTarget)
            }
        }
        .padding(.horizontal, NoopTheme.Layout.s)
        .padding(.vertical, CoachRedesignLayout.headerVertical)
    }

    /// The route to the ChatGPT plan when another provider is in use (the classic screen's button).
    private var chatGPTSubscriptionChip: some View {
        Button {
            showChatGPTConnection = true
        } label: {
            NoopChip("ChatGPT subscription", systemImage: "person.crop.circle")
        }
        .buttonStyle(.noopPress)
    }

    // MARK: Transcript

    private var redesignTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CoachRedesignLayout.messageGap) {
                    redesignContextLine
                    if coach.messages.isEmpty {
                        redesignEmptyTranscript
                    }
                    ForEach(coach.messages) { message in
                        redesignBubble(message).id(message.id)
                    }
                    if coach.sending {
                        CoachTypingDots().id("typing")
                    }
                    if let error = coach.errorText, !error.isEmpty {
                        redesignErrorBanner(error)
                    }
                    if coach.provider != .chatGPT && (coach.keyRejected || showKeyEditor) {
                        redesignKeyRepairPanel
                    }
                    redesignPrivacyFootnote
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.vertical, NoopTheme.Layout.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChangeCompat(of: coach.messages.count) { _ in scrollToEnd(proxy) }
            .onChangeCompat(of: coach.sending) { _ in scrollToEnd(proxy) }
        }
    }

    /// What this conversation draws on. The scope chip appears ONLY while data sharing is on, since it
    /// states what is being sent; the plan line names the ChatGPT account in use.
    @ViewBuilder
    private var redesignContextLine: some View {
        VStack(spacing: NoopTheme.Layout.s) {
            if coach.dataConsent {
                HStack(spacing: NoopTheme.Layout.s) {
                    Image(systemName: "checkmark.shield.fill").accessibilityHidden(true)
                    Text("Using today's scores, sleep and workouts")
                }
                .noopFont(.pill, color: false)
                .foregroundStyle(NoopTheme.coach)
                .padding(.horizontal, NoopTheme.Layout.m)
                .frame(minHeight: NoopTheme.Layout.pillHeight)
                .background(Capsule().fill(NoopTheme.coach.opacity(CoachRedesignLayout.scopeTint)))
            }
            if coach.provider == .chatGPT {
                HStack(spacing: NoopTheme.Layout.s) {
                    if let profile = coach.chatGPTSession.activeProfile {
                        Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                            .lineLimit(1)
                    } else {
                        Text("Using ChatGPT plan")
                    }
                    Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                        .foregroundStyle(NoopTheme.textPrimary)
                }
                .noopFont(.caption, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
            } else {
                chatGPTSubscriptionChip
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var redesignEmptyTranscript: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text("Ask your first question")
                    .noopFont(.listTitle)
                Text("Coach reads a summary of your last two weeks plus 30-day averages and recent workouts, then answers in plain language. Try a suggestion below.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func redesignBubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: CoachRedesignLayout.bubbleInset)
                Text(message.text)
                    .noopFont(.body, color: false)
                    .foregroundStyle(NoopTheme.canvas)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, CoachRedesignLayout.bubbleHorizontal)
                    .padding(.vertical, CoachRedesignLayout.bubbleVertical)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: CoachRedesignLayout.bubbleRadius,
                                               bottomLeadingRadius: CoachRedesignLayout.bubbleRadius,
                                               bottomTrailingRadius: CoachRedesignLayout.bubbleTail,
                                               topTrailingRadius: CoachRedesignLayout.bubbleRadius,
                                               style: .continuous)
                            .fill(NoopTheme.textPrimary)
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            // Replies arrive as Markdown; user bubbles stay verbatim so a typed `*` never formats.
            // Context chips (mockup D1) are not drawn: a reply carries only its text, with no record of
            // which figures it was given, so any chips would be a guess.
            let shape = UnevenRoundedRectangle(topLeadingRadius: CoachRedesignLayout.bubbleRadius,
                                               bottomLeadingRadius: CoachRedesignLayout.bubbleTail,
                                               bottomTrailingRadius: CoachRedesignLayout.bubbleRadius,
                                               topTrailingRadius: CoachRedesignLayout.bubbleRadius,
                                               style: .continuous)
            HStack {
                Markdown(message.text)
                    .markdownTheme(.strand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, CoachRedesignLayout.bubbleHorizontal)
                    .padding(.vertical, CoachRedesignLayout.bubbleVertical)
                    .background {
                        ZStack {
                            shape.fill(.ultraThinMaterial)
                            shape.fill(NoopTheme.card)
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(NoopTheme.cardBorder, lineWidth: FormKitLayout.hairline))
                    .contextMenu { assistantReplyActions(message.text) }
                Spacer(minLength: CoachRedesignLayout.bubbleInset)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(message.text)")
        }
    }

    private func redesignErrorBanner(_ message: String) -> some View {
        NoopGlassCard {
            HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NoopTheme.recoveryLow)
                    .accessibilityHidden(true)
                Text(message)
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.recoveryLow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    /// The replacement-key editor (same `setKey` path, same rules as the classic panel).
    private var redesignKeyRepairPanel: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                if coach.keyRejected {
                    Text("Paste the corrected key. Your conversation is kept.")
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecureField("Paste your \(coach.provider.displayName) API key", text: $keyFix)
                    .textFieldStyle(.plain)
                    .formKitField()
                    .onSubmit(saveRepairedKey)
                    .accessibilityLabel(coach.keyRejected ? Text("Corrected API key") : Text("API key"))
                Button("Update key", action: saveRepairedKey)
                    .buttonStyle(NoopPrimaryButton())
                    .disabled(keyFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if showKeyEditor && !coach.keyRejected {
                    Button("Cancel") { toggleKeyEditor() }
                        .buttonStyle(NoopSecondaryButton())
                }
            }
        }
    }

    private var redesignPrivacyFootnote: some View {
        HStack(alignment: .top, spacing: NoopTheme.Layout.s) {
            Image(systemName: "lock.shield")
                .accessibilityHidden(true)
            privacyFootnoteText
                .fixedSize(horizontal: false, vertical: true)
        }
        .noopFont(.caption)
        .padding(.top, NoopTheme.Layout.s)
        .accessibilityElement(children: .combine)
    }

    // MARK: Composer

    /// Suggested prompts, the token estimate and the input bar, docked above the tab bar.
    private var redesignComposerArea: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NoopTheme.Layout.s) {
                    let prompts = showFollowUpChips ? AICoachEngine.followUpSuggestions : suggestions
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            send(prompt)
                        } label: {
                            NoopChip(verbatim: prompt)
                        }
                        .buttonStyle(.noopPress)
                        .disabled(coach.sending)
                        .accessibilityLabel(showFollowUpChips ? Text("Follow-up prompt: \(prompt)") : Text("Suggested prompt: \(prompt)"))
                    }
                }
                .padding(.horizontal, NoopTheme.Layout.m)
            }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tokens = coach.estimatedTokens(forDraft: draft) {
                Group {
                    if tokens > 8000 {
                        Text("~\(tokens) tokens") + Text(verbatim: " ") + Text("· may exceed small context windows")
                    } else {
                        Text("~\(tokens) tokens")
                    }
                }
                .noopFont(.caption)
                .padding(.horizontal, NoopTheme.Layout.m + CoachRedesignLayout.inputLeading)
            }
            redesignInputBar
                .padding(.horizontal, NoopTheme.Layout.m)
        }
        .padding(.top, NoopTheme.Layout.s)
        .padding(.bottom, NoopTheme.Layout.s)
        .background(
            LinearGradient(colors: [NoopTheme.canvas.opacity(0), NoopTheme.canvas.opacity(CoachRedesignLayout.composerFade)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var redesignInputBar: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            HStack(spacing: 0) {
                TextField("Ask Coach about your data…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .noopFont(.body, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .onSubmit { send(draft) }
                    .accessibilityLabel("Question")
                redesignMicButton
            }
            .padding(.leading, CoachRedesignLayout.inputLeading)
            .padding(.trailing, CoachRedesignLayout.inputTrailing)
            .frame(minHeight: CoachRedesignLayout.inputHeight)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(NoopTheme.control)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(NoopTheme.cardBorder, lineWidth: FormKitLayout.hairline))

            Button {
                send(draft)
            } label: {
                Group {
                    if coach.sending {
                        ProgressView().controlSize(.small).tint(NoopTheme.canvas)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: CoachRedesignLayout.sendSymbol, weight: .semibold))
                    }
                }
                .foregroundStyle(NoopTheme.canvas)
                .frame(width: CoachRedesignLayout.inputHeight, height: CoachRedesignLayout.inputHeight)
                .background(Circle().fill(NoopTheme.textPrimary))
            }
            .buttonStyle(.noopPress)
            .disabled(coach.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
    }

    /// K4 on-device voice input inside the field (same `CoachVoiceInput` and toggle as the classic mic).
    private var redesignMicButton: some View {
        Button {
            toggleVoice()
        } label: {
            Image(systemName: voiceInput.isRecording ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: CoachRedesignLayout.micSymbol, weight: .medium))
                .foregroundStyle(voiceInput.isRecording
                                 ? NoopTheme.recoveryLow
                                 : (canUseVoice ? NoopTheme.textPrimary : NoopTheme.textTertiary))
                .frame(width: CoachRedesignLayout.micWidth, height: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!micButtonEnabled)
        .accessibilityLabel(voiceInput.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityHint(voiceInput.statusMessage ?? "Transcribes your question on-device")
        .task {
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { _ in }
            }
        }
    }

    // MARK: Setup (no provider yet)

    private var redesignSetupCard: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
                HStack(spacing: NoopTheme.Layout.m) {
                    DomainIcon(systemImage: "sparkles", color: NoopTheme.coach)
                    Text("Connect a provider")
                        .noopFont(.sectionTitle)
                }
                providerIntroduction
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FormKitControlRow("Provider", showsDivider: false) {
                    Picker("Provider", selection: $coach.provider) {
                        ForEach(AIProvider.selectableProviders) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(NoopTheme.textSecondary)
                    .accessibilityLabel("Provider")
                }
                if coach.provider == .chatGPT {
                    Button("Continue with ChatGPT") { showChatGPTConnection = true }
                        .buttonStyle(NoopPrimaryButton())
                    Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.textPrimary)
                    Text("Signing in does not grant access to your health data. Coach's data-sharing settings remain separate.")
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    redesignLegacyProviderFields
                }
                if let error = coach.errorText, !error.isEmpty {
                    Text(error)
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.recoveryLow)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Error: \(error)")
                }
                FormKitDivider()
                redesignPrivacyFootnote
            }
        }
    }

    /// API-key and Custom provider fields: the same bindings and actions as `legacyProviderFields`.
    @ViewBuilder
    private var redesignLegacyProviderFields: some View {
        if coach.provider == .custom {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text("Server URL").noopFont(.footnote)
                TextField("http://localhost:11434/v1", text: $coach.customBaseURL)
                    .textFieldStyle(.plain)
                    .formKitField()
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Server URL")
                Text("Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, or your own gateway. Stays on your network; nothing leaves \(Platform.deviceNounPhrase).")
                    .noopFont(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text("Key header").noopFont(.footnote)
                Picker("Key header", selection: $coach.customAuthHeader) {
                    ForEach(CustomAIAuthHeader.allCases) { header in
                        Text(header.displayName).tag(header)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Key header")
                Text("Use Bearer for most local servers; use x-api-key for gateways that require the key in that header.")
                    .noopFont(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            HStack {
                Text("Model").noopFont(.footnote)
                Spacer()
                Button {
                    Task { await coach.refreshModels() }
                } label: {
                    Label("Refresh models", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(!coach.canRefreshModels)
                .accessibilityLabel("Refresh models from provider")
            }
            Picker("Model", selection: modelPickerSelection) {
                ForEach(coach.availableModels, id: \.self) { m in
                    Text(verbatim: coach.modelDisplayName(m)).tag(m)
                }
                Divider()
                Text("Custom…").tag(customModelTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(NoopTheme.textSecondary)
            .accessibilityLabel("Model")
            if customModel {
                HStack(spacing: NoopTheme.Layout.s) {
                    TextField("Enter a model id", text: $customModelDraft)
                        .textFieldStyle(.plain)
                        .formKitField()
                        .onSubmit(applyCustomModel)
                        .accessibilityLabel("Custom model id")
                    Button("Use", action: applyCustomModel)
                        .buttonStyle(.noopPress)
                        .noopFont(.button, color: false)
                        .foregroundStyle(NoopTheme.textPrimary)
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Use custom model")
                }
            }
        }
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            Text(coach.provider == .custom ? "API key (optional)" : "API key").noopFont(.footnote)
            SecureField(coach.provider == .custom
                        ? "Only if your server requires one"
                        : "Paste your \(coach.provider.displayName) API key", text: $keyDraft)
                .textFieldStyle(.plain)
                .formKitField()
                .onSubmit { coach.provider == .custom ? connectCustom() : saveKey() }
                .accessibilityLabel("API key")
        }
        if coach.provider == .custom {
            Button("Connect", action: connectCustom)
                .buttonStyle(NoopPrimaryButton())
                .disabled(coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
            Button("Save key", action: saveKey)
                .buttonStyle(NoopPrimaryButton())
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// Three bouncing dots while a reply is on its way (mockup D1 `.typing`). The loop never settles, so it
/// holds still under Reduce Motion, Low Power Mode, the in-app "Reduce motion" switch, or a covered
/// window (`NoopMotionState.poseStill`), showing three resting dots instead.
private struct CoachTypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    var body: some View {
        let still = motion.poseStill(reduceMotion)
        let shape = UnevenRoundedRectangle(topLeadingRadius: CoachRedesignLayout.bubbleRadius,
                                           bottomLeadingRadius: CoachRedesignLayout.bubbleTail,
                                           bottomTrailingRadius: CoachRedesignLayout.bubbleRadius,
                                           topTrailingRadius: CoachRedesignLayout.bubbleRadius,
                                           style: .continuous)
        TimelineView(.animation(paused: still)) { timeline in
            HStack(spacing: CoachRedesignLayout.dotGap) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = still ? nil : Self.phase(at: timeline.date, index: index)
                    Circle()
                        .fill(NoopTheme.textSecondary)
                        .frame(width: CoachRedesignLayout.dot, height: CoachRedesignLayout.dot)
                        .opacity(phase.map { CoachRedesignLayout.dotRestOpacity + (1 - CoachRedesignLayout.dotRestOpacity) * $0 }
                                 ?? CoachRedesignLayout.dotRestOpacity)
                        .offset(y: -CoachRedesignLayout.dotRise * (phase ?? 0))
                }
            }
            .padding(.horizontal, CoachRedesignLayout.bubbleHorizontal + NoopTheme.Layout.xs)
            .padding(.vertical, CoachRedesignLayout.bubbleVertical + NoopTheme.Layout.xs)
        }
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(NoopTheme.card)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(NoopTheme.cardBorder, lineWidth: FormKitLayout.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach is thinking")
    }

    /// Lift 0…1 for one dot: up over the first 30 % of the cycle, down by 60 %, resting after (the
    /// mockup's `typing` keyframes), each dot 0.15 s behind the last.
    private static func phase(at date: Date, index: Int) -> Double {
        let t = date.timeIntervalSinceReferenceDate - Double(index) * CoachRedesignLayout.dotStagger
        let cycle = CoachRedesignLayout.dotCycle
        let local = (t.truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle) / cycle
        if local < 0.3 { return local / 0.3 }
        if local < 0.6 { return 1 - (local - 0.3) / 0.3 }
        return 0
    }
}
#endif
