import Combine
import Foundation

/// One observable copy of one `UserDefaults` Bool. The general form of `CutScorecardFlag`: a
/// feature flag's views observe one of these, and reading it never writes the key.
@MainActor
class ObservableDefaultsFlag: ObservableObject {
    /// The `UserDefaults` key this flag reads and writes.
    let key: String

    /// The stored value, false when the key is absent. Follows every write to the key, whoever
    /// makes it, and publishes only when the value changes.
    @Published private(set) var isEnabled: Bool

    private let defaults: UserDefaults
    private var observer: AnyCancellable?

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: key)
        observer = Self.observeWrites(to: defaults) { [weak self] in self?.followStoredValue() }
    }

    /// The app's one observation of `UserDefaults` writes: `onWrite` runs on the main actor after
    /// every write to `defaults`, whoever makes it, until the returned value is cancelled or
    /// released. Ruling A29 reuses it for the scorecard's rules.
    static func observeWrites(to defaults: UserDefaults,
                              _ onWrite: @escaping @MainActor () -> Void) -> AnyCancellable {
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
        ) { _ in
            // Posted on the thread that wrote. A write on the main thread is followed at once.
            if Thread.isMainThread {
                MainActor.assumeIsolated { onWrite() }
            } else {
                Task { @MainActor in onWrite() }
            }
        }
        return AnyCancellable { NotificationCenter.default.removeObserver(token) }
    }

    /// Writes the one key. The new value is published before this returns.
    func set(_ enabled: Bool) {
        if isEnabled != enabled { isEnabled = enabled }
        defaults.set(enabled, forKey: key)
    }

    private func followStoredValue() {
        let stored = defaults.bool(forKey: key)
        if stored != isEnabled { isEnabled = stored }
    }
}
