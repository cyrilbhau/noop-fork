import Foundation
import Combine
import Security
import WhoopStore
import StrandAnalytics
import StrandImport

// MARK: - AI Coach (the one networked feature, strictly opt-in, bring-your-own-key)
//
// NOOP is offline by design. This file is the single exception: when the user pastes their OWN
// API key for a provider they choose, NOOP can send a compact text summary of their metrics plus
// their question to that provider and surface coaching advice. Nothing leaves the device until a
// key is set AND a question is asked. We never embed our own key, never auto-send, and only ever
// transmit the small text context built in `buildContext()` + the running chat, no raw streams.
//
// Pure macOS: Foundation + URLSession + Security (Keychain). Compiles on macOS 13, Swift 5.
// Provider wire formats live in Providers/: OpenAI.swift, Anthropic.swift, Gemini.swift.

// MARK: - Chat model

/// One turn in the coaching conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

// MARK: - Secure key storage (Keychain)

/// Keychain Services wrapper for the user's API key. Uses a generic-password item under a fixed
/// service so the key never lands in UserDefaults, a plist, or on disk in the clear.
enum AIKeyStore {
    private static let service = "com.noop.aicoach"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// UserDefaults key recording which provider the stored API key belongs to, so one provider's key
    /// is never sent to another provider's endpoint (above all the arbitrary user-typed Custom URL).
    private static let ownerKey = "ai.keyProvider"

    /// The provider the stored key was saved for, or nil for a legacy key saved before this tracking.
    static var ownerProvider: String? { UserDefaults.standard.string(forKey: ownerKey) }

    /// Store (or replace) the API key for `owner`. Empty/whitespace input is treated as a clear.
    /// Returns true once the key is in the Keychain (or was cleared); false if the Keychain write
    /// failed, in which case the owner marker is left untouched so it never points at a key that
    /// isn't actually stored (#872). The live `read()`/`hasKey` gating already reads the real
    /// Keychain, so this is defensive tidying of the discarded write result, not a behaviour change.
    @discardableResult
    static func save(_ key: String, owner: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return true }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Delete any existing item first so we always insert a single, fresh value.
        SecItemDelete(baseQuery as CFDictionary)

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { return false }
        UserDefaults.standard.set(owner, forKey: ownerKey)
        return true
    }

    /// Read the stored API key, or nil if none is set.
    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else { return nil }
        return str
    }

    /// Remove any stored API key.
    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: ownerKey)
    }
}

// MARK: - Errors

/// User-facing failure reasons mapped to clear, non-crashing messages.
enum AICoachError: LocalizedError {

    /// Whether an HTTP status means the stored key itself was turned away, as opposed to the provider
    /// being busy, broken, or asked for something it does not have.
    ///
    /// Named rather than left as two literals in two switches because it is the hinge the key-repair
    /// affordance hangs on, and it decides what the wearer is told to go and do. Widen it and a rate
    /// limit starts demanding a new key; narrow it and the trap this exists to remove comes straight
    /// back. Byte-identical twin of the Kotlin `AiCoach.isKeyRejection`.
    static func isKeyRejection(_ status: Int) -> Bool { status == 401 || status == 403 }

    case noKey
    case emptyQuestion
    case badKey
    case rateLimited(String)
    case server(Int, String)
    case network(String)
    case decode
    case emptyReply(String)   // #1074: verbatim provider-error / empty-reply text (byte-parity with Android emptyReplyMessage)
    case keySaveFailed
    case badCustomURL(String)

    var errorDescription: String? {
        switch self {
        case .badCustomURL(let message):
            return message
        case .noKey:
            return "Add your own API key first to use the coach."
        case .keySaveFailed:
            return "Couldn't save the key to the Keychain. The key was not stored, so try again."
        case .emptyQuestion:
            return "Type a question for the coach."
        case .badKey:
            return "That API key was rejected. Check the key and the provider you selected."
        case .rateLimited(let detail):
            let extra = detail.isEmpty ? "" : " (\(detail))"
            return "The provider is rate-limiting requests right now. Wait a moment and try again.\(extra)"
        case .server(let code, let detail):
            let extra = detail.isEmpty ? "" : " - \(detail)"
            return "The provider returned an error (\(code))\(extra)."
        case .network(let detail):
            return "Network problem: \(detail). The coach is the only feature that needs the internet."
        case .decode:
            return "Couldn't read the provider's reply. Try again."
        case .emptyReply(let message):
            return message
        }
    }
}

// MARK: - Engine

/// Drives the AI Coach: holds the chat, the chosen provider/model, the secure key, and performs the
/// networked request. `@MainActor` so all `@Published` mutations are main-thread; the actual HTTP
/// call hops off-main via `URLSession`'s async API and results are applied back on the main actor.
@MainActor
final class AICoachEngine: ObservableObject {

    /// One account session for every presentation of Coach. Laziness avoids reading the
    /// subscription Keychain when the feature is unused, including on the macOS target.
    lazy var chatGPTSession: ChatGPTSession = {
        let value = injectedChatGPTSession ?? ChatGPTSession()
        observeChatGPT(value)
        return value
    }()

    private let injectedChatGPTSession: ChatGPTSession?
    private let chatGPTClient: ChatGPTClient
    private var sessionObservation: AnyCancellable?
    private var defaultsObservation: AnyCancellable?
    private var observedSessionGeneration: UInt64 = 0
    private var observedProfileID: String?
    private var observedSessionState: ChatGPTSessionState = .signedOut
    private var requestEpoch: UInt64 = 0
    private var cancellationActions: [UUID: () -> Void] = [:]
    private var foregroundID: UUID?
    private var streamingMessageID: UUID?
    private var lastMasterEnabled = CoachBriefScheduler.coachMasterEnabled
    private var chatGPTCatalog: [ChatGPTModel] = []
    private var catalogProfileID: String?
    private var catalogRefreshID: UUID?
    private var historyWriteTask: Task<Void, Never>?
    private var historyWriteGeneration: UInt64 = 0
    private var conversationProfileID: String?

    // Published state the UI binds to.
    @Published var messages: [ChatMessage] = []

    /// Local day the current transcript was last written on; nil while it is empty. Drives the day
    /// boundary in `send` — see `isStaleConversation`. Kotlin twin: `CoachViewModel.conversationDay`.
    private var conversationDay: Int?
    @Published var sending = false
    @Published var errorText: String?

    /// Whether the last failure was the provider turning the stored key away, as opposed to a rate
    /// limit, a server fault or the network.
    ///
    /// It exists because the rejection message tells the wearer to check their key while the screen
    /// offers no way to reach it: the coach shows the chat as soon as ANY key is stored, and a wrong
    /// key is still a stored key, so the only route back was a Disconnect that also throws the
    /// conversation away. This lets the error carry the field with it.
    ///
    /// It QUALIFIES `errorText` rather than standing on its own, and the view reads it only inside the
    /// branch that renders one, so it cannot leave a key editor open under no error. Assigned on every
    /// failure, so a rejection followed by a rate limit stops claiming to be a rejection. Twin of the
    /// Kotlin `CoachViewModel.keyRejected`.
    @Published var keyRejected = false

    /// #1862: a question handed over by the Today Coach launcher sheet, for `CoachView` to send on appear.
    ///
    /// The launcher owns no send, stream, error or consent surface of its own — duplicating those is how a
    /// second chat UI drifts from the first. It collects a question and hands it here; the Coach screen,
    /// which already has all of that, consumes it exactly once and clears it. Nil is the normal state, and
    /// setting it performs NO network work by itself.
    @Published var pendingPrompt: String?
    @Published var provider: AIProvider {
        didSet {
            guard provider != oldValue else { return }
            invalidateConnection()
            if sessionObservation != nil {
                chatGPTSession.invalidateRequests()
                observedSessionGeneration = chatGPTSession.requestGeneration
            }
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            if provider == .chatGPT {
                restoreChatGPTCatalog()
                if isConfigured { Task { await self.refreshModels(silent: true) } }
                errorText = nil
                keyRejected = false
                alignBriefOwner()
                return
            }
            // Reset the model list to the new provider's built-in options.
            availableModels = provider.modelOptions
            // Keep the model valid for the newly-selected provider.
            model = UserDefaults.standard.string(forKey: Self.providerModelKey(provider)) ?? provider.defaultModel
            if !model.isEmpty, !availableModels.contains(model) { availableModels.insert(model, at: 0) }
            // The message names a provider ("That API key was rejected", after a request only THIS
            // provider saw), so it cannot survive switching to a different one. Harmless while only the
            // chat rendered it; wrong now that the setup card does too, which is where switching
            // happens. Twin of the Kotlin `selectProvider`.
            errorText = nil
            keyRejected = false
            alignBriefOwner()
        }
    }
    @Published var model: String {
        didSet {
            if provider == .chatGPT {
                if let id = catalogProfileID { UserDefaults.standard.set(model, forKey: Self.chatGPTModelKey(id)) }
            } else {
                UserDefaults.standard.set(model, forKey: Self.modelKey)
                UserDefaults.standard.set(model, forKey: Self.providerModelKey(provider))
            }
        }
    }
    /// The model ids offered in the picker. Seeded from `provider.modelOptions`, reset when the
    /// provider changes, and optionally extended by `refreshModels()` with the provider's live list.
    @Published var availableModels: [String] = []
    /// Explicit permission for the coach to read & transmit the user's biometric data. OFF by
    /// default, until this is true, NO metrics are included in any request (only the question).
    @Published var dataConsent: Bool {
        didSet {
            UserDefaults.standard.set(dataConsent, forKey: Self.consentKey)
            if dataConsent != oldValue { invalidateConnection() }
        }
    }
    /// Base URL for the Custom (OpenAI-compatible) provider, e.g. `http://localhost:11434/v1` for a
    /// local LLM server. Only used when `provider == .custom`. Persisted so it survives relaunch.
    @Published var customBaseURL: String {
        didSet {
            UserDefaults.standard.set(customBaseURL, forKey: AIProvider.customBaseURLKey)
            if customBaseURL != oldValue { invalidateConnection() }
        }
    }
    @Published var customAuthHeader: CustomAIAuthHeader {
        didSet {
            UserDefaults.standard.set(customAuthHeader.rawValue, forKey: AIProvider.customAuthHeaderKey)
            if customAuthHeader != oldValue { invalidateConnection() }
        }
    }
    /// Whether the user has committed the Custom provider (tapped Connect with a base URL). Lets the
    /// keyless local path reach the chat without a stored key, while avoiding a flip mid-typing.
    @Published var customConnected: Bool {
        didSet { UserDefaults.standard.set(customConnected, forKey: Self.customConnectedKey) }
    }
    /// SECOND opt-in (v5): also fold a SUMMARY of the new on-device signals, your strongest n-of-1
    /// correlations and your Lab Book markers, into the coach context. OFF by default and gated behind
    /// `dataConsent` too, so it never adds anything without both consents. Summary-only: a few one-line
    /// sentences, NEVER raw readings, the anonymity / no-raw-egress posture is preserved.
    @Published var includeOnDeviceSignals: Bool {
        didSet {
            UserDefaults.standard.set(includeOnDeviceSignals, forKey: Self.onDeviceSignalsKey)
            if includeOnDeviceSignals != oldValue { invalidateConnection() }
        }
    }

