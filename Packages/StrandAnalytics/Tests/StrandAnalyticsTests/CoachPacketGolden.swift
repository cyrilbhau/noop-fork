import Foundation

// Golden packet texts for `docs/personal/superapp/specs/stage-2.md`, as Swift string literals (the
// test target has no resources).
//
// Packet v2 (§7.12, §14.5) regenerated G1 and G2 once, as version 2. The version 1 texts of §7.9
// and §13.3 are no longer produced by the renderer; the version 2 texts and the helpers that cut
// them into blocks live in `CoachPacketV2Golden.swift`, and this file names them for the version 1
// tests that compare against G1 and G2.

/// The goldens the stage 2 tests compare against: version 2, the format in force.
enum CoachPacketGolden {

    /// Golden G1: the full fixture with every section on.
    static var g1: String { CoachPacketV2Golden.g1 }

    /// Golden G2: the same clock and range with no data at all.
    static var g2: String { CoachPacketV2Golden.g2 }

    /// The blank-line-separated blocks of a packet text, without the final newline.
    static func blocks(_ text: String) -> [String] { CoachPacketV2Golden.blocks(text) }

    /// The fixed section order with each raw section id and its heading. Section `n` of this list
    /// is block `n + 1` of G1.
    static var sectionOrder: [(id: String, heading: String)] { CoachPacketV2Golden.sectionOrder }

    /// G1 with the sections named in `off` (raw ids) removed.
    static func g1(withSectionsOff off: Set<String>) -> String {
        CoachPacketV2Golden.g1(withSectionsOff: off)
    }
}
