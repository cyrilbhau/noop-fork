import AppIntents
import Foundation

// Stage 2 (coach packet), specification §9.3 and §10.4: the Shortcuts action. It returns the text
// the packet sheet previews, from the same assembler and the same stored sections and range, and
// does nothing else: no parameter, no spoken or shown reply (which would put health text on the
// lock screen), no pasteboard write, no Siri phrase and no entry in `NOOPShortcuts`.

/// Why the action returned no text. Each case is worded by `CoachPacketPresenter`.
enum CoachPacketIntentError: Error, CustomLocalizedStringResourceConvertible {
    case switchedOff, notReady, blocked, unavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .switchedOff: return "\(CoachPacketPresenter.intentSwitchedOff)"
        case .notReady: return "\(CoachPacketPresenter.intentNotReady)"
        case .blocked: return "\(CoachPacketPresenter.intentBlocked)"
        case .unavailable: return "\(CoachPacketPresenter.intentUnavailable)"
        }
    }
}

/// Returns the coach packet as text. Listed in the Shortcuts app whether or not the feature is on,
/// because an intent's presence is static; with the feature off it fails and says so.
struct GetCoachPacketIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Coach Packet"
    static var description = IntentDescription(
        "Returns the coach packet as text, using the sections and range chosen in NOOP.")
    /// No app screen is needed: the text is assembled from the on-device store and returned.
    static var openAppWhenRun = false
    /// The phone must be unlocked: the result is health text.
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// How long a cold launch is given to open its store before the action gives up.
    private static let waitSeconds = 8

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let settings = CoachPacketSettings()
        // Refused before any wait when the feature is off; the shared steps read the flag again
        // after the waits and after assembly.
        guard settings.isEnabled else { throw CoachPacketIntentError.switchedOff }
        let result = await CoachPacketShortcut.run(
            settings: settings, attempts: Self.waitSeconds,
            isReady: {
                guard let app = AppModel.shared else { return false }
                return app.repo.loaded && app.deviceRegistry != nil
            },
            pause: { try? await Task.sleep(nanoseconds: 1_000_000_000) },
            assemble: {
                guard AppModel.shared?.repo.loaded == true, let assembler = CoachPacketAssembler.live() else {
                    return nil
                }
                return await assembler.assemble()
            })
        switch result {
        case .text(let text): return .result(value: text)
        case .switchedOff: throw CoachPacketIntentError.switchedOff
        case .notReady: throw CoachPacketIntentError.notReady
        case .blocked: throw CoachPacketIntentError.blocked
        case .unavailable: throw CoachPacketIntentError.unavailable
        }
    }
}
