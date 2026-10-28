import AuthenticationServices
import Combine
import Foundation
import UIKit

/// Presents the iPhone authentication sheet while a separate loopback listener receives OAuth.
/// HTTP loopback delivery in this arrangement must be verified on the owner's physical iPhone.
@MainActor
final class ChatGPTSignInCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isAuthorizing = false
    @Published private(set) var statusError: String?

    private enum Failure: LocalizedError {
        case alreadyAuthorizing, noWindow, browserUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyAuthorizing: return "A ChatGPT sign-in is already running."
            case .noWindow: return "Open NOOP on your iPhone to sign in with ChatGPT."
            case .browserUnavailable: return "Couldn't open ChatGPT sign-in. Try again."
            }
        }
    }

    private var webSession: ASWebAuthenticationSession?
    private var listener: ChatGPTLoopbackListener?
    private var activeTask: Task<Void, Error>?
    private var activeSession: ChatGPTSession?
    private var activeID: UUID?
    private var anchor: ASPresentationAnchor?
    private var backgroundObserver: NSObjectProtocol?

    func authorize(session: ChatGPTSession, profileID: String? = nil, requestConsent: Bool = false) async throws {
        guard activeID == nil else { throw Failure.alreadyAuthorizing }
        try Task.checkCancellation()
        let id = UUID()
        let listener = ChatGPTLoopbackListener()
        activeID = id
        activeSession = session
        self.listener = listener
        statusError = nil
        isAuthorizing = true
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeID == id else { return }
                self.cancel()
                self.statusError = "ChatGPT sign-in was interrupted. Keep NOOP open and try again."
            }
        }

        let task = Task { @MainActor [self] in
            try await performAuthorization(session: session, listener: listener, id: id,
                                           profileID: profileID, requestConsent: requestConsent)
        }
        activeTask = task
        defer {
            if activeID == id {
                if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
                backgroundObserver = nil
                webSession?.cancel()
                webSession = nil
                listener.cancel()
                self.listener = nil
                anchor = nil
                activeSession = nil
                activeTask = nil
                activeID = nil
                isAuthorizing = false
            }
        }
        do {
            try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: {
                task.cancel()
                listener.cancel()
            })
        } catch {
            // The session owns rollback to the previous profile; a failed new login never replaces it.
            session.cancelAuthorization()
            if !(error is CancellationError) { statusError = error.localizedDescription }
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        listener?.cancel()
        webSession?.cancel()
        activeSession?.cancelAuthorization()
        statusError = nil
    }

    private func performAuthorization(session: ChatGPTSession, listener: ChatGPTLoopbackListener,
                                      id: UUID, profileID: String?, requestConsent: Bool) async throws {
        // The redirect exists only after the socket is ready, preventing a fast browser redirect race.
        let redirectURI = try await listener.start()
        try Task.checkCancellation()
        let attempt = try session.prepareAuthorization(redirectURI: redirectURI, profileID: profileID,
                                                       requestConsent: requestConsent)
        listener.expectCallback(state: attempt.state)
        guard let window = foregroundWindow() else { throw Failure.noWindow }
        anchor = window
        let browser = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: nil) {
            [weak self] _, _ in
            // HTTP success is received by the listener. This handler only ends an unfinished wait
            // when the person dismisses the sheet or the OS cannot keep the browser session open.
            Task { @MainActor in
                guard self?.activeID == id else { return }
                listener.cancel()
            }
        }
        browser.presentationContextProvider = self
        browser.prefersEphemeralWebBrowserSession = false
        webSession = browser
        guard browser.start() else { throw Failure.browserUnavailable }
        let callbackURL = try await listener.waitForCallback()
        // The listener has already sent its response. Cancelling the sheet can no longer cancel
        // callback delivery, since the listener's terminal result is committed exactly once.
        browser.cancel()
        webSession = nil
        try Task.checkCancellation()
        let callback = try ChatGPTAuth.parseCallback(url: callbackURL, attempt: attempt)
        try await session.completeAuthorization(attempt: attempt, callback: callback)
    }

    private func foregroundWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .compactMap { scene in scene.keyWindow ?? scene.windows.first(where: { !$0.isHidden }) }
            .first
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