    /// K11: THIRD opt-in — send a chart image alongside the text when using Gemini's multimodal
    /// API. OFF by default and gated behind `dataConsent` too. Only active when the provider is
    /// Gemini (the only provider with multimodal support in the app). When on, the Coach composer
    /// shows an "Attach chart" toggle; the rendered chart is sent as inline_data to Gemini.
    @Published var multimodalChartEnabled: Bool {
        didSet {
            UserDefaults.standard.set(multimodalChartEnabled, forKey: Self.multimodalChartKey)
            if multimodalChartEnabled != oldValue { invalidateConnection() }
        }
    }

    private let repo: Repository
    private let session: URLSession

    private static let providerKey = "ai.provider"
    private static let modelKey = "ai.model"
    private static let consentKey = "ai.dataConsent"
    private static let customConnectedKey = "ai.customConnected"
    private static let onDeviceSignalsKey = "ai.includeOnDeviceSignals"
    private static let multimodalChartKey = "ai.multimodalChartEnabled"
    private static let conversationProfileKey = "ai.chatGPT.conversationProfile"
    private static let historyPendingKey = "ai.coachHistoryWritePending"
    private static func providerModelKey(_ provider: AIProvider) -> String { "ai.model.\(provider.rawValue)" }
    private static func chatGPTCatalogKey(_ id: String) -> String { "ai.chatGPT.catalog.\(id)" }
    private static func chatGPTModelKey(_ id: String) -> String { "ai.chatGPT.model.\(id)" }
    /// UserDefaults key holding the user's EDITED system prompt. Absent (or blank) means "use the
    /// built-in default". Small text key, never a secret, so plain UserDefaults is fine. Read FRESH
    /// per request (see `systemPrompt`) so an edit takes effect on the very next message.
    static let systemPromptKey = "ai.systemPrompt"

    /// The built-in system prompt that frames every request. Anonymous, frames the assistant only as a
    /// coach. Exposed (read-only) so the UI's "Reset to default" can restore it and show it when nothing
    /// custom is stored. Editing the live prompt overrides this via `systemPromptKey`.
    static let defaultSystemPrompt = """
    You are an elite, supportive recovery and performance coach with a real training methodology. \
    You may be given a summary of the user's own wearable data (charge 0-100, effort 0-100, rest 0-100, \
    sleep duration and its deep/REM/light breakdown, sleep efficiency, HRV, resting heart rate) and \
    recent workouts. Charge is the daily recovery/readiness score, effort is the daily cardiovascular \
    load score, and rest is the nightly sleep-quality score. A dash in the data means that value was \
    NOT MEASURED that day — say so rather than treating it as a zero. \
    Coach using autoregulation:
    • Readiness → prescription: charge 67-100 = green light to build/push, higher effort is fine; \
    34-66 = maintain, quality over volume, keep it controlled; 0-33 = active recovery only \
    (Zone 2, mobility, extra sleep) and protect against accumulating effort debt.
    • Workout optimisation: progressive overload, polarised ~80/20 intensity, space hard sessions, \
    program deloads/periodisation, and treat sleep as the single biggest recovery lever.
    • Always cite the user's ACTUAL numbers, give a concrete plan (today and the week ahead), and \
    be specific, punchy and motivating - like a coach who knows them.
    If no data is provided, coach generally and invite them to turn on data access for personalised \
    advice. You are NOT a doctor - never diagnose; suggest a professional for genuine health concerns.
    Format replies in simple Markdown, chat-sized: short paragraphs, **bold** for key numbers, \
    bullet or numbered lists for plans, ### headings only when structure genuinely helps, and a \
    small table only for a week-ahead plan. No code blocks.
    """

    /// The system prompt actually sent, read FRESH from UserDefaults on every request so an edit in
    /// the settings takes effect on the next message, with no engine rebuild. A blank/absent stored
    /// value falls back to `defaultSystemPrompt`, so a user who clears it never sends an empty prompt.
    var systemPrompt: String {
        let stored = UserDefaults.standard.string(forKey: Self.systemPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return Self.defaultSystemPrompt
    }

    /// The user's stored prompt override, or the default when nothing custom is set. The UI binds its
    /// editor to this: writing persists the override; writing a blank string clears it (back to default).
    var customSystemPrompt: String {
        get { systemPrompt }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == Self.defaultSystemPrompt {
                UserDefaults.standard.removeObject(forKey: Self.systemPromptKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: Self.systemPromptKey)
            }
            objectWillChange.send()
        }
    }

