import Combine
import Foundation
import StrandAnalytics
import StrandDesign

// The one reader of personal events for charts (stage 5 specification §10.5). Every adopting chart
// site asks this source for its dots and its caption; none reads the store or computes an overlap.
// Each call reads the store's events once, so a site's dots and caption come from the same events.
// Every function is nil while the feature is off and nil when nothing overlaps the window.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

@MainActor
final class PersonalEventChartSource: ObservableObject {
    enum MarkStyle { case points, bars }

    static let shared = PersonalEventChartSource()

    private let store: PersonalEventStore
    private let locale: Locale
    private var revisionObserver: AnyCancellable?

    init(store: PersonalEventStore? = nil, locale: Locale = AppLanguage.activeLocale) {
        self.store = store ?? .shared
        self.locale = locale
        // A chart redraws when the list or the flag changes.
        revisionObserver = self.store.$revision.dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// One slot per day key: `.points` for line and weekly-point charts, `.bars` for bar charts.
    func marks(dayKeys: [String], style: MarkStyle) -> NoopChartAxisMarks? {
        resolve(slots: dayKeys.map { PersonalEventSlot(firstDay: $0, lastDay: $0) }) { covered, spoken in
            switch style {
            case .points: return .points(covered: covered, accessibilityText: spoken)
            case .bars: return .bars(covered: covered, accessibilityText: spoken)
            }
        }
    }

    /// One slot per week, Monday to Sunday, placed as points.
    func marks(weekStarts: [String]) -> NoopChartAxisMarks? {
        let slots = weekStarts.map { start in
            PersonalEventSlot(firstDay: start, lastDay: CanonicalDay.adding(6, to: start) ?? start)
        }
        return resolve(slots: slots) { covered, spoken in .points(covered: covered, accessibilityText: spoken) }
    }

    /// One slot per day key, placed at its x on a continuous domain (a line chart of dates).
    func marks(dayKeys: [String], xs: [Double], domain: ClosedRange<Double>) -> NoopChartAxisMarks? {
        resolve(slots: dayKeys.map { PersonalEventSlot(firstDay: $0, lastDay: $0) }) { covered, spoken in
            .values(xs, covered: covered, domain: domain, accessibilityText: spoken)
        }
    }

    /// What the dots of a window mean; nil when no event overlaps it.
    func caption(firstDay: String, lastDay: String, today: String) -> PersonalEventCaption? {
        PersonalEventPresenter.caption(events: store.events, firstDay: firstDay, lastDay: lastDay, today: today,
                                       locale: locale)
    }

    /// The caption of a chart of day keys: the window from the first key to the last, with the last
    /// as the reference day. Nil exactly when `marks(dayKeys:...)` is nil, so a chart given only the
    /// days that have a reading never captions an event that falls between them and has no dot.
    func caption(dayKeys: [String]) -> PersonalEventCaption? {
        windowCaption(events: store.events, slots: dayKeys.map { PersonalEventSlot(firstDay: $0, lastDay: $0) })
    }

    /// The day keys of chart points dated at the UTC start of their day, as the redesign's charts
    /// date the stored day keys.
    nonisolated static func dayKeys(utcDayStarts dates: [Date]) -> [String] {
        let days = LocalDayWindows(timeZone: TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current)
        return dates.map { days.dayKey(for: $0) }
    }

    // MARK: Pieces

    /// One read of the events, the covered flags of `slots`, and the spoken caption of the window the
    /// slots span, all from that read.
    private func resolve(slots: [PersonalEventSlot],
                         make: ([Bool], String?) -> NoopChartAxisMarks) -> NoopChartAxisMarks? {
        let events = store.events
        guard let covered = coveredFlags(events: events, slots: slots) else { return nil }
        return make(covered, windowCaption(events: events, slots: slots, covered: covered)?.spokenText)
    }

    /// The covered flag of each slot; nil when no slot is covered.
    private func coveredFlags(events: [PersonalEvent], slots: [PersonalEventSlot]) -> [Bool]? {
        guard !events.isEmpty, !slots.isEmpty else { return nil }
        let covered = PersonalEvents.coveredSlots(events: events, slots: slots)
        return covered.contains(true) ? covered : nil
    }

    /// The one caption of a chart's slots, read by both its visible caption and its dots' spoken text:
    /// the window the valid slots span, with its last day as the reference day. Nil when no slot is
    /// covered.
    private func windowCaption(events: [PersonalEvent], slots: [PersonalEventSlot],
                               covered: [Bool]? = nil) -> PersonalEventCaption? {
        guard (covered ?? coveredFlags(events: events, slots: slots)) != nil else { return nil }
        let valid = slots.filter { CanonicalDay.isValid($0.firstDay) && CanonicalDay.isValid($0.lastDay) }
        guard let first = valid.map(\.firstDay).min(), let last = valid.map(\.lastDay).max() else { return nil }
        return PersonalEventPresenter.caption(events: events, firstDay: first, lastDay: last, today: last,
                                              locale: locale)
    }
}
