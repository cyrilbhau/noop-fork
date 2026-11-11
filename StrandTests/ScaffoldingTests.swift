import XCTest
import Combine
import StrandAnalytics
@testable import Strand

// Shared scaffolding ahead of stages 2 to 6 (cross-stage review, items X6, X7 and X19). Written
// before the implementation exists. Synthetic values only. The change these tests describe adds
// plumbing once and changes no behaviour of the app.
//
// API ASSUMED BY THESE TESTS (new; everything else is used as it exists today)
//
// 1. Strand/Data/DemoScreenRegistry.swift, the whole file inside `#if DEBUG`:
//
//     /// The demo-name prefixes each stage reserves. Stage 1's are the names
//     /// `ScorecardDemo.screen(named:)` answers today.
//     enum DemoScreenPrefixes {
//         static let scorecard: [String]   // ["scorecard-", "flow-", "weighin-", "history-", "phase-", "cards-"]
//     }
//
//     /// The ordered list `--demo-screen <name>` falls through to after the app's own switch.
//     /// Generic over the screen so that the routing is tested without a view; the app uses
//     /// `DemoScreenRegistry<AnyView>`.
//     struct DemoScreenRegistry<Screen> {
//         struct Element {
//             let prefixes: [String]
//             let resolve: (String) -> Screen?
//             init(prefixes: [String], resolve: @escaping (String) -> Screen?)
//         }
//         /// A prefix of an earlier element and a prefix of a later one, where one begins with
//         /// the other (equal prefixes included).
//         struct Conflict: Equatable {
//             let earlier: String
//             let later: String
//         }
//
//         let elements: [Element]
//         /// Stores the elements in the order given. Does not trap on a conflict, so that the
//         /// rule can be tested; the app asserts `conflicts.isEmpty` where it builds its registry.
//         init(_ elements: [Element])
//
//         /// Every overlapping pair across two different elements, each named once with the
//         /// earlier element's prefix first. In no promised order. Empty for a well-formed registry.
//         var conflicts: [Conflict] { get }
//
//         /// Asks, in order, each element one of whose prefixes `name` begins with, and returns
//         /// the first screen that is not nil. An element is never asked about a name outside its
//         /// own prefixes. `name` is matched as given: the caller lowercases, as it does today.
//         func screen(named name: String) -> Screen?
//     }
//
//    `StrandiOSApp.swift`'s `DemoScreens.requested` keeps its switch and still lowercases the
//    name. `DemoScreens` gains a static `registry: DemoScreenRegistry<AnyView>` whose first element
//    is `(prefixes: DemoScreenPrefixes.scorecard, resolve: ScorecardDemo.screen(named:))`; the
//    switch's `default:` is `return registry.screen(named: …)`; and one line inside `DemoScreens`
//    asserts `registry.conflicts.isEmpty` (any `assert…(` call naming `conflicts`). Checked by
//    source scan, because that file and `ScorecardDemo.swift` are iPhone-only and are not compiled
//    into this macOS-hosted bundle.
//
// 2. Strand/Data/ObservableDefaultsFlag.swift:
//
//     /// One observable copy of one UserDefaults Bool. The general form of `CutScorecardFlag`.
//     @MainActor class ObservableDefaultsFlag: ObservableObject {
//         init(key: String, defaults: UserDefaults = .standard)
//         let key: String
//         /// The stored value, false when the key is absent. Follows every write to the key in
//         /// `defaults`, whoever makes it. Publishes only when the value changes. Reading it never
//         /// writes the key.
//         @Published private(set) var isEnabled: Bool
//         /// Writes the one key. The new value is published before this returns.
//         func set(_ enabled: Bool)
//     }
//
//    `CutScorecardFlag` keeps its API (`shared`, `init(defaults:)`, `isEnabled`, `$isEnabled`,
//    `set(_:)`, `displayPolicy`) and its behaviour, and holds no observer of its own: the
//    `UserDefaults.didChangeNotification` subscription lives in `ObservableDefaultsFlag.swift` only.
//    `CutScorecardFlagSwitchTests` is the check that it behaves as before, and is not edited.
//
// 3. Strand/Data/ChargeTypicalBand.swift:
//
//     /// The "typical range" of a personal baseline: baseline ± `Baselines.sigma(state)`, nil
//     /// unless the baseline is usable (provisional or trusted).
//     enum ChargeTypicalBand {
//         static func range(_ state: BaselineState?) -> ClosedRange<Double>?
//     }
//
//    `RecoveryDetailModel.load` calls it in place of its nested `band(_:)`, and it is the only
//    place in the app targets that calls `Baselines.sigma(`.
//
// THE FUNCTION CHARACTERISED FOR THE BAND
//
// The nested function `band(_:)` of `RecoveryDetailModel.load(dayKey:repo:)`, at
// StrandiOS/Redesign/ScoreDetailData.swift:156-160 of the commit these tests were written against:
//
//     func band(_ state: BaselineState?) -> ClosedRange<Double>? {
//         guard let state, state.usable else { return nil }
//         let sigma = Baselines.sigma(state)
//         return (state.baseline - sigma)...(state.baseline + sigma)
//     }
//
// It feeds `RecoveryFactor.typical` for heart rate variability, resting heart rate and respiratory
// rate. The expected bounds below are the output of that body, copied verbatim into a throwaway
// test and run against the package at that commit, printed with seventeen significant digits so
// that each literal is the exact Double.

// MARK: - Shared

private enum ScaffoldingSource {
    struct NotReachable: Error, CustomStringConvertible {
        let path: String
        var description: String { "\(path) is not reachable from the test sources" }
    }