    /// True when the user has an edited prompt that differs from the built-in default, gates the
    /// "Reset to default" affordance in the UI.
    var hasCustomSystemPrompt: Bool {
        let stored = UserDefaults.standard.string(forKey: Self.systemPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !(stored ?? "").isEmpty && stored != Self.defaultSystemPrompt
    }

    /// Restore the built-in system prompt by clearing the stored override.
    func resetSystemPrompt() {
        UserDefaults.standard.removeObject(forKey: Self.systemPromptKey)
        objectWillChange.send()
    }

    /// Contextual suggestion chips for the composer, derived from today's bands via `CoachSuggestions`.
    /// Reads only on-device `repo.days`; pure, byte-identical to the Android twin. Returns the stable
    /// generic fallback when there is no usable data for today.
    var suggestions: [String] { CoachSuggestions.suggestions(for: repo.days.last, recent: repo.days) }

    /// K7: Follow-up suggestion chips shown after each assistant reply. These are generic
    /// conversational follow-ups (not data-derived) so the user can dig deeper without typing.
    /// Byte-identical to the Android twin's `followUpSuggestions`.
    static let followUpSuggestions: [String] = [
        "Tell me more about that",
        "What should I do next?",
        "How does today compare to this week?",
        "Give me a specific action plan",
    ]

    /// K12: Rough token estimate for the next send, based on the current draft + context size.
    /// Uses the standard ~4 chars/token heuristic. This is an estimate only — actual token counts
    /// vary by tokenizer. Returns nil when the engine isn't configured (no context to estimate).
    func estimatedTokens(forDraft draft: String) -> Int? {
        guard isConfigured else { return nil }
        // Estimate the context size: system prompt + data context (rough — we don't build the
        // full context here to avoid a DB read on every keystroke). Use the last known context
        // size or a reasonable default.
        let systemPromptTokens = systemPrompt.count / 4
        // The data context is typically ~2000-4000 chars depending on the user's data.
        // Use a conservative estimate of 3000 chars (750 tokens) when consent is on.
        let contextTokens = dataConsent ? 750 : 50
        // History tokens: sum of all message texts in the windowed history.
        let historyTokens = windowedMessages().reduce(0) { $0 + $1.text.count / 4 }
        let draftTokens = draft.count / 4
        return systemPromptTokens + contextTokens + historyTokens + draftTokens
    }

    /// Used in place of the metrics context when the user has NOT granted data access.
    private let noConsentNote = """
    NOTE: The user has not granted access to their biometric data. Coach generally and encourage \
    them to enable "Let the coach use my data" for guidance tailored to their real numbers.
    """

    init(repo: Repository, session: URLSession = .shared, chatGPTSession: ChatGPTSession? = nil,
         chatGPTHTTP: URLSession? = nil) {
        self.repo = repo
        self.session = session
        self.injectedChatGPTSession = chatGPTSession
        self.chatGPTClient = ChatGPTClient(session: chatGPTHTTP ?? ChatGPTAuth.makeURLSession())

        // Restore persisted provider / model (falling back to sane defaults).
        let storedProvider = UserDefaults.standard.string(forKey: Self.providerKey)
            .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        self.provider = storedProvider

        let storedModel = storedProvider == .chatGPT ? nil :
            UserDefaults.standard.string(forKey: Self.providerModelKey(storedProvider))
                ?? UserDefaults.standard.string(forKey: Self.modelKey)
        // A persisted custom id is honoured even if it's not in the built-in list.
        if let storedModel, !storedModel.isEmpty {
            self.model = storedModel
        } else {
            self.model = storedProvider.defaultModel
        }

        // Seed the picker with the provider's built-in options; include any persisted custom id.
        var seeded = storedProvider.modelOptions
        if let storedModel, !storedModel.isEmpty, !seeded.contains(storedModel) {
            seeded.insert(storedModel, at: 0)
        }
        self.availableModels = seeded

        self.dataConsent = UserDefaults.standard.bool(forKey: Self.consentKey)
        self.customBaseURL = UserDefaults.standard.string(forKey: AIProvider.customBaseURLKey) ?? ""
        self.customAuthHeader = AIProvider.customAuthHeader
        self.customConnected = UserDefaults.standard.bool(forKey: Self.customConnectedKey)
        self.includeOnDeviceSignals = UserDefaults.standard.bool(forKey: Self.onDeviceSignalsKey)
        self.multimodalChartEnabled = UserDefaults.standard.bool(forKey: Self.multimodalChartKey)
        defaultsObservation = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.applyCoachMasterSwitch() }
            }
        if chatGPTSession != nil || storedProvider == .chatGPT {
            _ = self.chatGPTSession
            if storedProvider == .chatGPT { restoreChatGPTCatalog() }
        }
        alignBriefOwner()
    }

    // MARK: Key management

    /// True when a key is present in the Keychain.
    var hasKey: Bool { AIKeyStore.read() != nil }

    /// True once the coach can actually send: a stored key for the cloud providers, or, for the
    /// Custom (local) provider, a committed base URL (a key is optional there, as local servers
    /// usually need none). Gates the setup card vs. the live chat.
    var isConfigured: Bool {
        if provider == .chatGPT {
            guard chatGPTSession.activeProfileID != nil else { return false }
            switch chatGPTSession.state {
            case .ready, .refreshing, .usageLimited, .unavailable: return true
            default: return false
            }
        }
        return provider == .custom ? customConnected : resolvedKey != nil
    }

    var canRefreshModels: Bool { provider == .chatGPT ? isConfigured : resolvedKey != nil }
    var chatGPTIsBusy: Bool { chatGPTSession.state == .authorizing || chatGPTSession.state == .refreshing }
    var chatGPTNeedsReconnect: Bool {
        switch chatGPTSession.state {
        case .signedOut, .signedInWithoutPlanPermission, .reauthorizationRequired: return true
        default: return false
        }
    }

    func modelDisplayName(_ slug: String) -> String {
        guard provider == .chatGPT else { return slug }
        return chatGPTCatalog.first { $0.slug == slug }?.displayName ?? slug
    }

    func applyCoachMasterSwitch() {
        let enabled = CoachBriefScheduler.coachMasterEnabled
        guard enabled != lastMasterEnabled else { return }
        lastMasterEnabled = enabled
        if !enabled {
            invalidateConnection()
            if sessionObservation != nil { chatGPTSession.invalidateRequests() }
        }
    }

    /// Retry a temporarily locked credential store when work or the foreground resumes.
    func resumeChatGPTConnection() {
        guard provider == .chatGPT || sessionObservation != nil else { return }
        let connection = chatGPTSession
        guard connection.state == .unavailable else { return }
        connection.retryStorageIfUnavailable()
        chatGPTSessionChanged(connection)
    }

    private func alignBriefOwner() {
        var owner: String? = provider.rawValue
        if provider == .chatGPT {
            if let id = chatGPTSession.activeProfileID,
               chatGPTSession.state != .signedOut, chatGPTSession.state != .signedInWithoutPlanPermission {
                owner = "chatGPT:" + id
            } else { owner = nil }
        }
        CoachBriefScheduler.alignStoredBriefOwner(owner)
    }

    func disconnectChatGPT() async {
        invalidateConnection()
        await chatGPTSession.disconnect()
        if provider == .chatGPT { objectWillChange.send() }
    }

    private func invalidateConnection() {
        requestEpoch &+= 1
        for cancel in Array(cancellationActions.values) { cancel() }
        if let id = streamingMessageID, let index = messages.firstIndex(where: { $0.id == id }) {
            let text = messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text == "Today's brief" { messages.remove(at: index) }
            else { messages[index] = ChatMessage(id: id, role: .assistant, text: text + "\n\n*(stream interrupted)*") }
        }
        streamingMessageID = nil
        foregroundID = nil
        sending = false
        pendingPrompt = nil
        pendingChartImage = nil
    }

    private func observeChatGPT(_ value: ChatGPTSession) {
        observedSessionGeneration = value.requestGeneration
        observedProfileID = value.activeProfileID
        observedSessionState = value.state
        sessionObservation = value.objectWillChange.sink { [weak self, weak value] _ in
            // @Published emits before assignment. Read the coherent final session on the next turn.
            Task { @MainActor [weak self, weak value] in
                guard let self, let value else { return }
                self.chatGPTSessionChanged(value)
            }
        }
    }

    private func chatGPTSessionChanged(_ value: ChatGPTSession) {
        let oldProfile = observedProfileID
        let oldState = observedSessionState
        let profileChanged = oldProfile != value.activeProfileID
        if observedSessionGeneration != value.requestGeneration || profileChanged {
            observedSessionGeneration = value.requestGeneration
            observedProfileID = value.activeProfileID
            if provider == .chatGPT {
                invalidateConnection()
                if profileChanged {
                    if oldProfile != nil, !messages.isEmpty { clearConversation() }
                    droppedSummary = nil
                    droppedSummaryKey = []
                    restoreChatGPTCatalog()
                }
            }
        }
        observedSessionState = value.state
        if provider == .chatGPT { alignBriefOwner() }
        objectWillChange.send()
        if provider == .chatGPT, value.state == .ready,
           profileChanged || [.signedOut, .authorizing, .signedInWithoutPlanPermission, .reauthorizationRequired].contains(oldState) {
            Task { await self.refreshModels(silent: true) }
        }
    }

    private func restoreChatGPTCatalog() {
        let id = chatGPTSession.activeProfileID
        catalogProfileID = id
        chatGPTCatalog = id.flatMap { UserDefaults.standard.data(forKey: Self.chatGPTCatalogKey($0)) }
            .flatMap { try? JSONDecoder().decode([ChatGPTModel].self, from: $0) } ?? []
        availableModels = chatGPTCatalog.map(\.slug)
        let selected = id.flatMap { UserDefaults.standard.string(forKey: Self.chatGPTModelKey($0)) }
        model = selected.flatMap { availableModels.contains($0) ? $0 : nil } ?? availableModels.first ?? ""
        if let prior = UserDefaults.standard.string(forKey: Self.conversationProfileKey),
           let id, prior != id { clearConversation() }
    }

    private func tracked<T>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let id = UUID()
        let task = Task { @MainActor in try await operation() }
        cancellationActions[id] = { task.cancel() }
        defer { cancellationActions[id] = nil }
        return try await withTaskCancellationHandler(operation: {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        }, onCancel: { task.cancel() })
    }

    /// The key to send with a request: the stored key, or an empty string for the keyless Custom
    /// provider. `nil` means "not configured", the caller surfaces `.noKey`.
    private var resolvedKey: String? {
        guard provider != .chatGPT else { return nil }
        if let k = AIKeyStore.read() {
            // Only send the stored key to the provider it was SAVED for, never Bearer one provider's
            // key (e.g. a cloud OpenAI/Anthropic secret) to another provider's endpoint, above all the
            // arbitrary user-typed Custom URL. A legacy key with no recorded owner is assumed to belong
            // to a cloud provider, so it is never auto-sent to Custom.
            let owner = AIKeyStore.ownerProvider
            if owner == provider.rawValue { return k }
            if owner == nil && provider != .custom { return k }
        }
        return provider == .custom ? "" : nil
    }

    /// Commit the Custom (local) provider once the user has entered a server URL. Optionally stores a
    /// key first if they pasted one. Pulls the server's live model list so the picker isn't empty.
    func connectCustom() {
        let url = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        errorText = nil
        customConnected = true
        // Pull the server's model list; if the user hasn't picked one yet, default to the first.
        Task {
            await refreshModels()
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let first = availableModels.first {
                model = first
            }
        }
    }

    /// Disconnect entirely: forget any stored key and un-commit the Custom provider. The base URL is
    /// kept so reconnecting pre-fills it.
    func disconnect() {
        if provider == .chatGPT {
            invalidateConnection()
            Task { await self.disconnectChatGPT() }
            return
        }
        invalidateConnection()
        AIKeyStore.clear()
        customConnected = false
        // Retire the transcript with the connection. Kotlin has done this since the method existed
        // (CoachViewModel.disconnect) and this side never did, so returning to the setup screen on Apple
        // left the whole conversation sitting behind it — including whatever the user had told a coach
        // they were in the middle of disconnecting from.
        messages = []
        conversationDay = nil
        // The error belongs to the connection being retired, so it goes with it. Kotlin has cleared it
        // here since the method existed and this side never did: harmless while only the chat rendered
        // an error, and a visible defect the moment the setup card does too, because the card this
        // returns to would open carrying "That API key was rejected" above an empty key field, reading
        // as a verdict on the key about to be typed.
        errorText = nil
        keyRejected = false
        objectWillChange.send()
    }

    /// Store the user's pasted key securely. Clears any prior error. If the Keychain write fails the
    /// key is NOT saved, so surface that to the UI instead of silently proceeding (#872).
    func setKey(_ key: String) {
        guard provider != .chatGPT else { return }
        guard AIKeyStore.save(key, owner: provider.rawValue) else {
            errorText = AICoachError.keySaveFailed.errorDescription
            objectWillChange.send()
            return
        }
        invalidateConnection()
        errorText = nil
        // A stored key is no longer the rejected one. Deliberately leaves the transcript alone:
        // correcting a mistyped key is not a reason to lose the conversation, which is what routing
        // this through `disconnect` used to cost. Twin of the Kotlin `saveKey`.
        keyRejected = false
        objectWillChange.send() // `hasKey` is computed; nudge SwiftUI to re-read it.
        // #288: do NOT auto-fetch the provider's model list on key-save. For a cloud provider that GET
        // egresses to the provider the MOMENT a key is saved (IP + request timing + key-validity) — before
        // any send, in an app that is zero-network by default. The picker shows the curated models; the LIVE
        // list is pulled only when the user taps Refresh (an explicit action that is its own consent) or
        // sends. Local Custom servers still refresh on Connect.
    }

    /// Forget the stored key.
    func clearKey() {
        guard provider != .chatGPT else { disconnect(); return }
        invalidateConnection()
        AIKeyStore.clear()
        // Same reasoning as `disconnect`: clearing the key returns the user to the setup screen, and
        // Kotlin empties the transcript when it does. Leaving it meant a "clear my key" on Apple removed
        // the credential and kept the conversation.
        messages = []
        conversationDay = nil
        // The error belongs to the connection being retired, so it goes with it. Kotlin has cleared it
        // here since the method existed and this side never did: harmless while only the chat rendered
        // an error, and a visible defect the moment the setup card does too, because the card this
        // returns to would open carrying "That API key was rejected" above an empty key field, reading
        // as a verdict on the key about to be typed.
        errorText = nil
        keyRejected = false
        objectWillChange.send()
    }

    // MARK: Live model list

    /// Set a custom model id (any string). Adds it to the picker if it isn't already listed.
    func setCustomModel(_ id: String) {
        guard provider != .chatGPT else { return }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !availableModels.contains(trimmed) {
            availableModels.insert(trimmed, at: 0)
        }
        model = trimmed
    }

    /// Test seam (DEBUG only): lets a test stand in for the live `fetchModels` network call so it can
    /// control timing and which provider's ids come back. Production never sets this, so the real path
    /// below is byte-identical in release builds.
    #if DEBUG
    var fetchModelsOverride: ((_ provider: AIProvider, _ key: String) async throws -> [String])?
    var fullContextOverride: (() async -> String)?
    func waitForHistoryWritesForTesting() async { await historyWriteTask?.value }
    #endif

    /// Best-effort: GET the chosen provider's models endpoint with the saved key and merge the
    /// returned ids into `availableModels`. Never crashes; failures land in `errorText` and leave
    /// the existing list intact. Requires a saved key.
    /// When the live catalogue was last pulled for `provider`, keyed per provider so switching does
    /// not hide one provider's stale list behind another's refresh. Kotlin twin:
    /// `NoopPrefs.coachModelsRefreshedAt`.
    static func modelsRefreshedKey(_ provider: AIProvider) -> String {
        "ai.modelsRefreshed.\(provider.rawValue)"
    }

    /// How long a pulled catalogue is trusted. Kotlin twin: `MODEL_REFRESH_INTERVAL_MS`.
    static let modelRefreshInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Whether a catalogue last pulled at `last` is due another pull at `now`.
    ///
    /// Split out and `static` so the rule can be pinned without an engine: it decides how often the app
    /// talks to a provider unasked. A never-pulled catalogue (0) is stale, so the first visit fetches. A
    /// clock moved BACKWARDS gives a negative age and reads as fresh, keeping the cached list rather
    /// than refetching every visit until the clock catches up. Kotlin twin:
    /// `CoachViewModel.isCatalogueStale`.
    static func isCatalogueStale(last: TimeInterval, now: TimeInterval) -> Bool {
        now - last >= modelRefreshInterval
    }

    /// Pull the live catalogue at most once a week, so the picker offers what the provider sells today
    /// without this app shipping a build for every model release.
    ///
    /// Quiet about FAILURE: it passes `silent`, so `refreshModels` leaves the error surface untouched
    /// in both directions rather than this restoring it afterwards. Restoring would have raced — there
    /// is no re-entrancy guard here, so a manual Refresh tapped during the await would have had its
    /// result stomped by a stale snapshot on resume. Not touching the state cannot race with anything.
    ///
    /// Requires a stored key, so it cannot fire during first-run setup where there is nothing to
    /// authenticate with. Custom is excluded: `connectCustom()` already pulls its list, and its server
    /// is the user's own machine rather than a vendor catalogue.
    ///
    /// Only the LIST moves. The selected model is never changed underneath the user. Kotlin twin:
    /// `CoachViewModel.refreshModelsIfStale`.
    func refreshModelsIfStale() async {
        resumeChatGPTConnection()
        guard provider != .custom, canRefreshModels else { return }
        let key = provider == .chatGPT ? Self.modelsRefreshedKey(provider) + "." + (chatGPTSession.activeProfileID ?? "")
            : Self.modelsRefreshedKey(provider)
        let last = UserDefaults.standard.double(forKey: key)
        guard Self.isCatalogueStale(last: last, now: Date().timeIntervalSince1970) else { return }
        await refreshModels(silent: true)
    }

    /// `silent` leaves the error surface entirely alone, in both directions: an automatic refresh must
    /// neither wipe a message the user is still reading nor raise one they never asked for. Kotlin twin:
    /// the `silent` parameter on `CoachViewModel.refreshModels`.
    func refreshModels(silent: Bool = false) async {
        resumeChatGPTConnection()
        guard CoachBriefScheduler.coachMasterEnabled, !Task.isCancelled else { return }
        let capturedProvider = provider
        let epoch = requestEpoch
        let refreshID = UUID()
        catalogRefreshID = refreshID
        if !silent { errorText = nil; keyRejected = false }
        if capturedProvider == .chatGPT {
            guard let profile = chatGPTSession.activeProfileID, isConfigured else {
                if !silent { errorText = ChatGPTAuthError.signInRequired.localizedDescription }
                return
            }
            let generation = chatGPTSession.requestGeneration
            let current = { self.provider == .chatGPT && self.requestEpoch == epoch
                && self.catalogRefreshID == refreshID
                && self.chatGPTSession.activeProfileID == profile
                && self.chatGPTSession.requestGeneration == generation
                && CoachBriefScheduler.coachMasterEnabled && !Task.isCancelled }
            do {
                let models = try await tracked {
                    var token = try await self.chatGPTSession.validAccessToken(profileID: profile)
                    guard current() else { throw CancellationError() }
                    do { return try await self.chatGPTClient.fetchModels(accessToken: token) }
                    catch let error as ChatGPTRequestError where error.kind == .auth && !error.outputStarted {
                        guard current() else { throw CancellationError() }
                        token = try await self.chatGPTSession.validAccessToken(profileID: profile, forceRefresh: true)
                        guard current() else { throw CancellationError() }
                        return try await self.chatGPTClient.fetchModels(accessToken: token)
                    }
                }
                guard current() else { return }
                let previous = UserDefaults.standard.string(forKey: Self.chatGPTModelKey(profile))
                catalogProfileID = profile
                chatGPTCatalog = models
                availableModels = models.map(\.slug)
                model = previous.flatMap { availableModels.contains($0) ? $0 : nil } ?? availableModels.first ?? ""
                if let data = try? JSONEncoder().encode(models) {
                    UserDefaults.standard.set(data, forKey: Self.chatGPTCatalogKey(profile))
                }
                if models.isEmpty, !silent {
                    errorText = "No models are currently available for this ChatGPT account."
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970,
                                          forKey: Self.modelsRefreshedKey(capturedProvider) + "." + profile)
            } catch {
                guard current(), !(error is CancellationError) else { return }
                if let typed = error as? ChatGPTRequestError {
                    chatGPTSession.reportRequestFailure(typed, profileID: profile, generation: generation)
                }
                if !silent { setProviderError(error) }
            }
            return
        }
        guard let key = resolvedKey, let client = capturedProvider.legacyClient else {
            if !silent { errorText = AICoachError.noKey.errorDescription }
            return
        }
        do {
            let ids: [String]
            #if DEBUG
            if let override = fetchModelsOverride { ids = try await override(capturedProvider, key) }
            else { ids = try await client.fetchModels(key: key, session: session) }
            #else
            ids = try await client.fetchModels(key: key, session: session)
            #endif
            guard provider == capturedProvider, requestEpoch == epoch, !Task.isCancelled,
                  CoachBriefScheduler.coachMasterEnabled else { return }
            guard !ids.isEmpty else {
                if !silent { errorText = AICoachError.decode.errorDescription }
                return
            }
            let builtin = capturedProvider.modelOptions
            var merged = builtin + Set(ids).subtracting(builtin).sorted()
            if !merged.contains(model) { merged.insert(model, at: 0) }
            availableModels = merged
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: Self.modelsRefreshedKey(capturedProvider))
        } catch {
            guard provider == capturedProvider, requestEpoch == epoch, !silent,
                  !(error is CancellationError), CoachBriefScheduler.coachMasterEnabled else { return }
            setProviderError(error)
        }
    }

    // MARK: Sending

    /// Hard rolling cap on the STORED transcript. The network payload is separately windowed by
    /// `windowedMessages()` (`maxHistoryMessages`); this bounds the in-memory `messages` array — and the
    /// SwiftUI transcript rendered from it — so a long-lived session can't grow it without bound. `coach`
    /// is a single app-lifetime instance on `AppModel`, so before this an active chat grew `messages`
    /// until the process was killed: the "gets laggy the longer the app runs, reopening fixes it, feels
    /// like RAM" report. Cap >> the wire window, so it never changes what's sent. (parity with Android)
    private static let maxStoredMessages = 40
    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > Self.maxStoredMessages {
            messages.removeFirst(messages.count - Self.maxStoredMessages)
        }
    }

    // MARK: - K2: persisted conversation history

    /// Guards `loadPersistedMessagesIfNeeded()` so it only ever runs once per app launch, even if the
    /// Coach screen's `.task` re-fires (e.g. a tab re-select).
    private var didLoadPersistedMessages = false

    /// Load the conversation persisted by a PRIOR launch (PRD-K2), so relaunching doesn't lose it.
    /// Called from the Coach screen's `.task` (mirroring `startBriefIfNeeded`) rather than `init`,
    /// which is synchronous and runs for every screen the app builds, not just Coach. Best-effort: a
    /// store failure just leaves the transcript empty, matching pre-K2 behaviour — never crashes.
    func loadPersistedMessagesIfNeeded() async {
        resumeChatGPTConnection()
        alignBriefOwner()
        guard !didLoadPersistedMessages else { return }
        didLoadPersistedMessages = true
        let epoch = requestEpoch
        guard !UserDefaults.standard.bool(forKey: Self.historyPendingKey),
              messages.isEmpty, let store = await repo.storeHandle() else { return }
        guard let rows = try? await store.coachMessages(), !rows.isEmpty,
              epoch == requestEpoch, messages.isEmpty,
              !UserDefaults.standard.bool(forKey: Self.historyPendingKey) else { return }
        let owner = UserDefaults.standard.string(forKey: Self.conversationProfileKey)
        if provider == .chatGPT, rows.contains(where: { $0.provider == AIProvider.chatGPT.rawValue }) {
            guard let owner, owner == chatGPTSession.activeProfileID else { return }
        }
        if provider == .chatGPT, let owner, owner != chatGPTSession.activeProfileID { return }
        conversationProfileID = owner
        // Recover the day this transcript was last written on FROM THE ROWS. `conversationDay` lives in
        // memory, so a process restart brought it back nil, and `isStaleConversation(nil, ...)` is false
        // by design (nothing sent yet is never stale), which meant a restored conversation from any
        // previous day was never retired, by `send` or by anything else (#2087).
        let newest = rows.map(\.createdAt).max() ?? 0
        let lastDay = Self.localEpochDay(Date(timeIntervalSince1970: TimeInterval(newest)))
        // Retire by NOT restoring. The next append replaces the stored rows wholesale, so nothing is
        // deleted here and a transcript is never destroyed by merely opening the screen.
        guard !Self.isStaleConversation(lastEpochDay: lastDay, todayEpochDay: Self.localEpochDay()) else {
            return
        }
        messages = rows
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { ChatMessage(id: UUID(uuidString: $0.id) ?? UUID(),
                                role: ChatMessage.Role(rawValue: $0.role) ?? .user,
                                text: $0.text) }
        conversationDay = lastDay
    }

    /// Replace the ENTIRE persisted conversation with the current in-memory `messages`. Called once
    /// per completed send/brief (not per streamed chunk) so a streamed reply's several in-place text
    /// mutations don't hammer the store. Fire-and-forget; a store failure never blocks the UI — the
    /// in-memory transcript (what the user sees) is unaffected either way.
    private func persistMessages() {
        let snapshot = messages
        let providerID = provider.rawValue
        let owner = conversationProfileID
        historyWriteGeneration &+= 1
        let generation = historyWriteGeneration
        // Metadata is committed after SQLite, with a durable tombstone before it. A process death
        // between those writes must never relabel the preceding account's transcript as the new one.
        UserDefaults.standard.set(true, forKey: Self.historyPendingKey)
        UserDefaults.standard.synchronize()
        let previous = historyWriteTask
        historyWriteTask = Task {
            await previous?.value
            guard let store = await repo.storeHandle() else { return }
            let rows = snapshot.enumerated().map { index, message in
                CoachMessageRow(id: message.id.uuidString, role: message.role.rawValue, text: message.text,
                                 provider: providerID, createdAt: Int(Date().timeIntervalSince1970), orderIndex: index)
            }
            do { try await store.replaceCoachMessages(rows) } catch { return }
            guard historyWriteGeneration == generation else { return }
            if let owner { UserDefaults.standard.set(owner, forKey: Self.conversationProfileKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.conversationProfileKey) }
            UserDefaults.standard.set(false, forKey: Self.historyPendingKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// The Coach toolbar's "Clear conversation" action: wipes both the in-memory transcript and the
    /// persisted table. Fire-and-forget on the store side; the in-memory clear is immediate.
    func clearConversation() {
        invalidateConnection()
        didLoadPersistedMessages = true
        messages = []
        conversationDay = nil
        conversationProfileID = nil
        droppedSummary = nil
        droppedSummaryKey = []
        historyWriteGeneration &+= 1
        let generation = historyWriteGeneration
        UserDefaults.standard.set(true, forKey: Self.historyPendingKey)
        UserDefaults.standard.synchronize()
        let previous = historyWriteTask
        historyWriteTask = Task {
            await previous?.value
            guard let store = await repo.storeHandle() else { return }
            do { try await store.clearCoachMessages() } catch { return }
            guard historyWriteGeneration == generation else { return }
            UserDefaults.standard.removeObject(forKey: Self.conversationProfileKey)
            UserDefaults.standard.set(false, forKey: Self.historyPendingKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// K5: surface a brief generated by the SCHEDULED morning-brief notification as the first Coach
    /// message, with no network call — called once when the app opens via a tap on that notification.
    /// No-op if a conversation already exists, so it never duplicates into an active chat.
    func surfaceScheduledBrief(_ text: String) {
        alignBriefOwner()
        guard messages.isEmpty else { return }
        conversationProfileID = provider == .chatGPT ? chatGPTSession.activeProfileID : nil
        appendMessage(ChatMessage(role: .assistant, text: "Today's brief\n\n" + text))
        conversationDay = Self.localEpochDay()
        persistMessages()
    }

    /// Retire yesterday's in-memory chat when Coach is opened, before checking for today's
    /// scheduled brief. A process kept alive overnight does not reload persisted messages, so the
    /// one-time load check cannot clear that chat. Keep the stored rows until a new turn or brief
    /// replaces them, as the existing restored-chat path does.
    func retireStaleConversationIfNeeded() {
        guard Self.isStaleConversation(lastEpochDay: conversationDay,
                                       todayEpochDay: Self.localEpochDay()) else { return }
        messages = []
        conversationDay = nil
        droppedSummary = nil
        droppedSummaryKey = []
    }

    /// K5: append an explicitly-generated brief (the Coach settings "Generate now" button) as a new
    /// assistant message, unconditionally — unlike `surfaceScheduledBrief`, this always appends so a
    /// mid-conversation tap still shows the fresh brief.
    func appendGeneratedBrief(_ text: String) {
        retireStaleConversationIfNeeded()
        conversationProfileID = provider == .chatGPT ? chatGPTSession.activeProfileID : nil
        appendMessage(ChatMessage(role: .assistant, text: "Today's brief\n\n" + text))
        conversationDay = Self.localEpochDay()
        persistMessages()
    }

    /// K11: An optional chart image (base64-encoded PNG) to send with the next user message.
    /// Set by the composer's "Attach chart" toggle when multimodal is enabled and the provider
    /// is Gemini. Consumed (cleared) on the next send. nil when no image is attached.
    @Published var pendingChartImage: String?

    /// Send a question: append it, build the metrics context, call the chosen provider with the
    /// system prompt + context + running history, parse the reply, append it. Never throws/crashes;
    /// failures land in `errorText`.
    func send(_ userText: String) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorText = AICoachError.emptyQuestion.errorDescription; return }
        guard !sending, CoachBriefScheduler.coachMasterEnabled, !Task.isCancelled else { return }
        if provider == .chatGPT { chatGPTSessionChanged(chatGPTSession) }
        let ticket = UUID()
        foregroundID = ticket
        sending = true
        var changedTranscript = false
        defer {
            if foregroundID == ticket {
                foregroundID = nil
                sending = false
                if changedTranscript { persistMessages() }
            }
        }
        do {
            let connection = try await captureConnection()
            try requireCurrent(connection)
            retireStaleConversationIfNeeded()
            conversationDay = Self.localEpochDay()
            errorText = nil
            keyRejected = false
            appendMessage(ChatMessage(role: .user, text: trimmed))
            changedTranscript = true
            conversationProfileID = connection.profileID
            let context = await contextFor(connection)
            try requireCurrent(connection)
            try await summarizeDroppedMiddleIfNeeded(connection: connection)
            try requireCurrent(connection)
            let wire = wireMessages(context: context)
            let image = connection.provider == .gemini && connection.consent && multimodalChartEnabled ? pendingChartImage : nil
            pendingChartImage = nil
            await foregroundResponse(connection: connection, messages: wire, inlineImage: image)
        } catch {
            guard foregroundID == ticket, CoachBriefScheduler.coachMasterEnabled,
                  !(error is CancellationError), !Task.isCancelled else { return }
            setProviderError(error)
        }
    }

    /// Opening Coach can generate a brief only with the same master/data/connection gates as a send.
    func startBriefIfNeeded() async {
        resumeChatGPTConnection()
        if provider == .chatGPT { chatGPTSessionChanged(chatGPTSession) }
        guard CoachBriefScheduler.coachMasterEnabled, isConfigured, dataConsent,
              messages.isEmpty, !sending, !Task.isCancelled else { return }
        if provider == .chatGPT, chatGPTSession.state == .usageLimited { return }
        let ticket = UUID()
        foregroundID = ticket
        sending = true
        var changedTranscript = false
        defer {
            if foregroundID == ticket {
                foregroundID = nil
                sending = false
                if changedTranscript { persistMessages() }
            }
        }
        do {
            let connection = try await captureConnection()
            let context = await contextFor(connection)
            try requireCurrent(connection)
            guard messages.isEmpty else { return }
            errorText = nil
            keyRejected = false
            conversationDay = Self.localEpochDay()
            conversationProfileID = connection.profileID
            changedTranscript = true
            await foregroundResponse(connection: connection,
                                     messages: [(.user, context + "\n\n---\n\n" + Self.briefInstruction)],
                                     prefix: "Today's brief\n\n")
        } catch {
            guard foregroundID == ticket, CoachBriefScheduler.coachMasterEnabled,
                  !(error is CancellationError), !Task.isCancelled else { return }
            setProviderError(error)
        }
    }

    private func foregroundResponse(connection: CoachConnection,
                                    messages wire: [(role: ChatMessage.Role, content: String)],
                                    inlineImage: String? = nil, prefix: String = "") async {
        guard connectionIsCurrent(connection) else { return }
        let placeholder = ChatMessage(role: .assistant, text: prefix)
        appendMessage(placeholder)
        streamingMessageID = placeholder.id
        var accumulated = ""
        do {
            try await streamProvider(connection: connection, messages: wire, inlineImage: inlineImage) { delta in
                guard self.connectionIsCurrent(connection) else { return }
                accumulated += delta
                if let index = self.messages.firstIndex(where: { $0.id == placeholder.id }) {
                    self.messages[index] = ChatMessage(id: placeholder.id, role: .assistant, text: prefix + accumulated)
                }
            }
            try requireCurrent(connection)
            let clean = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = messages.firstIndex(where: { $0.id == placeholder.id }) {
                if clean.isEmpty { messages.remove(at: index) }
                else { messages[index] = ChatMessage(id: placeholder.id, role: .assistant, text: prefix + clean) }
            }
        } catch {
            guard connectionIsCurrent(connection) else { return }
            let partial = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = messages.firstIndex(where: { $0.id == placeholder.id }) {
                if partial.isEmpty { messages.remove(at: index) }
                else {
                    messages[index] = ChatMessage(id: placeholder.id, role: .assistant,
                                                  text: prefix + partial + "\n\n*(stream interrupted)*")
                }
            }
            if !(error is CancellationError), !Task.isCancelled { setProviderError(error) }
        }
        if streamingMessageID == placeholder.id { streamingMessageID = nil }
    }

    /// K5: The brief instruction shared by the interactive `startBriefIfNeeded()` (streamed into the
    /// chat) and the headless `generateBrief()` below (used by the scheduled morning-brief notification).
    /// Kept in one place so the two paths never drift.
    private static let briefInstruction = """
    Based on the data above, give me TODAY'S coaching brief in three short parts: \
    (1) my readiness in one line, citing charge, HRV and rest; \
    (2) exactly what training to do today and what to avoid; \
    (3) one specific thing to improve my charge. Be punchy and motivating.
    """

    /// K5: Generate today's coaching brief WITHOUT touching the visible chat transcript. Used by the
    /// scheduled morning-brief notification (`CoachBriefScheduler`), which can run with no Coach screen
    /// open and must never append to (or duplicate into) `messages`. Non-streaming (a background/BGTask
    /// context has no UI to stream into). Returns nil when not configured/consented, on any network
    /// failure, or when the reply is empty — the caller treats nil as "brief unavailable"; never throws.
    func generateBrief() async -> String? {
        resumeChatGPTConnection()
        guard CoachBriefScheduler.coachMasterEnabled, isConfigured, dataConsent, !Task.isCancelled else { return nil }
        if provider == .chatGPT, chatGPTSession.state == .usageLimited { return nil }
        do {
            let connection = try await captureConnection()
            let context = await contextFor(connection)
            try requireCurrent(connection)
            let reply = try await callProvider(connection: connection,
                                               messages: [(.user, context + "\n\n---\n\n" + Self.briefInstruction)])
            try requireCurrent(connection)
            let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        } catch { return nil }
    }

    /// Full data context = the metrics summary + recent workouts (+ an OPT-IN on-device-signals summary
    /// when the second consent is on). Used when the user has granted data access.
    func buildFullContext() async -> String {
        var ctx = buildContext()
        ctx += "\n\n" + (await recentWorkoutsBlock())
        // Derived stress: a single Baevsky Stress Index summary line over today's R-R, computed the same
        // way StressView does. Gated here under `dataConsent` (the caller only reaches buildFullContext()
        // with consent on), so it rides the SAME consent + text-only channel as the HRV/RHR summary, a
        // derived number, never raw R-R egress. Omitted when there aren't enough clean beats yet.
        if let line = await stressIndexLine() { ctx += "\n\n" + line }
        if includeOnDeviceSignals {
            let block = await onDeviceSignalsBlock()
            if !block.isEmpty { ctx += "\n\n" + block }
        }
        return ctx
    }

    /// One derived stress line for the coach context: the Baevsky Stress Index over TODAY's R-R, read
    /// via the same device-aware repository R-R union as `StressView`,
    /// then summarised to a single number with `StressIndex.stressIndex(rr:)`. Returns nil when the
    /// store is unavailable or there are too few clean beats (the histogram needs >= 20), so the line is
    /// simply absent, never a fabricated value. Summary-only: the raw R-R never leaves the device.
    func stressIndexLine() async -> String? {
        let cal = Calendar.current
        let from = Int(cal.startOfDay(for: Date()).timeIntervalSince1970)
        let to = Int(Date().timeIntervalSince1970)
        let rr = await repo.rrIntervals(from: from, to: to, limit: 200_000)
        guard let si = StressIndex.stressIndex(rr: rr) else { return nil }
        return Self.stressIndexSummary(si: si)
    }

    /// Pure formatter for the derived stress line, kept separate so it is unit-testable without a store.
    /// One summary number, labelled, with a plain-English note that it's an autonomic-balance proxy.
    static func stressIndexSummary(si: Double) -> String {
        "Stress (SI): \(Int(si.rounded())) (Baevsky Stress Index over today's R-R; higher means more sympathetic / under load; an autonomic-balance proxy, not a clinical figure)."
    }

    /// A SUMMARY-ONLY block of the new on-device signals, the user's strongest n-of-1 correlations
    /// (lag-aware EffectRanker) and a one-line roll-up of their Lab Book markers. Plain sentences, never
    /// raw readings: this rides the same text channel as the metrics summary, so the no-raw-egress posture
    /// holds. Gated by the caller on the second opt-in; returns "" when there's nothing worth adding.
    func onDeviceSignalsBlock() async -> String {
        var lines: [String] = []

        // 1. Strongest behaviour→outcome associations (EffectRanker over the journal × Charge).
        let entries = await repo.journalEntries()
        // Yes days and NO days, kept apart. A day with no journal row for the question lands in
        // neither, so an unanswered day is never counted as a No (BehaviorInsights.effect).
        var byBehaviour: [String: Set<String>] = [:]
        var controls: [String: Set<String>] = [:]
        for e in entries {
            if e.answeredYes { byBehaviour[e.question, default: []].insert(e.day) }
            else { controls[e.question, default: []].insert(e.day) }
        }
        if !byBehaviour.isEmpty {
            let outcomeByDay = Dictionary(
                repo.days.compactMap { d in d.recovery.map { (d.day, $0) } },
                uniquingKeysWith: { _, last in last })
            let ranked = EffectRanker.rank(behaviors: byBehaviour, controls: controls,
                                           outcomeByDay: outcomeByDay, outcome: "Charge")
                .filter { $0.effect.significant }
                .prefix(3)
            if !ranked.isEmpty {
                lines.append("STRONGEST PERSONAL PATTERNS (the user's own data — association, not cause):")
                for r in ranked { lines.append("  • " + r.sentence()) }
            }
        }

        // 2. Lab Book markers roll-up (count + latest of a few, never the full history).
        if let store = await repo.storeHandle() {
            var markerSummaries: [String] = []
            for category in LabMarkerCategory.allCases {
                let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
                let byKey = Dictionary(grouping: rows, by: { $0.markerKey })
                for (key, kRows) in byKey {
                    guard let latest = kRows.sorted(by: { $0.takenAt < $1.takenAt }).last else { continue }
                    let name = MarkerCatalog.definition(for: key)?.displayName ?? key
                    let value = latest.value.map { "\(LabBookFormat.value($0, key: key)) \(latest.unit)" } ?? latest.valueText ?? "—"
                    markerSummaries.append("\(name) \(value)")
                }
            }
            if !markerSummaries.isEmpty {
                lines.append("")
                lines.append("LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):")
                lines.append("  " + markerSummaries.prefix(8).joined(separator: ", "))
            }
        }

        return lines.joined(separator: "\n")
    }

    private enum CoachBackend {
        case legacy(any AIProviderClient, key: String)
        case chatGPT(profileID: String, generation: UInt64)
    }

    private struct CoachConnection {
        let provider: AIProvider
        let model: String
        let instructions: String
        let epoch: UInt64
        let consent: Bool
        let signals: Bool
        let backend: CoachBackend
        var profileID: String? {
            if case let .chatGPT(profileID, _) = backend { return profileID }
            return nil
        }
    }

    private func captureConnection() async throws -> CoachConnection {
        resumeChatGPTConnection()
        applyCoachMasterSwitch()
        try Task.checkCancellation()
        guard CoachBriefScheduler.coachMasterEnabled else { throw CancellationError() }
        let selected = provider
        let epoch = requestEpoch
        let backend: CoachBackend
        if selected == .chatGPT {
            guard isConfigured, let profile = chatGPTSession.activeProfileID else {
                throw chatGPTNeedsReconnect && chatGPTSession.state == .signedInWithoutPlanPermission
                    ? ChatGPTAuthError.planPermissionRequired : ChatGPTAuthError.signInRequired
            }
            let generation = chatGPTSession.requestGeneration
            if availableModels.isEmpty || model.isEmpty { await refreshModels() }
            try Task.checkCancellation()
            guard provider == selected, requestEpoch == epoch,
                  chatGPTSession.activeProfileID == profile, chatGPTSession.requestGeneration == generation,
                  CoachBriefScheduler.coachMasterEnabled else { throw CancellationError() }
            guard availableModels.contains(model), !model.isEmpty else {
                throw ChatGPTRequestError(kind: .model, code: "no_available_models")
            }
            backend = .chatGPT(profileID: profile, generation: generation)
        } else {
            guard let key = resolvedKey, let client = selected.legacyClient else { throw AICoachError.noKey }
            backend = .legacy(client, key: key)
        }
        return CoachConnection(provider: selected, model: model, instructions: systemPrompt, epoch: epoch,
                               consent: dataConsent, signals: includeOnDeviceSignals, backend: backend)
    }

    private func connectionIsCurrent(_ connection: CoachConnection) -> Bool {
        guard provider == connection.provider, requestEpoch == connection.epoch,
              CoachBriefScheduler.coachMasterEnabled, dataConsent == connection.consent,
              includeOnDeviceSignals == connection.signals else { return false }
        if case let .chatGPT(profile, generation) = connection.backend {
            return chatGPTSession.activeProfileID == profile && chatGPTSession.requestGeneration == generation
        }
        return true
    }

    private func requireCurrent(_ connection: CoachConnection) throws {
        try Task.checkCancellation()
        guard connectionIsCurrent(connection) else { throw CancellationError() }
    }

    private func contextFor(_ connection: CoachConnection) async -> String {
        guard connection.consent else { return noConsentNote }
        #if DEBUG
        if let override = fullContextOverride { return await override() }
        #endif
        return await buildFullContext()
    }

    private func setProviderError(_ error: Error) {
        keyRejected = false
        if let typed = error as? AICoachError {
            errorText = typed.localizedDescription
            if case .badKey = typed { keyRejected = true }
        } else if error is ChatGPTRequestError || error is ChatGPTAuthError {
            errorText = error.localizedDescription
        } else {
            errorText = AICoachError.network("The connection was interrupted").localizedDescription
        }
    }

    private func callProvider(connection: CoachConnection,
                              messages: [(role: ChatMessage.Role, content: String)]) async throws -> String {
        try requireCurrent(connection)
        switch connection.backend {
        case let .legacy(client, key):
            return try await tracked {
                try self.requireCurrent(connection)
                let reply = try await client.send(key: key, model: connection.model,
                                                  systemPrompt: connection.instructions,
                                                  messages: messages, session: self.session)
                try self.requireCurrent(connection)
                return reply
            }
        case .chatGPT:
            var text = ""
            try await streamProvider(connection: connection, messages: messages) { text += $0 }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func streamProvider(connection: CoachConnection,
                                messages: [(role: ChatMessage.Role, content: String)],
                                inlineImage: String? = nil,
                                onDelta: @escaping (String) -> Void) async throws {
        try requireCurrent(connection)
        let auth = connection.provider == .chatGPT ? chatGPTSession : nil
        try await tracked {
            try self.requireCurrent(connection)
            switch connection.backend {
            case let .legacy(client, key):
                try await client.streamWithImage(key: key, model: connection.model,
                                                  systemPrompt: connection.instructions, messages: messages,
                                                  inlineImage: inlineImage, session: self.session) { delta in
                    guard self.connectionIsCurrent(connection), !Task.isCancelled else { return }
                    onDelta(delta)
                }
            case let .chatGPT(profile, generation):
                guard let auth else { throw ChatGPTAuthError.signInRequired }
                var emitted = false
                do {
                    var token = try await auth.validAccessToken(profileID: profile)
                    try self.requireCurrent(connection)
                    let deliver = { (delta: String) in
                        guard self.connectionIsCurrent(connection), !Task.isCancelled else { return }
                        emitted = true
                        onDelta(delta)
                    }
                    do {
                        try await self.chatGPTClient.stream(accessToken: token, model: connection.model,
                                                           instructions: connection.instructions, messages: messages,
                                                           onDelta: deliver)
                    } catch let error as ChatGPTRequestError where error.kind == .auth && !error.outputStarted && !emitted {
                        try self.requireCurrent(connection)
                        token = try await auth.validAccessToken(profileID: profile, forceRefresh: true)
                        try self.requireCurrent(connection)
                        try await self.chatGPTClient.stream(accessToken: token, model: connection.model,
                                                           instructions: connection.instructions, messages: messages,
                                                           onDelta: deliver)
                    }
                    try self.requireCurrent(connection)
                    auth.reportRequestSuccess(profileID: profile, generation: generation)
                } catch {
                    if self.connectionIsCurrent(connection), let typed = error as? ChatGPTRequestError {
                        auth.reportRequestFailure(typed, profileID: profile, generation: generation)
                    }
                    throw error
                }
            }
            try self.requireCurrent(connection)
        }
    }

    /// Sliding window over the chat: the FIRST user turn (it carries the metrics context) plus the most
    /// recent `maxHistoryMessages`, dropping the middle. Sending the whole growing history crowds out the
    /// reply on small-context local servers (Ollama defaults to a 2048-token window, the Custom
    /// provider's main use case) and balloons token cost/latency on cloud providers. (parity with Android)
    /// True when a transcript last written on `lastEpochDay` should be retired before a question asked
    /// on `todayEpochDay` — i.e. the conversation crossed into a new local day.
    ///
    /// STRICTLY forward (`>`, never `!=`): a clock that moves BACKWARDS — the user flying west, a
    /// timezone change, an NTP correction — must not wipe a conversation they are in the middle of.
    /// Only real elapsed days retire a transcript. A nil `lastEpochDay` (nothing sent yet) is never
    /// stale. Kotlin twin: `CoachViewModel.isStaleConversation`.
    ///
    /// `nonisolated` because it is a pure function of its arguments. AICoachEngine is @MainActor, so
    /// without this the rule inherits that isolation and cannot be called from a synchronous test —
    /// which is exactly how the first attempt at this twin failed to compile. Isolating a function
    /// that touches no state buys nothing and costs its testability.
    nonisolated static func isStaleConversation(lastEpochDay: Int?, todayEpochDay: Int) -> Bool {
        guard let lastEpochDay else { return false }
        return todayEpochDay > lastEpochDay
    }

    /// Days since the epoch in the LOCAL calendar. Kotlin computes the same value with
    /// `LocalDate.now().toEpochDay()`.
    ///
    /// Counted with calendar day arithmetic from `startOfDay`, not by dividing an interval by 86,400:
    /// a day is not always 86,400 seconds (DST), and the rule only needs a value that increments
    /// exactly once per local midnight and orders correctly. Injectable so the tests never depend on
    /// the machine's clock or zone.
    nonisolated static func localEpochDay(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let epoch = Date(timeIntervalSince1970: 0)
        return calendar.dateComponents([.day], from: epoch, to: start).day ?? 0
    }

    ///
    /// K13: when the middle is dropped, a one-line summary of the dropped turns is prepended to the
    /// first user turn so the model retains context continuity (instead of seeing a gap). The summary
    /// is generated via the same provider, with a short prompt; on failure it degrades to the old
    /// behaviour (no summary, just the windowed set).
    private static let maxHistoryMessages = 10
    /// K13: the cached summary of the dropped middle, regenerated when the dropped set changes.
    private var droppedSummary: String?
    private var droppedSummaryKey: [String] = []

    private func windowedMessages() -> [ChatMessage] {
        guard messages.count > Self.maxHistoryMessages + 1,
              let firstUser = messages.firstIndex(where: { $0.role == .user }) else { return messages }
        let recentStart = messages.count - Self.maxHistoryMessages
        // If the first user turn already falls inside the recent window, that window covers it.
        if firstUser >= recentStart { return Array(messages.suffix(Self.maxHistoryMessages)) }
        // K13: inject the summary of the dropped middle by prepending it to the first user turn,
        // so the model sees continuity instead of a gap. We don't use a separate system message
        // because the Role enum only has .user/.assistant (providers map those to API roles).
        var windowed = [messages[firstUser]]
        if let summary = droppedSummary {
            let first = windowed[0]
            windowed[0] = ChatMessage(id: first.id, role: first.role, text: "\(summary)\n\n---\n\n\(first.text)")
        }
        windowed.append(contentsOf: messages[recentStart...])
        return windowed
    }

    /// K13: When the conversation overflows the sliding window, summarize the dropped middle turns
    /// into a single system message. Called before each send when the window would drop messages.
    /// Best-effort: on any failure, leaves `droppedSummary` nil (the old gap behaviour).
    private func summarizeDroppedMiddleIfNeeded(connection: CoachConnection) async throws {
        guard messages.count > Self.maxHistoryMessages + 1,
              let firstUser = messages.firstIndex(where: { $0.role == .user }) else { return }
        let recentStart = messages.count - Self.maxHistoryMessages
        guard firstUser < recentStart else { return }

        // The dropped middle is messages[firstUser+1 ..< recentStart]. Cache on its identity so we
        // don't re-summarize the same set on every send.
        let dropped = Array(messages[(firstUser + 1)..<recentStart])
        let keySignature = dropped.map { "\($0.role.rawValue):\($0.text)" }
        guard droppedSummaryKey != keySignature else { return }

        // Build a compact transcript of the dropped turns for the summarizer.
        let transcript = dropped.map { m in
            "\(m.role == .user ? "User" : "Coach"): \(m.text)"
        }.joined(separator: "\n")

        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, preserving the key advice and \
        any specific numbers or recommendations. This summary will be shown to you as context \
        for the ongoing conversation.\n\n\(transcript)
        """
        let wire: [(role: ChatMessage.Role, content: String)] = [
            (.user, "You are a concise summarizer. Summarize the conversation in 2-3 sentences.\n\n\(summaryPrompt)"),
        ]
        do {
            let summary = try await callProvider(connection: connection, messages: wire)
            try requireCurrent(connection)
            droppedSummaryKey = keySignature
            droppedSummary = "Summary of earlier conversation: \(summary.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            if error is CancellationError { throw error }
            if let typed = error as? ChatGPTRequestError,
               [.auth, .permission, .usage].contains(typed.kind) { throw typed }
            // A transient summarizer failure can still use the existing local history window.
        }
    }

    /// The chat as `(role, content)` pairs, with the metrics context prepended to the first user turn.
    private func wireMessages(context: String) -> [(role: ChatMessage.Role, content: String)] {
        var out: [(role: ChatMessage.Role, content: String)] = []
        var contextInjected = false
        for m in windowedMessages() {
            if m.role == .user && !contextInjected {
                contextInjected = true
                out.append((.user, context + "\n\n---\n\nQuestion: " + m.text))
            } else {
                out.append((m.role, m.text))
            }
        }
        return out
    }

    // MARK: - Context builder

    /// Build a compact plain-text summary of the user's recent data: last ~14 days of
    /// recovery/strain/sleep-hours/HRV/restingHR where present, plus 30-day averages, plus a few
    /// recent workouts. Kept well under ~1500 tokens. If there's no data, it says so.
    func buildContext() -> String {
        let days = repo.days // oldest → newest
        var lines: [String] = ["USER BIOMETRIC SUMMARY (the user's own wearable data):"]

        guard !days.isEmpty else {
            return """
            USER BIOMETRIC SUMMARY:
            No wearable data is available yet. Acknowledge this and give general, encouraging guidance \
            while inviting the user to sync their device so future advice can reference real numbers.
            """
        }

        // Last ~14 days, newest first for readability.
        let recent = Array(days.suffix(14)).reversed()
        lines.append("")
        lines.append("Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), "
                     + "deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:")
        for d in recent {
            lines.append("  " + dayLine(d))
        }

        // 30-day averages.
        let last30 = Array(days.suffix(30))
        lines.append("")
        lines.append("30-day averages:")
        lines.append("  charge: \(avgInt(last30.compactMap { $0.recovery }))"
                     + ", effort: \(avgOne(last30.compactMap { $0.strain }))"
                     + ", sleep: \(avgSleepHours(last30))h"
                     + ", HRV: \(avgInt(last30.compactMap { $0.avgHrv })) ms"
                     + ", RHR: \(avgInt(last30.compactMap { $0.restingHr.map(Double.init) })) bpm")
        // Additional vitals when present (#124, the coach used to see only recovery/strain/sleep/HRV/RHR).
        lines.append("  SpO2: \(avgInt(last30.compactMap { $0.spo2Pct }))%"
                     + ", respiration: \(avgOne(last30.compactMap { $0.respRateBpm }))/min"
                     + ", skin-temp deviation: \(avgOne(last30.compactMap { $0.skinTempDevC }))°C"
                     + ", steps: \(avgInt(last30.compactMap { $0.steps.map(Double.init) }))/day"
                     + ", active energy: \(avgInt(last30.compactMap { $0.activeKcalEst }))kcal/day")

        return lines.joined(separator: "\n")
    }

    /// Append recent workouts to an existing context string. Async (workouts are read from the store),
    /// so callers that want workouts in the context can await this and feed the result to `send`'s
    /// flow via the chat, kept separate so `buildContext()` stays synchronous per the spec.
    func recentWorkoutsBlock(limit: Int = 6) async -> String {
        let rows = await repo.workoutRows(days: 30) // newest first
        guard !rows.isEmpty else { return "Recent workouts: none recorded in the last 30 days." }
        let bodySystem = UnitSystem(
            rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let distanceSystem = UnitPrefs.resolveDistance(
            system: bodySystem,
            override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        var lines = ["Recent workouts (newest first):"]
        for w in rows.prefix(limit) {
            var parts = ["  \(dateString(w.startTs)) \(w.sport)"]
            if let dur = w.durationS { parts.append("\(Int((dur / 60).rounded())) min") }
            if let s = w.strain { parts.append("effort \(String(format: "%.1f", s))") }
            if let hr = w.avgHr { parts.append("avg HR \(hr)") }
            if let kcal = w.energyKcal { parts.append("\(Int(kcal.rounded())) kcal") }
            if let dist = w.distanceM {
                parts.append(UnitFormatter.distanceFromMeters(dist, system: distanceSystem))
            }
            lines.append(parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Formatting helpers

    /// `internal`, not private, so `AICoachSleepContextTests` can assert the emitted line directly.
    /// Swift's `buildContext()` takes no arguments (it reads the repo), unlike the Kotlin twin which is
    /// handed the day list — so without this the formatter has no seam and the Swift half of a change
    /// with fifteen Kotlin tests would ship untested.
    func dayLine(_ d: DailyMetric) -> String {
        var parts: [String] = [d.day + ":"]
        parts.append("charge " + (d.recovery.map { "\(Int($0.rounded()))" } ?? "—"))
        parts.append("effort " + (d.strain.map { String(format: "%.1f", $0) } ?? "—"))
        parts.append("rest " + (d.totalSleepMin.map { String(format: "%.1fh", $0 / 60) } ?? "—"))
        // The stage breakdown and efficiency, which the coach could not see at all: a user asked why it
        // said it had no access to sleep stages, and it was answering honestly — `rest 7.8h` was every
        // word it got about a night. These four sit on the SAME DailyMetric the line already reads, so
        // nothing new is plumbed; they were simply never included. (#124 widened this context once
        // before, for the same reason.)
        //
        // Always emitted, "—" when absent, like every other field here. A night with no staging then
        // says so rather than going quiet, which matters more than line length: the alternative — only
        // appending stages when present — gives the model a schema that changes shape between days and
        // invites it to read a missing field as a zero.
        parts.append("deep " + hoursOrDash(d.deepMin))
        parts.append("REM " + hoursOrDash(d.remMin))
        parts.append("light " + hoursOrDash(d.lightMin))
        parts.append("eff " + efficiencyPercentOrDash(d.efficiency))
        parts.append("HRV " + (d.avgHrv.map { "\(Int($0.rounded()))ms" } ?? "—"))
        parts.append("RHR " + (d.restingHr.map { "\($0)bpm" } ?? "—"))
        return parts.joined(separator: ", ")
    }

    /// Minutes as "1.4h", or "—" when the night has no value. Matches the `rest` field's format so a
    /// stage total and the total it is part of read on the same scale.
    private func hoursOrDash(_ minutes: Double?) -> String {
        minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—"
    }

    /// Efficiency as a percentage, NORMALISING the stored value first.
    ///
    /// `DailyMetric.efficiency` is not reliably a 0–1 fraction: it "arrives as % on some import paths",
    /// which `SleepView` and `StagesCard` each guard against inline with this same `> 1.5` test. A bare
    /// `* 100` would therefore hand the coach "eff 9400%" for an imported night — and a model given a
    /// nonsense number reasons about it confidently rather than ignoring it.
    ///
    /// 1.5 rather than 1.0 because a genuine fraction can exceed 1.0 only by floating-point noise, while
    /// a genuine percentage is 30–100 and nowhere near the threshold. Android's two copies of this guard
    /// split at 1.0 instead, which is a pre-existing divergence and not this change's to settle.
    func efficiencyPercentOrDash(_ raw: Double?) -> String {
        guard var e = raw, e > 0 else { return "—" }
        if e > 1.5 { e /= 100 }
        guard e > 0, e <= 1 else { return "—" }
        return "\(Int((e * 100).rounded()))%"
    }

    private func avgOne(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "—" }
        return String(format: "%.1f", xs.reduce(0, +) / Double(xs.count))
    }

    private func avgInt(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "—" }
        return "\(Int((xs.reduce(0, +) / Double(xs.count)).rounded()))"
    }

    private func avgSleepHours(_ days: [DailyMetric]) -> String {
        let mins = days.compactMap { $0.totalSleepMin }
        guard !mins.isEmpty else { return "—" }
        return String(format: "%.1f", (mins.reduce(0, +) / Double(mins.count)) / 60)
    }

    private func dateString(_ ts: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
