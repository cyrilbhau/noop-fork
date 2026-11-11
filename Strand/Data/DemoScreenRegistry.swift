#if DEBUG
import Foundation

/// The demo-name prefixes each stage reserves for `--demo-screen <name>`. A stage adds its own
/// list here and one element to the app's registry; two stages may not claim overlapping prefixes.
enum DemoScreenPrefixes {
    /// Stage 1: the names `ScorecardDemo.screen(named:)` answers.
    static let scorecard = ["scorecard-", "flow-", "weighin-", "history-", "phase-", "cards-"]
    /// Stage 2: the names `CoachPacketDemo.screen(named:)` answers.
    static let packet = ["packet-"]
}

/// The ordered list `--demo-screen <name>` falls through to after the app's own switch. Generic
/// over the screen so that the routing is tested without a view; the app uses
/// `DemoScreenRegistry<AnyView>`.
struct DemoScreenRegistry<Screen> {
    /// One stage's demo screens: the prefixes it reserves and the function that answers them.
    struct Element {
        let prefixes: [String]
        let resolve: (String) -> Screen?

        init(prefixes: [String], resolve: @escaping (String) -> Screen?) {
            self.prefixes = prefixes
            self.resolve = resolve
        }
    }

    /// A prefix of an earlier element and a prefix of a later one, where one begins with the other
    /// (equal prefixes included).
    struct Conflict: Equatable {
        let earlier: String
        let later: String
    }

    let elements: [Element]

    /// Stores the elements in the order given. Does not trap on a conflict, so that the rule can be
    /// tested; the app asserts `conflicts.isEmpty` where it builds its registry.
    init(_ elements: [Element]) {
        self.elements = elements
    }

    /// Every overlapping pair across two different elements, each named once with the earlier
    /// element's prefix first. Empty for a well-formed registry.
    var conflicts: [Conflict] {
        var found: [Conflict] = []
        for (index, element) in elements.enumerated() {
            for later in elements[(index + 1)...] {
                for a in element.prefixes {
                    for b in later.prefixes where a.hasPrefix(b) || b.hasPrefix(a) {
                        found.append(Conflict(earlier: a, later: b))
                    }
                }
            }
        }
        return found
    }

    /// Asks, in order, each element one of whose prefixes `name` begins with, and returns the first
    /// screen that is not nil. An element is never asked about a name outside its own prefixes.
    /// `name` is matched as given: the caller lowercases.
    func screen(named name: String) -> Screen? {
        for element in elements where element.prefixes.contains(where: { name.hasPrefix($0) }) {
            if let screen = element.resolve(name) { return screen }
        }
        return nil
    }
}
#endif