    static func root(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    static func text(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else { throw NotReachable(path: relative) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every Swift file under the app-target folders, as paths relative to the repository root.
    static func appSwiftFiles() -> [String] {
        let base = root()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        let folders = names.filter { $0 == "Strand" || $0.hasPrefix("StrandiOS") || $0.hasPrefix("NOOPWatch") }
        var found: [String] = []
        for folder in folders.sorted() {
            guard let walker = FileManager.default.enumerator(atPath: base.appendingPathComponent(folder).path) else {
                continue
            }
            for case let item as String in walker where item.hasSuffix(".swift") {
                found.append("\(folder)/\(item)")
            }
        }
        return found.sorted()
    }

    /// The file's lines with `//` comments removed. String literals are kept, so a `//` inside one
    /// is not taken for a comment.
    static func codeLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            var kept = ""
            var inString = false
            var previous: Character?
            var index = line.startIndex
            while index < line.endIndex {
                let character = line[index]
                let next = line.index(after: index)
                if character == "\"", previous != "\\" { inString.toggle() }
                if !inString, character == "/", next < line.endIndex, line[next] == "/" { break }
                kept.append(character)
                previous = character
                index = next
            }
            return kept
        }
    }

    /// For each line, true when it is compiled only in a DEBUG build: it sits in the true branch
    /// of an `#if DEBUG`, at any depth.
    static func debugOnly(_ lines: [String]) -> [Bool] {
        var stack: [Bool] = []
        var result: [Bool] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                stack.append(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces) == "DEBUG")
                result.append(false)
            } else if trimmed.hasPrefix("#else") || trimmed.hasPrefix("#elseif") {
                if !stack.isEmpty { stack[stack.count - 1] = false }
                result.append(false)
            } else if trimmed.hasPrefix("#endif") {
                if !stack.isEmpty { stack.removeLast() }
                result.append(false)
            } else {
                result.append(stack.contains(true))
            }
        }
        return result
    }

    static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The code of `enum DemoScreens { … }` in StrandiOSApp.swift, comments removed: from its
    /// declaration to the `#endif` that closes the DEBUG block it sits in.
    static func demoScreensBlock() throws -> String {
        let code = codeLines(try text("StrandiOS/App/StrandiOSApp.swift")).joined(separator: "\n")
        guard let start = code.range(of: "enum DemoScreens"),
              let end = code.range(of: "\n#endif", range: start.upperBound..<code.endIndex) else {
            throw NotReachable(path: "StrandiOS/App/StrandiOSApp.swift: enum DemoScreens")
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    /// The code of `ScorecardDemo.screen(named:)`, comments removed.
    static func scorecardScreenBody() throws -> String {
        let code = codeLines(try text("StrandiOS/Scorecard/ScorecardDemo.swift")).joined(separator: "\n")
        guard let start = code.range(of: "static func screen(named name: String) -> AnyView?"),
              let end = code.range(of: "\n    }\n", range: start.upperBound..<code.endIndex) else {
            throw NotReachable(path: "StrandiOS/Scorecard/ScorecardDemo.swift: screen(named:)")
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }
}

// MARK: - 1. The debug demo registry (X6)

#if DEBUG
final class ScaffoldingDemoRegistryTests: XCTestCase {
    private typealias Registry = DemoScreenRegistry<String>
    private typealias Element = DemoScreenRegistry<String>.Element
    private typealias Conflict = DemoScreenRegistry<String>.Conflict

    /// The prefixes the later stages are to reserve, one element per stage, in stage order.
    private static let laterStages: [(stage: String, prefixes: [String])] = [
        ("stage2", ["packet-"]),
        ("stage3", ["intake-"]),
        ("stage4", ["scan-", "bench-"]),
        ("stage5", ["events-"]),
        ("stage6", ["niggle-", "recovery-", "timeline-"]),
        ("labbook", ["labbook-"]),
    ]

    /// Stage 1's element as the app builds it, followed by one element per later stage. Each
    /// resolver answers with its own tag, so a result says which resolver was asked.
    private func plannedRegistry() -> Registry {
        var elements = [Element(prefixes: DemoScreenPrefixes.scorecard, resolve: { "scorecard|" + $0 })]
        for stage in Self.laterStages {
            let tag = stage.stage
            elements.append(Element(prefixes: stage.prefixes, resolve: { tag + "|" + $0 }))
        }
        return Registry(elements)
    }

    /// Every name `ScorecardDemo.screen(named:)` answers at the commit these tests were written
    /// against: the live screen, the 27 scorecard frames, the weigh-in frames (c7 is not a frame),
    /// the history, phase and card frames, and every scripted flow step.
    private static let stageOneNames: [String] = {
        var names = ["scorecard-live"]
        names += (1...27).map { "scorecard-b\($0)" }
        names += (1...10).filter { $0 != 7 }.map { "weighin-c\($0)" }
        names += (1...5).map { "history-d\($0)" }
        names += (1...4).map { "phase-e\($0)" }
        names += (1...3).map { "cards-a\($0)" }
        names += ["state", "scorecard", "history", "flag-on", "flag-off", "card-add", "phase-first-open",
                  "phase-first-save", "phase-edit-open", "phase-new-open", "phase-new-save", "weighin-weight",
                  "weighin-waist", "weighin-save", "backdate-open", "backdate-save", "skip-open", "skip-save",
                  "edit-value-open", "edit-value-save", "edit-date-open", "edit-date-save", "delete-ask",
                  "delete-confirm", "reminder-on", "reminder-denied", "reminder-off", "show-today", "show-health",
                  "show-profile", "show-editor", "show-editor-default"].map { "flow-" + $0 }
        return names
    }()

    // MARK: Stage 1's names

    func testStageOnePrefixesAreTheSixFamiliesOfScorecardDemo() {
        XCTAssertEqual(DemoScreenPrefixes.scorecard, ["scorecard-", "flow-", "weighin-", "history-", "phase-", "cards-"])
    }

    func testEveryExistingStageOneNameReachesTheScorecardResolverUnchanged() {
        let registry = plannedRegistry()
        XCTAssertEqual(Self.stageOneNames.count, 81)
        for name in Self.stageOneNames {
            XCTAssertEqual(registry.screen(named: name), "scorecard|" + name, name)
        }
        // With stage 1 alone, which is the registry the scaffolding change ships.
        let alone = Registry([Element(prefixes: DemoScreenPrefixes.scorecard, resolve: { "scorecard|" + $0 })])
        for name in Self.stageOneNames {
            XCTAssertEqual(alone.screen(named: name), "scorecard|" + name, name)
        }
    }

    /// A name under a stage 1 prefix that `ScorecardDemo` does not answer is still its to refuse:
    /// it is asked, it says nil, and nil is the answer, as it was through the old fall-through.
    func testNamesStageOneRefusesStayNil() {
        var asked: [String] = []
        let known = Set(Self.stageOneNames)
        let registry = Registry([Element(prefixes: DemoScreenPrefixes.scorecard, resolve: { name in
            asked.append(name)
            return known.contains(name) ? "scorecard|" + name : nil
        })])
        let refused = ["weighin-c7", "scorecard-b0", "scorecard-b28", "scorecard-zz", "history-d6", "phase-e5",
                       "cards-a4", "scorecard-", "cards-a1-extra"]
        for name in refused { XCTAssertNil(registry.screen(named: name), name) }
        XCTAssertEqual(asked, refused, "each was put to the scorecard resolver, once, as given")
    }

    /// The registry must claim everything `ScorecardDemo.screen(named:)` can answer, or a name that
    /// resolved through the old fall-through would stop resolving. Read from the source, because
    /// the demo file is iPhone-only.
    func testThePinnedPrefixesCoverEveryNameFamilyInScorecardDemo() throws {
        let body = try ScaffoldingSource.scorecardScreenBody()
        let exact = ScaffoldingSource.captures(#"name == "([^"]+)""#, in: body)
        let prefixes = ScaffoldingSource.captures(#"hasPrefix\("([^"]+)"\)"#, in: body)
        let families = ScaffoldingSource.captures(#"case \("([^"]+)","#, in: body)
        XCTAssertEqual(exact, ["scorecard-live"])
        XCTAssertEqual(prefixes, ["flow-"])
        XCTAssertEqual(families, ["scorecard", "weighin", "history", "phase", "cards"])

        let claimed = DemoScreenPrefixes.scorecard
        for name in exact + prefixes + families.map({ $0 + "-x1" }) {
            XCTAssertTrue(claimed.contains(where: { name.hasPrefix($0) }), "\(name) is not under a stage 1 prefix")
        }
        XCTAssertEqual(Set(claimed), Set(prefixes + families.map { $0 + "-" }),
                       "and stage 1 reserves nothing ScorecardDemo does not answer")
    }

    // MARK: Unknown names

    func testUnknownNamesResolveToNil() {
        var asked: [String] = []
        var elements = [Element(prefixes: DemoScreenPrefixes.scorecard, resolve: { asked.append($0); return "scorecard" })]
        for stage in Self.laterStages {
            elements.append(Element(prefixes: stage.prefixes, resolve: { asked.append($0); return "later" }))
        }
        let registry = Registry(elements)
        let unknown = ["", "-", "nosuchscreen", "scorecard", "flow", "weighin", "history", "phase", "cards", "packet",
                       "recovery", "timeline", "xscorecard-b1", " scorecard-b1", "Scorecard-b1", "SCORECARD-LIVE",
                       "score-card-b1", "b1-scorecard-", "today", "liquidtoday", "gallery"]
        for name in unknown { XCTAssertNil(registry.screen(named: name), "\"\(name)\"") }
        XCTAssertEqual(asked, [], "no resolver is asked about a name outside its own prefixes")
        XCTAssertNil(Registry([]).screen(named: "scorecard-b1"), "an empty registry resolves nothing")
    }

    // MARK: Order

    func testElementsAreKeptAndAskedInTheOrderGiven() {
        let registry = plannedRegistry()
        XCTAssertEqual(registry.elements.map(\.prefixes), [DemoScreenPrefixes.scorecard] + Self.laterStages.map(\.prefixes))

        // Each later stage's names reach that stage's resolver and no other.
        let expected: [(String, String)] = [
            ("packet-p1", "stage2"), ("intake-a3", "stage3"), ("scan-b2", "stage4"), ("bench-c1", "stage4"),
            ("events-e9", "stage5"), ("niggle-n1", "stage6"), ("recovery-r2", "stage6"), ("timeline-t4", "stage6"),
            ("labbook-ownership", "labbook"),
        ]
        for (name, stage) in expected { XCTAssertEqual(registry.screen(named: name), stage + "|" + name, name) }
    }

    /// Order is only observable when two elements claim one name, which a well-formed registry
    /// never has. The rule is still defined: the earlier element is asked first, and a later one
    /// only when the earlier says nil.
    func testTheEarlierElementWinsAndNilFallsThroughToTheNext() {
        var asked: [String] = []
        func element(_ tag: String, _ prefixes: [String], answers: Bool) -> Element {
            Element(prefixes: prefixes, resolve: { name in
                asked.append(tag)
                return answers ? tag + "|" + name : nil
            })
        }
        let firstWins = Registry([element("a", ["demo-"], answers: true), element("b", ["demo-"], answers: true)])
        XCTAssertEqual(firstWins.screen(named: "demo-1"), "a|demo-1")
        XCTAssertEqual(asked, ["a"], "the later element is not asked once the earlier has answered")

        asked = []
        let swapped = Registry([element("b", ["demo-"], answers: true), element("a", ["demo-"], answers: true)])
        XCTAssertEqual(swapped.screen(named: "demo-1"), "b|demo-1")
        XCTAssertEqual(asked, ["b"])

        asked = []
        let fallsThrough = Registry([element("a", ["demo-"], answers: false), element("skip", ["other-"], answers: true),
                                     element("b", ["demo-x", "de"], answers: true)])
        XCTAssertEqual(fallsThrough.screen(named: "demo-x1"), "b|demo-x1")
        XCTAssertEqual(asked, ["a", "b"], "in order, the unrelated element is passed over, and b is asked once")

        asked = []
        let nobody = Registry([element("a", ["demo-"], answers: false), element("b", ["demo-"], answers: false)])
        XCTAssertNil(nobody.screen(named: "demo-1"))
        XCTAssertEqual(asked, ["a", "b"])
    }

    // MARK: Overlapping prefixes

    /// The conflicts as "earlier>later", sorted, because their order is not promised.
    private func pairs(_ prefixes: [[String]]) -> [String] {
        Registry(prefixes.map { Element(prefixes: $0, resolve: { _ in nil }) }).conflicts
            .map { $0.earlier + ">" + $0.later }.sorted()
    }

    func testThePlannedPrefixesDoNotConflict() {
        XCTAssertEqual(plannedRegistry().conflicts, [])
        XCTAssertEqual(Registry([]).conflicts, [])
        XCTAssertEqual(Registry([Element(prefixes: DemoScreenPrefixes.scorecard, resolve: { $0 })]).conflicts, [])
    }

    func testOverlappingPrefixesAcrossTwoElementsAreReported() {
        // The same prefix twice.
        XCTAssertEqual(pairs([["packet-"], ["packet-"]]), ["packet->packet-"])
        XCTAssertEqual(Registry([Element(prefixes: ["packet-"], resolve: { _ in nil }),
                                 Element(prefixes: ["packet-"], resolve: { _ in nil })]).conflicts,
                       [Conflict(earlier: "packet-", later: "packet-")])
        // One begins with the other, in either order.
        XCTAssertEqual(pairs([["scan-"], ["scan-body-"]]), ["scan->scan-body-"])
        XCTAssertEqual(pairs([["scan-body-"], ["scan-"]]), ["scan-body->scan-"])
        // A later stage taking a stage 1 family, or a longer name inside one.
        XCTAssertEqual(pairs([DemoScreenPrefixes.scorecard, ["events-", "history-"]]), ["history->history-"])
        XCTAssertEqual(pairs([DemoScreenPrefixes.scorecard, ["scorecard-ownership"]]), ["scorecard->scorecard-ownership"])
        // A prefix short enough to swallow another stage's names.
        XCTAssertEqual(pairs([["recovery-"], ["re"]]), ["recovery->re"])
        // The empty prefix claims every name, so it conflicts with every other element's prefixes.
        XCTAssertEqual(pairs([["packet-", "intake-"], [""]]), ["intake->", "packet->"])
        // Not adjacent, and more than one pair: each pair once, the earlier element's prefix first.
        XCTAssertEqual(pairs([["a-", "b-"], ["c-"], ["b-x", "a-"], ["c-"]]), ["a->a-", "b->b-x", "c->c-"])
        // Three elements on one prefix are three pairs.
        XCTAssertEqual(pairs([["x-"], ["x-"], ["x-"]]), ["x->x-", "x->x-", "x->x-"])
    }

    func testPrefixesThatOnlyLookAlikeDoNotConflict() {
        XCTAssertEqual(pairs([["scan-"], ["scans-"]]), [], "neither begins with the other")
        XCTAssertEqual(pairs([["recovery-"], ["recover-"]]), [])
        XCTAssertEqual(pairs([["events-"], ["Events-"]]), [], "prefixes are compared as written")
        XCTAssertEqual(pairs([["history-"], ["weighin-history-"]]), [], "a suffix is not a prefix")
    }

    /// The names the app's own switch answers come before the registry, so a reserved prefix must
    /// not be able to claim one of them (`recovery` is a switch name, `recovery-` a stage 6 prefix).
    func testNoReservedPrefixClaimsANameOfTheAppSwitch() throws {
        let block = try ScaffoldingSource.demoScreensBlock()
        let switchNames = ScaffoldingSource.captures(#"case "([^"]+)""#, in: block)
        XCTAssertGreaterThanOrEqual(switchNames.count, 20, "the switch's names were found")
        XCTAssertTrue(switchNames.contains("recovery") && switchNames.contains("today"))
        let registry = plannedRegistry()
        for name in switchNames { XCTAssertNil(registry.screen(named: name), "\(name) belongs to the app's switch") }
    }

    // MARK: The app's debug block (source scan)

    func testTheAppDebugBlockFallsThroughToTheRegistry() throws {
        let block = try ScaffoldingSource.demoScreensBlock()
        XCTAssertTrue(block.contains("DemoScreenRegistry<AnyView>"), "DemoScreens builds a DemoScreenRegistry<AnyView>")
        XCTAssertNil(block.range(of: #"default:\s*return\s+ScorecardDemo\."#, options: .regularExpression),
                     "the bare fall-through to ScorecardDemo is gone")
        XCTAssertNotNil(block.range(of: #"default:\s*return\s+[A-Za-z_.]*registry\.screen\(named:"#,
                                    options: [.regularExpression, .caseInsensitive]),
                        "the switch's default returns the registry's answer")
        XCTAssertTrue(block.contains(".lowercased()"), "the name is still lowercased by the caller")
        XCTAssertNotNil(block.range(of: #"assert[A-Za-z]*\([^\n]*conflicts"#, options: .regularExpression),
                        "the block asserts that the registry has no conflicts")
    }

    func testStageOneIsTheFirstElementWithItsPinnedPrefixes() throws {
        let block = try ScaffoldingSource.demoScreensBlock()
        let parts = block.components(separatedBy: "prefixes:")
        XCTAssertGreaterThanOrEqual(parts.count, 2, "the registry lists at least one element by its prefixes")
        guard parts.count >= 2 else { return }
        let firstElement = parts[1]
        XCTAssertTrue(firstElement.contains("DemoScreenPrefixes.scorecard"), "the first element reserves stage 1's prefixes")
        XCTAssertTrue(firstElement.contains("ScorecardDemo.screen"), "and resolves through ScorecardDemo.screen(named:)")

        let appFile = ScaffoldingSource.codeLines(try ScaffoldingSource.text("StrandiOS/App/StrandiOSApp.swift"))
            .joined(separator: "\n")
        XCTAssertEqual(ScaffoldingSource.count(of: "ScorecardDemo.screen", in: appFile), 1,
                       "ScorecardDemo is reached through its registry element and nowhere else")
    }

    func testTheRegistryIsCompiledInDebugBuildsOnly() throws {
        let registryFile = "Strand/Data/DemoScreenRegistry.swift"
        let lines = ScaffoldingSource.codeLines(try ScaffoldingSource.text(registryFile))
        let gated = ScaffoldingSource.debugOnly(lines)
        var offenders: [String] = []
        for (index, line) in lines.enumerated() where !gated[index] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("import ") { continue }
            offenders.append("\(registryFile):\(index + 1): \(trimmed)")
        }
        XCTAssertEqual(offenders, [], "every declaration of the registry file sits inside #if DEBUG")

        // No other app source names the registry outside a DEBUG block.
        var mentions = 0
        for file in ScaffoldingSource.appSwiftFiles() where file != registryFile {
            let fileLines = ScaffoldingSource.codeLines(try ScaffoldingSource.text(file))
            guard fileLines.contains(where: { $0.contains("DemoScreenRegistry") || $0.contains("DemoScreenPrefixes") }) else {
                continue
            }
            let fileGated = ScaffoldingSource.debugOnly(fileLines)
            for (index, line) in fileLines.enumerated()
            where line.contains("DemoScreenRegistry") || line.contains("DemoScreenPrefixes") {
                mentions += 1
                XCTAssertTrue(fileGated[index], "\(file):\(index + 1) names the demo registry outside #if DEBUG")
            }
        }
        XCTAssertGreaterThan(mentions, 0, "the app uses the registry")
    }
}
#endif

// MARK: - 3. One flag observer (X19)

@MainActor
final class ScaffoldingDefaultsFlagTests: XCTestCase {

    /// Records which keys were written, so "never written" can be told from "written with the same value".
    private final class RecordingDefaults: UserDefaults {
        var written: [String] = []
        override func set(_ value: Any?, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Bool, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func removeObject(forKey defaultName: String) {
            written.append(defaultName)
            super.removeObject(forKey: defaultName)
        }
    }

    private let key = "scaffolding.test.flag"
    private let otherKey = "scaffolding.test.otherFlag"
    private var suites: [String] = []
    private var observers: [AnyCancellable] = []

    override func tearDown() {
        observers = []
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeDefaults() throws -> RecordingDefaults {
        let name = "ScaffoldingDefaultsFlagTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        return defaults
    }

    private func record(_ flag: ObservableDefaultsFlag) -> () -> [Bool] {
        var seen: [Bool] = []
        flag.$isEnabled.sink { seen.append($0) }.store(in: &observers)
        return { seen }
    }

    private func recordChanges(_ flag: ObservableDefaultsFlag) -> () -> Int {
        var count = 0
        flag.objectWillChange.sink { count += 1 }.store(in: &observers)
        return { count }
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Long enough for a notification that would wrongly publish to have arrived.
    private func settle() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    // MARK: Reading

    func testAnAbsentKeyReadsAsFalseAndReadingNeverWritesIt() async throws {
        let defaults = try makeDefaults()
        let flag = ObservableDefaultsFlag(key: key, defaults: defaults)
        let seen = record(flag)
        let changes = recordChanges(flag)
        XCTAssertEqual(flag.key, key)
        XCTAssertFalse(flag.isEnabled, "absent reads as off")
        for _ in 0..<5 { _ = flag.isEnabled }
        _ = ObservableDefaultsFlag(key: key, defaults: defaults).isEnabled
        await settle()

        XCTAssertNil(defaults.object(forKey: key), "the key is still absent: a default is not a write")
        XCTAssertEqual(defaults.written, [], "observing the flag writes nothing at all")
        XCTAssertEqual(seen(), [false])
        XCTAssertEqual(changes(), 0)
    }

    func testTheFlagStartsFromTheStoredValue() throws {
        let on = try makeDefaults()
        on.set(true, forKey: key)
        on.written = []
        XCTAssertTrue(ObservableDefaultsFlag(key: key, defaults: on).isEnabled)
        XCTAssertFalse(ObservableDefaultsFlag(key: otherKey, defaults: on).isEnabled, "another key in the same defaults")
        XCTAssertEqual(on.written, [])

        let off = try makeDefaults()
        off.set(false, forKey: key)
        off.written = []
        XCTAssertFalse(ObservableDefaultsFlag(key: key, defaults: off).isEnabled)
        XCTAssertEqual(off.written, [])
    }

    // MARK: Writing

    func testSetWritesTheOneKeyAndPublishesOncePerChange() async throws {
        let defaults = try makeDefaults()
        let flag = ObservableDefaultsFlag(key: key, defaults: defaults)
        let seen = record(flag)

        flag.set(true)
        XCTAssertTrue(flag.isEnabled, "published before set returns")
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
        await settle()
        XCTAssertEqual(seen(), [false, true], "the echo of its own write is not a second change")

        flag.set(true)
        await settle()
        XCTAssertEqual(seen(), [false, true], "setting the same value publishes nothing")

        flag.set(false)
        XCTAssertFalse(flag.isEnabled)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false, "off is stored as false, not removed")
        await settle()
        XCTAssertEqual(seen(), [false, true, false])
        XCTAssertEqual(Set(defaults.written), [key], "only the flag's own key is ever written")
    }

    // MARK: Following

    func testTwoInstancesOnTheSameKeyAgree() async throws {
        let defaults = try makeDefaults()
        let first = ObservableDefaultsFlag(key: key, defaults: defaults)
        let second = ObservableDefaultsFlag(key: key, defaults: defaults)
        let seenByFirst = record(first)
        let seenBySecond = record(second)

        second.set(true)
        await waitUntil("the first copy to follow the second") { first.isEnabled }
        XCTAssertTrue(second.isEnabled)

        first.set(false)
        await waitUntil("the second copy to follow the first") { !second.isEnabled }

        defaults.set(true, forKey: key)             // a plain write to the key, by neither object
        await waitUntil("both copies to follow a plain write") { first.isEnabled && second.isEnabled }

        defaults.removeObject(forKey: key)
        await waitUntil("a removed key to read as off") { !first.isEnabled && !second.isEnabled }

        await settle()
        XCTAssertEqual(seenByFirst(), [false, true, false, true, false], "one publication per change")
        XCTAssertEqual(seenBySecond(), [false, true, false, true, false], "one publication per change")
        // A third copy made now reads what the others hold.
        XCTAssertEqual(ObservableDefaultsFlag(key: key, defaults: defaults).isEnabled, first.isEnabled)
    }

    func testAWriteToAnotherKeyIsNotAChange() async throws {
        let defaults = try makeDefaults()
        let flag = ObservableDefaultsFlag(key: key, defaults: defaults)
        let other = ObservableDefaultsFlag(key: otherKey, defaults: defaults)
        let seen = record(flag)
        let changes = recordChanges(flag)

        other.set(true)
        defaults.set(81.5, forKey: "profile.weightKg")
        defaults.set("x", forKey: key + ".suffix")
        await settle()
        XCTAssertTrue(other.isEnabled)
        XCTAssertFalse(flag.isEnabled, "two flags on two keys of one defaults are independent")
        XCTAssertEqual(seen(), [false])
        XCTAssertEqual(changes(), 0, "an unrelated write publishes nothing")
        XCTAssertNil(defaults.object(forKey: key))

        flag.set(true)
        other.set(false)
        await settle()
        XCTAssertTrue(flag.isEnabled)
        XCTAssertFalse(other.isEnabled)
        XCTAssertEqual(seen(), [false, true])
    }

    func testTwoDefaultsWithTheSameKeyAreIndependent() async throws {
        let one = try makeDefaults(), two = try makeDefaults()
        let first = ObservableDefaultsFlag(key: key, defaults: one)
        let second = ObservableDefaultsFlag(key: key, defaults: two)
        first.set(true)
        await settle()
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(second.isEnabled)
        XCTAssertEqual(two.written, [])
    }

    func testAWriteMadeOffTheMainThreadIsFollowed() async throws {
        let defaults = try makeDefaults()
        let flag = ObservableDefaultsFlag(key: key, defaults: defaults)
        let seen = record(flag)
        let key = self.key
        await Task.detached { defaults.set(true, forKey: key) }.value
        await waitUntil("the flag to follow a background write") { flag.isEnabled }
        await settle()
        XCTAssertEqual(seen(), [false, true])
    }

    func testAReleasedFlagStopsObserving() async throws {
        let defaults = try makeDefaults()
        weak var released: ObservableDefaultsFlag?
        do {
            let flag = ObservableDefaultsFlag(key: key, defaults: defaults)
            released = flag
            flag.set(true)
        }
        XCTAssertNil(released, "the observation does not keep the flag alive")
        defaults.set(false, forKey: key)            // must not reach a dead object
        await settle()
        XCTAssertFalse(ObservableDefaultsFlag(key: key, defaults: defaults).isEnabled)
    }

    // MARK: CutScorecardFlag is this object over its one key

    func testCutScorecardFlagAndTheGeneralFlagOnItsKeyAgree() async throws {
        XCTAssertEqual(CutScorecardSettings.enabledKey, "noop.cutScorecardEnabled")
        let defaults = try makeDefaults()
        let scorecard = CutScorecardFlag(defaults: defaults)
        let general = ObservableDefaultsFlag(key: CutScorecardSettings.enabledKey, defaults: defaults)
        var seenByScorecard: [Bool] = []
        scorecard.$isEnabled.sink { seenByScorecard.append($0) }.store(in: &observers)
        let seenByGeneral = record(general)
        XCTAssertFalse(scorecard.isEnabled)
        XCTAssertEqual(scorecard.displayPolicy, .legacyDisplay)
        XCTAssertEqual(defaults.written, [], "neither writes the key by being made or read")

        general.set(true)
        await waitUntil("the scorecard flag to follow the general flag") { scorecard.isEnabled }
        XCTAssertEqual(scorecard.displayPolicy, .unified)

        scorecard.set(false)
        XCTAssertFalse(scorecard.isEnabled, "published before set returns")
        XCTAssertEqual(scorecard.displayPolicy, .legacyDisplay)
        await waitUntil("the general flag to follow the scorecard flag") { !general.isEnabled }

        CutScorecardSettings(defaults: defaults).isEnabled = true
        await waitUntil("both to follow CutScorecardSettings") { scorecard.isEnabled && general.isEnabled }

        await settle()
        XCTAssertEqual(seenByScorecard, [false, true, false, true])
        XCTAssertEqual(seenByGeneral(), [false, true, false, true])
        XCTAssertEqual(Set(defaults.written), [CutScorecardSettings.enabledKey])

        // A flag on any other key does not move the scorecard flag.
        ObservableDefaultsFlag(key: key, defaults: defaults).set(true)
        defaults.set(false, forKey: key)
        await settle()
        XCTAssertEqual(seenByScorecard, [false, true, false, true])
    }

    /// The app's shared copy is still there, over the standard defaults, and reading it leaves the
    /// stored value as it was. Nothing is written here.
    func testTheSharedScorecardFlagStillReadsTheStandardDefaultsWithoutWriting() {
        let before = UserDefaults.standard.object(forKey: CutScorecardSettings.enabledKey) as? Bool
        let shared = CutScorecardFlag.shared
        XCTAssertTrue(shared === CutScorecardFlag.shared, "one shared copy")
        XCTAssertEqual(shared.isEnabled, before ?? false)
        XCTAssertEqual(shared.displayPolicy,
                       BodyMeasurementResolver.policy(flagEnabled: before ?? false, consumer: .display))
        XCTAssertEqual(UserDefaults.standard.object(forKey: CutScorecardSettings.enabledKey) as? Bool, before)
    }

    /// One implementation: the defaults observation lives in the general flag's file, and the
    /// scorecard flag is built on it rather than beside it.
    func testTheDefaultsObservationHasOneImplementation() throws {
        let general = ScaffoldingSource.codeLines(try ScaffoldingSource.text("Strand/Data/ObservableDefaultsFlag.swift"))
            .joined(separator: "\n")
        XCTAssertTrue(general.contains("class ObservableDefaultsFlag"))
        XCTAssertTrue(general.contains("UserDefaults.didChangeNotification"))

        let model = ScaffoldingSource.codeLines(try ScaffoldingSource.text("Strand/Data/CutScorecardModel.swift"))
            .joined(separator: "\n")
        XCTAssertTrue(model.contains("class CutScorecardFlag"), "the scorecard flag keeps its name and its file")
        XCTAssertTrue(model.contains("ObservableDefaultsFlag"), "CutScorecardFlag is built on ObservableDefaultsFlag")
        XCTAssertFalse(model.contains("didChangeNotification"), "and keeps no defaults observer of its own")
        XCTAssertFalse(model.contains("NotificationCenter"), "and keeps no defaults observer of its own")
    }
}

// MARK: - 5. The typical band (X7)

final class ScaffoldingTypicalBandTests: XCTestCase {

    private func state(_ baseline: Double, _ spread: Double, nValid: Int, since: Int = 0,
                       _ status: BaselineStatus) -> BaselineState {
        BaselineState(baseline: baseline, spread: spread, nValid: nValid, nightsSinceUpdate: since, status: status)
    }

    private func assertBand(_ range: ClosedRange<Double>?, _ expected: (Double, Double)?, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let expected else {
            XCTAssertNil(range, "\(label): no band is drawn", file: file, line: line)
            return
        }
        guard let range else {
            XCTFail("\(label): expected \(expected.0) to \(expected.1), got no band", file: file, line: line)
            return
        }
        // Bit for bit: the screen's numbers must not move by a unit in the last place.
        XCTAssertEqual(range.lowerBound.bitPattern, expected.0.bitPattern,
                       "\(label): lower \(range.lowerBound) is not \(expected.0)", file: file, line: line)
        XCTAssertEqual(range.upperBound.bitPattern, expected.1.bitPattern,
                       "\(label): upper \(range.upperBound) is not \(expected.1)", file: file, line: line)
    }

    // MARK: Baselines given directly

    /// Thirteen baseline states: every status, and the spreads at and below the sigma floor.
    func testTheBandOfABaselineState() {
        let table: [(String, BaselineState?, (Double, Double)?)] = [
            ("HRV, trusted", state(62.0, 8.0, nValid: 30, .trusted), (51.975999999999999, 72.024000000000001)),
            ("HRV, provisional at the floor spread", state(45.5, 5.0, nValid: 6, .provisional),
             (39.234999999999999, 51.765000000000001)),
            ("resting HR, trusted, one night since an update", state(52.0, 2.0, nValid: 40, since: 1, .trusted),
             (49.494, 54.506)),
            ("respiratory rate, trusted", state(14.6, 0.5, nValid: 21, .trusted), (13.9735, 15.2265)),
            ("calibrating: not enough history", state(62.0, 8.0, nValid: 3, .calibrating), nil),
            ("stale: enough history, none of it recent", state(62.0, 8.0, nValid: 30, since: 15, .stale), nil),
            ("zero spread: sigma is floored at 1e-9", state(60.0, 0.0, nValid: 20, .trusted),
             (59.999999999000003, 60.000000000999997)),
            ("negative spread: floored the same way", state(60.0, -3.0, nValid: 20, .trusted),
             (59.999999999000003, 60.000000000999997)),
            ("spread below the floor", state(60.0, 1e-12, nValid: 20, .trusted),
             (59.999999999000003, 60.000000000999997)),
            ("a negative baseline", state(-0.4, 0.3, nValid: 20, .trusted),
             (-0.77590000000000003, -0.024100000000000066)),
            ("a zero baseline, provisional", state(0.0, 1.0, nValid: 20, .provisional),
             (-1.2529999999999999, 1.2529999999999999)),
            ("large values", state(1e6, 1e3, nValid: 20, .trusted), (998_747, 1_001_253)),
            ("no baseline at all", nil, nil),
        ]
        XCTAssertEqual(table.count, 13)
        for (label, state, expected) in table {
            assertBand(ChargeTypicalBand.range(state), expected, label)
        }
    }

    /// The status decides, not the counts: a state is drawn exactly when it is provisional or trusted.
    func testOnlyUsableStatusesDrawABand() {
        let statuses: [(BaselineStatus, Bool)] = [(.calibrating, false), (.provisional, true), (.trusted, true),
                                                  (.stale, false)]
        for (status, drawn) in statuses {
            for nValid in [0, 3, 4, 14, 400] {
                for since in [0, 14, 15, 400] {
                    let range = ChargeTypicalBand.range(state(62.0, 8.0, nValid: nValid, since: since, status))
                    assertBand(range, drawn ? (51.975999999999999, 72.024000000000001) : nil,
                               "\(status) nValid \(nValid) since \(since)")
                }
            }
        }
    }

    // MARK: Baselines folded from a history

    /// Sixteen nightly histories, folded as the app folds them (`Baselines.foldHistory` with the
    /// metric's own configuration), and the band the Recovery screen draws for each.
    func testTheBandOfAFoldedHistory() throws {
        let hrv = try XCTUnwrap(Baselines.metricCfg["hrv"])
        let restingHR = try XCTUnwrap(Baselines.metricCfg["resting_hr"])
        let resp = try XCTUnwrap(Baselines.metricCfg["resp"])
        let fourteen: [Double?] = [60, 64, 58, 66, 61, 59, 63, 67, 55, 62, 60, 65, 58, 61]
        let missing = { (count: Int) in [Double?](repeating: nil, count: count) }

        let table: [(String, [Double?], MetricCfg, (Double, Double)?)] = [
            ("HRV, no nights", [], hrv, nil),
            ("HRV, three nights: still calibrating", [60, 64, 58], hrv, nil),
            ("HRV, four nights: the first provisional band", [60, 64, 58, 66], hrv,
             (55.165158941811818, 67.695158941811812)),
            ("HRV, thirteen nights: provisional", Array(fourteen.prefix(13)), hrv,
             (55.686478090382316, 68.21647809038231)),
            ("HRV, fourteen nights: trusted", fourteen, hrv, (55.64051708681265, 68.170517086812652)),
            ("HRV, fourteen nights then fourteen missed: held", fourteen + missing(14), hrv,
             (55.64051708681265, 68.170517086812652)),
            ("HRV, fourteen nights then fifteen missed: stale", fourteen + missing(15), hrv, nil),
            ("HRV, only implausible and missing nights", [300, 2, nil, 1000], hrv, nil),
            ("HRV, three nights then twenty missed: calibrating, not stale", [60, 64, 58] + missing(20), hrv, nil),
            ("HRV, four valid nights among missed ones", [60, nil, 62, nil, 58, 61], hrv,
             (53.873740521837448, 66.403740521837449)),
            ("HRV, settled, then one wild night that is not folded", fourteen + [200.0, 61.0], hrv,
             (55.59677622248789, 68.126776222487891)),
            ("HRV, six swinging nights: spread above the floor", [40, 90, 35, 95, 45, 85], hrv,
             (49.431683316852556, 69.561673552060896)),
            ("HRV, fifteen swinging nights: trusted, spread above the floor",
             [40, 90, 35, 95, 45, 85, 50, 100, 30, 80, 60, 70, 55, 75, 65], hrv,
             (54.012368031484414, 77.205695399733031)),
            ("resting HR, twenty identical nights", [Double?](repeating: 50, count: 20), restingHR, (47.494, 52.506)),
            ("resting HR, eight nights: provisional", [52, 54, 51, 55, 53, 50, 56, 52], restingHR,
             (50.27596816734895, 55.28796816734895)),
            ("respiratory rate, sixteen nights",
             [14.5, 15.0, 14.0, 15.5, 14.8, 13.9, 15.2, 14.4, 16.0, 14.1, 14.9, 15.3, 13.8, 14.7, 15.1, 14.6], resp,
             (14.051365289609649, 15.304365289609649)),
        ]
        XCTAssertEqual(table.count, 16)
        for (label, history, cfg, expected) in table {
            assertBand(ChargeTypicalBand.range(Baselines.foldHistory(history, cfg: cfg)), expected, label)
        }
    }

    // MARK: What the band means

    /// `RecoveryFactor.typical` documents the band as the one `Baselines.deviation` calls normal.
    func testTheBandIsTheRangeBaselinesDeviationCallsNormal() throws {
        let states = [state(62.0, 8.0, nValid: 30, .trusted), state(45.5, 5.0, nValid: 6, .provisional),
                      state(52.0, 2.0, nValid: 40, .trusted), state(14.6, 0.5, nValid: 21, .trusted),
                      state(-0.4, 0.3, nValid: 20, .trusted)]
        for state in states {
            let range = try XCTUnwrap(ChargeTypicalBand.range(state))
            let sigma = Baselines.sigma(state)
            XCTAssertEqual(range.lowerBound, state.baseline - sigma)
            XCTAssertEqual(range.upperBound, state.baseline + sigma)
            for fraction in [-0.99, -0.5, 0.0, 0.5, 0.99] {
                let value = state.baseline + fraction * sigma
                XCTAssertTrue(range.contains(value), "\(value)")
                XCTAssertTrue(Baselines.deviation(value, state: state).inNormalRange, "\(value)")
            }
            for fraction in [-3.0, -1.01, 1.01, 3.0] {
                let value = state.baseline + fraction * sigma
                XCTAssertFalse(range.contains(value), "\(value)")
                XCTAssertFalse(Baselines.deviation(value, state: state).inNormalRange, "\(value)")
            }
        }
    }

    // MARK: One definition (source scan)

    func testTheRecoveryScreenCallsTheSharedFunction() throws {
        let code = ScaffoldingSource.codeLines(try ScaffoldingSource.text("StrandiOS/Redesign/ScoreDetailData.swift"))
            .joined(separator: "\n")
        XCTAssertGreaterThanOrEqual(ScaffoldingSource.count(of: "ChargeTypicalBand.range(", in: code), 1,
                                    "RecoveryDetailModel takes its typical ranges from ChargeTypicalBand.range")
        XCTAssertFalse(code.contains("Baselines.sigma("), "and no longer computes the band itself")
        XCTAssertNil(code.range(of: #"func\s+band\s*\("#, options: .regularExpression),
                     "the nested band function is gone")
        // The three factors that had a band still have one, and Sleep still has none.
        for factor in ["baselines?.hrv", "baselines?.restingHR", "baselines?.resp"] {
            XCTAssertNotNil(code.range(of: "typical: ChargeTypicalBand.range(\(factor))"),
                            "the \(factor) factor's typical range comes from ChargeTypicalBand.range")
        }
        XCTAssertTrue(code.contains("kind: .sleep, value: restScore, typical: nil"), "Sleep has no typical range")
    }

    /// X7: baseline ± sigma as a "typical range" has one definition in the app targets.
    func testTheTypicalBandHasOneDefinition() throws {
        let home = "Strand/Data/ChargeTypicalBand.swift"
        var callers: [String] = []
        for file in ScaffoldingSource.appSwiftFiles() {
            let code = ScaffoldingSource.codeLines(try ScaffoldingSource.text(file)).joined(separator: "\n")
            if code.contains("Baselines.sigma(") { callers.append(file) }
        }
        XCTAssertEqual(callers, [home], "Baselines.sigma( is called in the app targets by ChargeTypicalBand only")
    }
}
