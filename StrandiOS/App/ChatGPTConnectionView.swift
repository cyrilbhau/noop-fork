#if os(iOS)
import SwiftUI
import StrandDesign

/// The account connection surface also provides an explicit, health-free inference check.
@MainActor
struct ChatGPTConnectionView: View {
    @ObservedObject var session: ChatGPTSession
    var hasConversation = false
    var onUse: (() -> Void)? = nil
    var onProfileChanged: () -> Void = {}
    @StateObject private var coordinator = ChatGPTSignInCoordinator()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("coach.chatGPTPlanNoticeAcknowledged") private var noticeAcknowledged = false
    @State private var showPlanNotice = false
    @State private var operation: Task<Void, Never>?
    @State private var testing = false
    @State private var result: String?
    @State private var failure: String?
    @State private var diagnostic: String?
    @State private var pendingAccountChange: AccountChange?
    @State private var showAccountChangeConfirmation = false
    /// The iPhone redesign switch (Settings). On by default; off restores the classic screen.
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true

    private enum AccountChange { case saved(String), add }

    private var activeProfile: ChatGPTProfile? {
        session.profiles.first { $0.id == session.activeProfileID }
    }

    var body: some View {
        NavigationStack {
            connectionContent
            .navigationTitle("ChatGPT subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: session.state) { _, state in
            if state == .ready && !noticeAcknowledged { showPlanNotice = true }
        }
        .onAppear {
            session.retryStorageIfUnavailable()
            if session.state == .ready && !noticeAcknowledged { showPlanNotice = true }
        }
        .alert("You're using your ChatGPT plan", isPresented: $showPlanNotice) {
            Button("Got it") { noticeAcknowledged = true }
        } message: {
            Text("Eligible requests use your existing plan allowance. You can manage Noop's usage in ChatGPT settings.")
        }
        .confirmationDialog("Start a new Coach conversation?", isPresented: $showAccountChangeConfirmation,
                            titleVisibility: .visible) {
            Button("Continue") { performAccountChange() }
            Button("Cancel", role: .cancel) { pendingAccountChange = nil }
        } message: {
            Text("Switching ChatGPT accounts starts a new conversation so earlier messages are not sent to the new account.")
        }
        .onDisappear {
            coordinator.cancel()
            operation?.cancel()
        }
    }

    /// The redesigned screen (mockup D2) with the redesign on; the classic one otherwise. The sign-in,
    /// account switching, test and disconnect actions are the same functions in both.
    @ViewBuilder private var connectionContent: some View {
        if redesignEnabled {
            redesignContent
        } else {
            classicContent
        }
    }

    private var classicContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        Text("Use your ChatGPT plan")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Connect an eligible Plus or Pro plan without an API key. Requests share your existing ChatGPT plan limits.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                        if let profile = activeProfile {
                            Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        Text(connectionDescription)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)

                        if session.profiles.count > 1 {
                            Picker("ChatGPT account", selection: Binding(
                                get: { session.activeProfileID ?? "" },
                                set: { requestAccountChange(.saved($0)) }
                            )) {
                                ForEach(session.profiles) { profile in
                                    Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                                        .tag(profile.id)
                                }
                            }
                            .disabled(coordinator.isAuthorizing || testing)
                        }
                        NoopButton("Continue with ChatGPT", kind: .primary) {
                            connect(profileID: session.activeProfileID)
                        }
                            .disabled(coordinator.isAuthorizing || testing)
                        if !session.profiles.isEmpty {
                            Button("Add another account") { requestAccountChange(.add) }
                                .buttonStyle(NoopButtonStyle(.tertiary))
                                .disabled(coordinator.isAuthorizing || testing)
                        }
                        if session.state == .ready, let onUse {
                            NoopButton("Use for Coach", systemImage: "sparkles", kind: .secondary) {
                                onUse()
                                dismiss()
                            }
                            .disabled(coordinator.isAuthorizing || testing)
                        }
                        if coordinator.isAuthorizing {
                            ProgressView("Waiting for sign-in…")
                                .font(StrandFont.footnote)
                            Button("Cancel sign-in") {
                                coordinator.cancel()
                                operation?.cancel()
                            }
                            .buttonStyle(NoopButtonStyle(.tertiary))
                        }
                        Button("Manage usage") {
                            openURL(URL(string: "https://chatgpt.com/settings/usage")!)
                        }
                        .buttonStyle(NoopButtonStyle(.tertiary))
                    }
                }

                if session.state == .ready {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                            Text("Check your connection")
                                .font(StrandFont.headline)
                            Text("This sends a short greeting without health data and verifies that your plan can complete a response.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                            NoopButton("Test connection", systemImage: "checkmark.circle", kind: .secondary) {
                                testConnection()
                            }
                            .disabled(testing || coordinator.isAuthorizing)
                            if testing { ProgressView("Checking connection…") }
                            if let result {
                                Text(verbatim: result)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .accessibilityIdentifier("chatgpt.connection.result")
                            }
                        }
                    }
                }

                if let error = failure ?? coordinator.statusError ?? session.lastError {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        Text(verbatim: error)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.statusCritical)
                            .accessibilityIdentifier("chatgpt.connection.error")
                        if let diagnostic {
                            Text(verbatim: diagnostic)
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Text("Signing in does not grant access to your health data. Coach's data-sharing settings remain separate.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)

                if activeProfile != nil {
                    Button("Disconnect ChatGPT", role: .destructive) { disconnectChatGPT() }
                    .buttonStyle(NoopButtonStyle(.tertiary))
                    .disabled(coordinator.isAuthorizing || testing)
                }
            }
            .padding(NoopMetrics.screenPadding)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }

    private var connectionDescription: LocalizedStringKey {
        switch session.state {
        case .signedOut: return "Sign in to connect your subscription."
        case .authorizing: return "Complete sign-in in the browser."
        case .signedInWithoutPlanPermission: return "Sign in again and allow this app to use your ChatGPT plan."
        case .ready: return "ChatGPT plan permission is enabled."
        case .refreshing: return "Renewing your connection…"
        case .reauthorizationRequired: return "Sign in again to reconnect your plan."
        case .unavailable: return "Your connection is temporarily unavailable."
        case .usageLimited: return "Review your plan usage before trying again."
        }
    }

    /// Cancels anything in flight and signs the active account out.
    private func disconnectChatGPT() {
        operation?.cancel()
        coordinator.cancel()
        operation = Task { await session.disconnect() }
    }

    private func requestAccountChange(_ change: AccountChange) {
        if case let .saved(id) = change, id == session.activeProfileID { return }
        pendingAccountChange = change
        if hasConversation { showAccountChangeConfirmation = true }
        else { performAccountChange() }
    }

    private func performAccountChange() {
        guard let change = pendingAccountChange else { return }
        pendingAccountChange = nil
        switch change {
        case let .saved(id):
            do {
                try session.selectProfile(id)
                onProfileChanged()
                result = nil
                failure = nil
                diagnostic = nil
            } catch { failure = error.localizedDescription }
        case .add: connect(profileID: nil)
        }
    }

    private func connect(profileID: String?) {
        failure = nil
        diagnostic = nil
        result = nil
        operation?.cancel()
        operation = Task {
            let previousProfileID = session.activeProfileID
            do {
                try await coordinator.authorize(
                    session: session,
                    profileID: profileID,
                    requestConsent: session.state == .signedInWithoutPlanPermission
                )
                if let previousProfileID, session.activeProfileID != previousProfileID {
                    onProfileChanged()
                }
            } catch is CancellationError {
                // Dismissal leaves the existing connection intact.
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func testConnection() {
        guard let profileID = session.activeProfileID else { return }
        let generation = session.requestGeneration
        testing = true
        failure = nil
        diagnostic = nil
        result = nil
        operation = Task {
            defer { testing = false }
            do {
                let token = try await session.validAccessToken(profileID: profileID)
                try Task.checkCancellation()
                guard session.activeProfileID == profileID,
                      session.requestGeneration == generation else { throw CancellationError() }
                let client = ChatGPTClient()
                let models = try await client.fetchModels(accessToken: token)
                try Task.checkCancellation()
                guard session.activeProfileID == profileID,
                      session.requestGeneration == generation else { throw CancellationError() }
                guard let model = models.first else {
                    failure = String(localized: "No models are currently available for this ChatGPT account.")
                    return
                }
                _ = try await client.send(accessToken: token, model: model.slug,
                                          instructions: "Reply briefly.",
                                          messages: [(.user, "Reply with exactly: Connected.")])
                try Task.checkCancellation()
                guard session.activeProfileID == profileID,
                      session.requestGeneration == generation else { throw CancellationError() }
                result = String(localized: "Connection verified with \(model.displayName).")
            } catch is CancellationError {
            } catch {
                if session.requestGeneration == generation && !Task.isCancelled {
                    failure = error.localizedDescription
                    diagnostic = (error as? ChatGPTRequestError)?.diagnosticSummary
                }
            }
        }
    }
}
// MARK: - Redesign (mockup D2, design/round3/coach-profile.html)

/// Geometry from mockup D2 with no `NoopTheme` token.
private enum ChatGPTConnectionLayout {
    static let icon: CGFloat = 52
    static let statusDot: CGFloat = 7
}

extension ChatGPTConnectionView {

    fileprivate var redesignContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard
                    .padding(.top, NoopTheme.Layout.s)
                Text("Connect an eligible Plus or Pro plan without an API key. Requests share your existing ChatGPT plan limits.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopTheme.Layout.sectionSide)
                    .padding(.top, NoopTheme.Layout.m)

                if session.profiles.count > 1 {
                    FormKitCard {
                        FormKitControlRow("ChatGPT account", showsDivider: false) {
                            Picker("ChatGPT account", selection: Binding(
                                get: { session.activeProfileID ?? "" },
                                set: { requestAccountChange(.saved($0)) }
                            )) {
                                ForEach(session.profiles) { profile in
                                    Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                                        .tag(profile.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(NoopTheme.textSecondary)
                            .disabled(coordinator.isAuthorizing || testing)
                        }
                    }
                    .padding(.top, NoopTheme.Layout.cardGap)
                }

                VStack(spacing: NoopTheme.Layout.s) {
                    Button("Continue with ChatGPT") { connect(profileID: session.activeProfileID) }
                        .buttonStyle(NoopPrimaryButton())
                        .disabled(coordinator.isAuthorizing || testing)
                    if session.state == .ready, let onUse {
                        Button {
                            onUse()
                            dismiss()
                        } label: {
                            Label("Use for Coach", systemImage: "sparkles")
                        }
                        .buttonStyle(NoopSecondaryButton())
                        .disabled(coordinator.isAuthorizing || testing)
                    }
                    if !session.profiles.isEmpty {
                        Button("Add another account") { requestAccountChange(.add) }
                            .buttonStyle(NoopSecondaryButton())
                            .disabled(coordinator.isAuthorizing || testing)
                    }
                    if coordinator.isAuthorizing {
                        ProgressView("Waiting for sign-in…")
                            .noopFont(.footnote)
                            .tint(NoopTheme.textSecondary)
                        Button("Cancel sign-in") {
                            coordinator.cancel()
                            operation?.cancel()
                        }
                        .buttonStyle(NoopSecondaryButton())
                    }
                }
                .formKitGutter()
                .padding(.top, NoopTheme.Layout.l)

                FormKitCard {
                    Button {
                        openURL(URL(string: "https://chatgpt.com/settings/usage")!)
                    } label: {
                        FormKitControlRow("Manage usage", showsDivider: false) {
                            Image(systemName: "arrow.up.right")
                                .noopFont(.footnote, color: false)
                                .foregroundStyle(NoopTheme.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, NoopTheme.Layout.cardGap)

                if session.state == .ready {
                    NoopSectionHeader("Check your connection")
                    NoopGlassCard {
                        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                            Text("This sends a short greeting without health data and verifies that your plan can complete a response.")
                                .noopFont(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                testConnection()
                            } label: {
                                Label("Test connection", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(NoopSecondaryButton())
                            .disabled(testing || coordinator.isAuthorizing)
                            if testing {
                                ProgressView("Checking connection…")
                                    .noopFont(.footnote)
                                    .tint(NoopTheme.textSecondary)
                            }
                            if let result {
                                Text(verbatim: result)
                                    .noopFont(.bodySmall)
                                    .accessibilityIdentifier("chatgpt.connection.result")
                            }
                        }
                    }
                    .formKitGutter()
                }

                if let error = failure ?? coordinator.statusError ?? session.lastError {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                        Text(verbatim: error)
                            .noopFont(.bodySmall, color: false)
                            .foregroundStyle(NoopTheme.recoveryLow)
                            .accessibilityIdentifier("chatgpt.connection.error")
                        if let diagnostic {
                            Text(verbatim: diagnostic)
                                .noopFont(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NoopTheme.Layout.sectionSide)
                    .padding(.top, NoopTheme.Layout.l)
                }

                FormKitFootnote("Signing in does not grant access to your health data. Coach's data-sharing settings remain separate.")
                    .padding(.top, NoopTheme.Layout.s)

                if activeProfile != nil {
                    FormKitCard {
                        Button(role: .destructive) { disconnectChatGPT() } label: {
                            Text("Disconnect ChatGPT")
                                .noopFont(.listTitle, color: false)
                                .foregroundStyle(NoopTheme.recoveryLow)
                                .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget, alignment: .leading)
                                .padding(.vertical, FormKitLayout.rowVertical)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(coordinator.isAuthorizing || testing)
                    }
                    .padding(.top, NoopTheme.Layout.l)
                    FormKitFootnote("Your sign-in lives in this iPhone's Keychain. It is never in backups or widgets.")
                }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .formKitAmbient(.coachConnection)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// The account and where its connection stands, in the words of `connectionDescription`.
    private var statusCard: some View {
        NoopGlassCard {
            HStack(spacing: NoopTheme.Layout.m) {
                DomainIcon(systemImage: "sparkles", color: NoopTheme.coach, size: ChatGPTConnectionLayout.icon)
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    if let profile = activeProfile {
                        Text(verbatim: profile.email.map { "\(profile.label) · \($0)" } ?? profile.label)
                            .noopFont(.listTitle)
                            .lineLimit(2)
                    } else {
                        Text("Use your ChatGPT plan")
                            .noopFont(.listTitle)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                        Circle()
                            .fill(session.state == .ready ? NoopTheme.recovery : NoopTheme.textTertiary)
                            .frame(width: ChatGPTConnectionLayout.statusDot, height: ChatGPTConnectionLayout.statusDot)
                            .accessibilityHidden(true)
                        Text(connectionDescription)
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formKitGutter()
        .accessibilityElement(children: .combine)
    }
}

#endif
