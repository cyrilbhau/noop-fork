import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Ruling A27: a screen showing a day count, or a label taken from today's date, reads again when the
// local calendar day changes or the app returns to the foreground while that screen is mounted. The
// day notification is not delivered while the app is suspended, so the foreground is the second
// trigger; a new time zone can change the local day as well.

enum LocalDayChange {
    /// The app returning to the foreground on this platform.
    static var foregroundNotification: Notification.Name {
        #if canImport(UIKit)
        UIApplication.willEnterForegroundNotification
        #elseif canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #endif
    }

    /// One value each time the local day may have changed: a new calendar day, a new system time
    /// zone, or a return to the foreground. For a view's `onReceive`.
    static func publisher(_ center: NotificationCenter = .default) -> AnyPublisher<Void, Never> {
        Publishers.Merge3(
            center.publisher(for: .NSCalendarDayChanged),
            center.publisher(for: .NSSystemTimeZoneDidChange),
            center.publisher(for: foregroundNotification)
        )
        .map { _ in () }
        // The day notification may be posted off the main thread.
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    /// Calls `action` on the main actor after each value of `publisher`. Hold the returned cancellable.
    static func observe(_ center: NotificationCenter, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        publisher(center).sink { _ in
            Task { @MainActor in action() }
        }
    }
}
