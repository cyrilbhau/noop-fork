import Foundation

// STAND-IN, to be replaced whole by stage 2's `CoachPacket.swift` when stage 2 merges.
//
// Stage 5's packet rows (`PersonalEventsPacket.swift`) and their committed tests call
// `CoachPacket.sanitize` (stage 2 specification §6.2), and stage 2's renderer is not on this branch.
// This file holds that one function and the two constants it reads, under stage 2's own file name
// so that the merge shows the collision instead of hiding it: resolve by taking stage 2's file.
// The body of `sanitize` is copied from stage 2's implementation, notes included, so the rows do
// not change when the real file arrives.
//
// Pure and total: no store, no clock, no calendar, time-zone, date or locale object.
//
// No Kotlin twin: the owner has skipped Android for the personal fork (stage 1 ruling R43).

/// The coach packet's shared text rules. Here only `sanitize`; stage 2 owns the renderer.
public enum CoachPacket {
    /// The most UTF-8 bytes of free text printed on a line.
    public static let freeTextByteLimit = 48
    /// What `sanitize` returns for text with nothing left in it.
    static let unnamed = "unnamed"

    /// One line of free text: control characters and line breaks become spaces, runs of spaces
    /// collapse, the ends are trimmed, `"` becomes `'`, and the result is cut at a character
    /// boundary to at most `freeTextByteLimit` UTF-8 bytes. Empty input gives "unnamed".
    public static func sanitize(_ text: String) -> String {
        var cleaned = String.UnicodeScalarView()
        var spacePending = false
        for scalar in text.unicodeScalars {
            // SPEC-NOTE: §6.2 names control characters and line breaks. Every other Unicode white
            // space (a no-break space, U+3000) is read as a space as well, so "runs of spaces
            // collapse" holds for all of them and no line ends in an invisible one.
            if scalar.properties.generalCategory == .control || scalar.properties.isWhitespace {
                spacePending = true
                continue
            }
            if spacePending, !cleaned.isEmpty { cleaned.append(" ") }
            spacePending = false
            cleaned.append(scalar == "\"" ? "'" : scalar)
        }
        var cut = ""
        var bytes = 0
        for character in String(cleaned) {
            let width = character.utf8.count
            guard bytes + width <= freeTextByteLimit else { break }
            cut.append(character)
            bytes += width
        }
        // SPEC-NOTE: the cut can land just after a space. That space is dropped, so "the ends are
        // trimmed" still holds for the text that is printed.
        while cut.hasSuffix(" ") { cut.removeLast() }
        // SPEC-NOTE: "Empty input gives unnamed" is read as "text that is empty once cleaned", so no
        // line ever carries an empty name.
        return cut.isEmpty ? unnamed : cut
    }
}
