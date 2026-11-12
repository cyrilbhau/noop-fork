import Foundation

// The body rows of the coach packet's events section (stage 5 specification §7.5; goldens §13.3),
// written in stage 2's packet grammar (stage 2 §7.12). Kept apart from `PersonalEvents.swift`
// because it calls stage 2's `CoachPacket.sanitize`.
//
// This file returns rows only. The heading, the blank line between sections, the section case, the
// version number and the whole-packet goldens belong to the packet v2 change. Nothing here scans
// for private-looking text, drops a row or rewrites a note: that is the packet scan's work.
//
// Pure and total, as `PersonalEvents.swift` is.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

extension PersonalEvents {
    /// The most event rows printed.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let packetRowLimit = 12
    /// The UTF-8 bytes the events section may add to a packet, heading and line breaks included.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let packetByteAllowance = 2000

    /// Row 1 of a listing.
    static let packetIntroRow = "entered by the owner, whole local days, oldest first:"
    /// The only row when nothing is listed. "Listed", because private events may exist and the
    /// packet must neither reveal nor deny them.
    static let packetNoneListedRow = "events: none listed in range"
    /// The indent of every row after the intro.
    static let packetRowIndent = "  "
    /// What stands for the end day of an ongoing event.
    static let packetOngoing = "ongoing"

    /// The body rows of the packet's events section: no heading, no blank line, no "\n".
    ///
    /// The events listed are those of `visible(events, includeSensitive:)` with a day in
    /// `[firstDay, lastDay]`, oldest start first. At most `packetRowLimit` are printed, the last
    /// ones, after a row that counts the earlier listed events left out. Nothing listed, or an
    /// invalid range, gives the single "none listed" row.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func packetLines(events: [PersonalEvent], firstDay: String, lastDay: String,
                                   includeSensitive: Bool) -> [String] {
        let listed = self.events(overlapping: firstDay, lastDay,
                                 in: visible(events, includeSensitive: includeSensitive))
        guard !listed.isEmpty else { return [packetNoneListedRow] }

        var rows = [packetIntroRow]
        // SPEC-NOTE: §6 makes the limit a constant, not a parameter. A limit below zero is read as
        // zero, so the arithmetic below cannot trap if the constant is ever changed.
        let limit = max(0, packetRowLimit)
        let earlier = listed.count - min(listed.count, limit)
        if earlier > 0 {
            rows.append("\(packetRowIndent)(\(earlier) earlier events in range not shown)")
        }
        rows.append(contentsOf: listed.suffix(limit).map(packetRow))
        return rows
    }

    /// One event row: the indent, the stored days printed whole, the name, and the note if any.
    private static func packetRow(_ event: PersonalEvent) -> String {
        let dates: String
        if let end = event.endDay {
            dates = end == event.startDay ? event.startDay : "\(event.startDay)..\(end)"
        } else {
            dates = "\(event.startDay)..\(packetOngoing)"
        }
        var name = event.kind.rawValue
        if event.kind == .custom {
            // A listed event has no issue, so a custom one has a label; "" would print "unnamed".
            name += " \"\(CoachPacket.sanitize(event.label ?? ""))\""
        }
        var row = "\(packetRowIndent)\(dates): \(name)"
        if let note = event.note {
            row += "; note \"\(CoachPacket.sanitize(note))\""
        }
        return row
    }
}
