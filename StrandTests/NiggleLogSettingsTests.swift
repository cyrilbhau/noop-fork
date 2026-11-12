// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §9.1, §9.2, §9.4, §12.3 and ruling R42 before
// the implementation exists. The full API block is at the top of Stage6TestSupport.swift. This file
// calls `NiggleLogSettings` and its stored types, and, unchanged, `DeviceRegistry`,
// `WhoopStore.deleteAllData(deviceId:)` and the registry fixture `LabBookOwnershipAppFixture`.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. Fixtures are written in the stored shape of §9.2 and read back; ids the store issues are read
//     from the list after a save. A draft with an empty id is inserted with a new id.
//  2. A save that refuses returns false and writes nothing at all (every key byte-identical).
//  3. The rules string carries `"v":1` at its top level; its rule elements are those of §9.2's example.
//  4. The `today` closure the settings take is what "not after today at the time of saving" uses.
//
// Synthetic values only.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class NiggleLogSettingsTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func settings(_ defaults: UserDefaults, today: String = "2031-03-22") -> NiggleLogSettings {
        NiggleLogSettings(defaults: defaults, today: { today })
    }

    private func draft(_ location: String = "Fixture location A", onset: String = "2031-03-20",
                       kind: StoredNiggle.Kind = .complaint, note: String = "") -> StoredNiggle {
        StoredNiggle(id: "", kind: kind, location: location, side: .left,
                     character: kind == .complaint ? .diffuse : .other, onsetDay: onset, resolvedDay: nil,
                     trend: kind == .complaint ? .easing : .notRecorded, weakness: false, updates: [], note: note)
    }

    /// Asserts that every stored key other than `except` is byte-identical to `before`.
    private func assertOthersUnchanged(_ before: [String: String], _ defaults: UserDefaults, except: Set<String>,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let after = Stage6Text.raw(defaults)
        for (key, value) in before where !except.contains(key) {
            XCTAssertEqual(after[key], value, "\(key) changed", file: file, line: line)
        }
    }

    // MARK: Flag

    func testFlagDefaultsToOff() throws {
        let defaults = try suites.make()
        XCTAssertFalse(settings(defaults).isEnabled)
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.enabledKey), "reading the flag writes nothing")
        XCTAssertEqual(NiggleLogSettings.enabledKey, "noop.niggleLogEnabled")
        XCTAssertEqual(NiggleLogSettings.entriesKey, "niggleLog.entries")
        XCTAssertEqual(NiggleLogSettings.rulesKey, "niggleLog.rules")
        XCTAssertEqual(NiggleLogSettings.pausedKey, "niggleLog.paused")
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        XCTAssertTrue(settings(defaults).isEnabled)
    }

    // MARK: Stored shape

    func testEntriesRoundTripWithSortedKeysAndVersion() throws {
        let defaults = try suites.make()
        let text = Fx.storedEntries([Fx.n1, Fx.n2, Fx.n4])
        defaults.set(text, forKey: NiggleLogSettings.entriesKey)
        let store = settings(defaults)
        XCTAssertEqual(store.entries, [Fx.n1, Fx.n2, Fx.n4])
        XCTAssertFalse(store.entriesNeedAttention)

        // A replace that changes nothing writes back the same bytes: sorted keys, "v":1, omitted nils.
        XCTAssertTrue(store.save(Fx.n2))
        XCTAssertEqual(defaults.string(forKey: NiggleLogSettings.entriesKey), text)

        // A new entry is stored in the same shape with an issued id.
        XCTAssertTrue(store.save(draft()))
        let elements = try XCTUnwrap(Stage6Text.array(defaults, NiggleLogSettings.entriesKey))
        XCTAssertEqual(elements.count, 4)
        for element in elements {
            XCTAssertEqual(element["v"] as? Int, 1)
            XCTAssertNil(element["deviceId"])
        }
        let added = try XCTUnwrap(store.entries.first { !["n-00000001", "n-00000002", "n-00000004"].contains($0.id) })
        XCTAssertNotNil(added.id.range(of: "^n-[0-9a-f]{8}$", options: .regularExpression), added.id)
        let addedElement = try XCTUnwrap(elements.first { $0["id"] as? String == added.id })
        XCTAssertNil(addedElement["resolvedDay"], "an optional nil is omitted")
        // Sorted keys: the stored text equals its own re-serialisation with sorted keys.
        let stored = try XCTUnwrap(defaults.string(forKey: NiggleLogSettings.entriesKey))
        XCTAssertEqual(stored, Fx.json(elements))
    }

    func testReadingNeverWrites() {
        let defaults = suites.recording()
        Fx.seed(defaults)
        defaults.set("not json", forKey: NiggleLogSettings.pausedKey)
        defaults.writes = []
        let store = settings(defaults)
        _ = store.isEnabled
        _ = store.entries
        _ = store.entriesNeedAttention
        _ = store.rules
        _ = store.rulesNeedAttention
        _ = store.paused
        _ = store.pausedNeedAttention
        XCTAssertEqual(defaults.writes, [], "a read wrote \(defaults.writes)")
        XCTAssertEqual(defaults.string(forKey: NiggleLogSettings.pausedKey), "not json")
    }

    func testUnreadableEntriesReadAsEmptyAndNeedAttention() throws {
        for bad in ["not json", "{}", "[1]", "[{\"v\":1}]"] as [Any] {
            let defaults = try suites.make()
            defaults.set(bad, forKey: NiggleLogSettings.entriesKey)
            let store = settings(defaults)
            XCTAssertEqual(store.entries, [], "\(bad)")
            XCTAssertTrue(store.entriesNeedAttention, "\(bad)")
        }
        let defaults = try suites.make()
        defaults.set(42, forKey: NiggleLogSettings.entriesKey)
        XCTAssertTrue(settings(defaults).entriesNeedAttention, "a stored value that is not a string")
        let empty = try suites.make()
        XCTAssertFalse(settings(empty).entriesNeedAttention, "nothing stored is not unreadable")
        XCTAssertEqual(settings(empty).entries, [])
    }

    func testSaveIsRefusedWhileEntriesNeedAttention() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        defaults.set("not json", forKey: NiggleLogSettings.entriesKey)
        let before = Stage6Text.raw(defaults)
        let store = settings(defaults)
        XCTAssertFalse(store.save(draft()))
        XCTAssertFalse(store.delete(niggleId: "n-00000001"))
        XCTAssertFalse(store.resolve(niggleId: "n-00000002", on: "2031-03-22"))
        XCTAssertFalse(store.addUpdate(niggleId: "n-00000002", day: "2031-03-22", trend: .easing, weakness: false, note: ""))
        XCTAssertEqual(Stage6Text.raw(defaults), before, "an unreadable log is never replaced")
    }

    func testDiscardRemovesOnlyUnreadableData() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let before = Stage6Text.raw(defaults)
        let store = settings(defaults)
        XCTAssertFalse(store.discardUnreadableEntries(), "a readable list is not discarded")
        XCTAssertFalse(store.discardUnreadableRules())
        XCTAssertFalse(store.discardUnreadablePaused())
        XCTAssertEqual(Stage6Text.raw(defaults), before)

        defaults.set("not json", forKey: NiggleLogSettings.rulesKey)
        let unreadable = Stage6Text.raw(defaults)
        XCTAssertTrue(store.discardUnreadableRules())
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.rulesKey))
        XCTAssertFalse(store.rulesNeedAttention)
        assertOthersUnchanged(unreadable, defaults, except: [NiggleLogSettings.rulesKey])
    }

    func testOneUnreadableElementMakesTheWholeListUnreadable() throws {
        let defaults = try suites.make()
        var elements = [Fx.element(Fx.n1), Fx.element(Fx.n2)]
        elements[1]["location"] = nil
        defaults.set(Fx.json(elements), forKey: NiggleLogSettings.entriesKey)
        let store = settings(defaults)
        XCTAssertEqual(store.entries, [])
        XCTAssertTrue(store.entriesNeedAttention)

        let paused = try suites.make()
        var pausedElements = [Fx.element(Fx.pausedPress), Fx.element(Fx.pausedRow)]
        pausedElements[0]["reason"] = nil
        paused.set(Fx.json(pausedElements), forKey: NiggleLogSettings.pausedKey)
        XCTAssertEqual(settings(paused).paused, [])
        XCTAssertTrue(settings(paused).pausedNeedAttention)
    }

    // MARK: Operations, with per-row counts before and after

    func testSaveReplacesById() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let store = settings(defaults)
        let before = Stage6Text.raw(defaults)
        var edited = Fx.n2
        edited.location = "Fixture location B edited"
        XCTAssertTrue(store.save(edited))
        XCTAssertEqual(store.entries.count, 3, "a replace adds no row")
        XCTAssertEqual(store.entries.first { $0.id == Fx.n2.id }?.location, "Fixture location B edited")
        XCTAssertEqual(store.entries.filter { $0.id != Fx.n2.id }, [Fx.n1, Fx.n4], "no other entry changes")
        assertOthersUnchanged(before, defaults, except: [NiggleLogSettings.entriesKey])

        XCTAssertTrue(store.save(draft()))
        XCTAssertEqual(store.entries.count, 4, "an insert adds one row")
    }

    func testDeleteRemovesOnlyThatEntry() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let store = settings(defaults)
        let before = Stage6Text.raw(defaults)
        XCTAssertTrue(store.delete(niggleId: Fx.n1.id))
        XCTAssertEqual(store.entries, [Fx.n2, Fx.n4])
        XCTAssertFalse(store.delete(niggleId: "n-ffffffff"), "an unknown id deletes nothing")
        XCTAssertEqual(store.entries.count, 2)
        assertOthersUnchanged(before, defaults, except: [NiggleLogSettings.entriesKey])
    }

    func testResolveAndReopen() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let store = settings(defaults, today: "2031-03-22")
        XCTAssertTrue(store.resolve(niggleId: Fx.n2.id, on: "2031-03-22"))
        XCTAssertEqual(store.entries.first { $0.id == Fx.n2.id }?.resolvedDay, "2031-03-22")
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertTrue(store.reopen(niggleId: Fx.n2.id))
        XCTAssertNil(store.entries.first { $0.id == Fx.n2.id }?.resolvedDay)
        XCTAssertEqual(store.entries.first { $0.id == Fx.n2.id }, Fx.n2, "reopen restores the entry as it was")
        XCTAssertEqual(store.entries.first { $0.id == Fx.n1.id }, Fx.n1, "another entry is untouched")
    }

    func testFutureOnsetIsRefused() throws {
        let defaults = try suites.make()
        let store = settings(defaults, today: "2031-03-22")
        XCTAssertFalse(store.save(draft(onset: "2031-03-23")))
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.entriesKey), "nothing written")
        XCTAssertTrue(store.save(draft(onset: "2031-03-22")), "today itself is allowed")
        XCTAssertFalse(store.save(draft(onset: "2031-3-1")), "a day key that is not canonical")
    }

    func testResolvedBeforeOnsetIsRefused() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let store = settings(defaults, today: "2031-03-22")
        let before = Stage6Text.raw(defaults)
        XCTAssertFalse(store.resolve(niggleId: Fx.n2.id, on: "2031-03-02"))
        XCTAssertFalse(store.resolve(niggleId: Fx.n2.id, on: "2031-03-23"), "after today")
        XCTAssertEqual(Stage6Text.raw(defaults), before)
        XCTAssertTrue(store.resolve(niggleId: Fx.n2.id, on: "2031-03-03"), "on the onset day")
    }

    func testAddUpdateAssignsTheNextSequence() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let store = settings(defaults, today: "2031-03-25")
        XCTAssertTrue(store.addUpdate(niggleId: Fx.n2.id, day: "2031-03-24", trend: .easing, weakness: true,
                                      note: "Fixture update"))
        XCTAssertTrue(store.addUpdate(niggleId: Fx.n2.id, day: "2031-03-24", trend: .unchanged, weakness: false, note: ""))
        let updates = try XCTUnwrap(store.entries.first { $0.id == Fx.n2.id }?.updates)
        XCTAssertEqual(updates.map(\.seq), [1, 2, 3], "1 + the greatest seq in the entry")
        XCTAssertEqual(updates[1], StoredNiggleUpdate(seq: 2, day: "2031-03-24", trend: .easing, weakness: true,
                                                     note: "Fixture update"))
        XCTAssertFalse(store.addUpdate(niggleId: Fx.n2.id, day: "2031-03-26", trend: .easing, weakness: false, note: ""),
                       "an update after today")
        XCTAssertTrue(store.deleteUpdate(niggleId: Fx.n2.id, seq: 2))
        XCTAssertEqual(store.entries.first { $0.id == Fx.n2.id }?.updates.map(\.seq), [1, 3])
        XCTAssertTrue(store.addUpdate(niggleId: Fx.n2.id, day: "2031-03-25", trend: .easing, weakness: false, note: ""))
        XCTAssertEqual(store.entries.first { $0.id == Fx.n2.id }?.updates.map(\.seq), [1, 3, 4])
        XCTAssertEqual(store.entries.first { $0.id == Fx.n1.id }, Fx.n1)
    }

    func testLimitsRefuseAndNeverTruncate() throws {
        // 500 entries.
        let full = try suites.make()
        let many = (0..<500).map { i -> StoredNiggle in
            var n = Fx.n1
            n.id = String(format: "n-%08x", i + 0x100)
            return n
        }
        full.set(Fx.storedEntries(many), forKey: NiggleLogSettings.entriesKey)
        let before = full.string(forKey: NiggleLogSettings.entriesKey)
        XCTAssertFalse(settings(full).save(draft()))
        XCTAssertEqual(full.string(forKey: NiggleLogSettings.entriesKey), before)
        XCTAssertEqual(settings(full).entries.count, 500)

        // 100 updates on one entry.
        let updates = try suites.make()
        var busy = Fx.n2
        busy.updates = (1...100).map { StoredNiggleUpdate(seq: $0, day: "2031-03-10", trend: .easing, weakness: false, note: "") }
        updates.set(Fx.storedEntries([busy]), forKey: NiggleLogSettings.entriesKey)
        XCTAssertFalse(settings(updates).addUpdate(niggleId: busy.id, day: "2031-03-11", trend: .easing, weakness: false,
                                                   note: ""))
        XCTAssertEqual(settings(updates).entries.first?.updates.count, 100)

        // Text limits: location 60, note 500.
        let text = try suites.make()
        XCTAssertTrue(settings(text).save(draft(String(repeating: "x", count: 60))))
        XCTAssertFalse(settings(text).save(draft(String(repeating: "x", count: 61))))
        XCTAssertFalse(settings(text).save(draft(note: String(repeating: "y", count: 501))))
        XCTAssertEqual(settings(text).entries.count, 1, "a refused save is never stored truncated")

        // 20 rules.
        let rules = try suites.make()
        let twenty = (1...20).map { i in
            StoredTriageRule(id: String(format: "r-%08x", i), label: "Fixture label \(i)", action: .watch, characters: [],
                             trends: [], weakness: nil, fromDay: nil, throughDay: nil, note: "")
        }
        XCTAssertTrue(settings(rules).saveRules(StoredTriageRules(professionalRule: "", rules: twenty)))
        let extra = StoredTriageRule(id: "", label: "Fixture label 21", action: .watch, characters: [], trends: [],
                                     weakness: nil, fromDay: nil, throughDay: nil, note: "")
        XCTAssertFalse(settings(rules).saveRules(StoredTriageRules(professionalRule: "", rules: twenty + [extra])))
        XCTAssertEqual(settings(rules).rules.rules.count, 20)

        // 100 paused exercises.
        let paused = try suites.make()
        let hundred = (0..<100).map { i -> StoredPausedExercise in
            var p = Fx.pausedRow
            p.id = String(format: "p-%08x", i + 0x100)
            return p
        }
        paused.set(Fx.storedPaused(hundred), forKey: NiggleLogSettings.pausedKey)
        var another = Fx.pausedPress
        another.id = ""
        another.niggleId = nil
        XCTAssertFalse(settings(paused).save(another))
        XCTAssertEqual(settings(paused).paused.count, 100)
    }

    func testTextIsTrimmedAndEmptyLocationRefused() throws {
        let defaults = try suites.make()
        let store = settings(defaults)
        XCTAssertFalse(store.save(draft("   \n ")))
        XCTAssertFalse(store.save(draft("")))
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.entriesKey))
        XCTAssertTrue(store.save(draft("  Fixture location A \n", note: "\n Fixture note  ")))
        XCTAssertEqual(store.entries.first?.location, "Fixture location A")
        XCTAssertEqual(store.entries.first?.note, "Fixture note")

        var paused = Fx.pausedPress
        paused.id = ""
        paused.niggleId = nil
        paused.reason = "  "
        XCTAssertFalse(store.save(paused), "the reason is required")
        paused.reason = " Fixture reason A "
        paused.exercise = " Fixture Press "
        XCTAssertTrue(store.save(paused))
        XCTAssertEqual(store.paused.first?.reason, "Fixture reason A")
        XCTAssertEqual(store.paused.first?.exercise, "Fixture Press")
    }

    // MARK: Rules

    func testRulesRoundTripAndInvalidRulesNeedAttention() throws {
        let defaults = try suites.make()
        let text = Fx.storedRules(Fx.rules)
        defaults.set(text, forKey: NiggleLogSettings.rulesKey)
        let store = settings(defaults)
        XCTAssertEqual(store.rules, Fx.rules)
        XCTAssertEqual(store.rules.rules.map(\.triageRule),
                       [NiggleTriageRule(id: "r-0000000a", action: .watch, characters: [.diffuse], trends: [.easing],
                                         weakness: nil, fromDay: 1, throughDay: 10),
                        NiggleTriageRule(id: "r-0000000b", action: .modify, characters: [.positional], trends: [],
                                         weakness: nil, fromDay: 5, throughDay: nil),
                        NiggleTriageRule(id: "r-0000000c", action: .seeProfessional, characters: [], trends: [],
                                         weakness: nil, fromDay: 30, throughDay: nil),
                        NiggleTriageRule(id: "r-0000000d", action: .seeProfessional, characters: [], trends: [.worsening],
                                         weakness: nil, fromDay: 20, throughDay: nil),
                        NiggleTriageRule(id: "r-0000000e", action: .modify, characters: [.localised], trends: [],
                                         weakness: true, fromDay: 1, throughDay: nil)])
        XCTAssertTrue(store.saveRules(Fx.rules))
        XCTAssertEqual(defaults.string(forKey: NiggleLogSettings.rulesKey), text, "same rules, same bytes")
        XCTAssertEqual(Stage6Text.object(defaults, NiggleLogSettings.rulesKey)?["v"] as? Int, 1)

        // A stored list that fails `rulesAreValid` is unreadable.
        for broken in [[Fx.ruleA, Fx.ruleA], [{ var r = Fx.ruleB; r.fromDay = 0; return r }()],
                       [{ var r = Fx.ruleA; r.throughDay = 0; return r }()]] {
            let bad = try suites.make()
            bad.set(Fx.storedRules(StoredTriageRules(professionalRule: "", rules: broken)), forKey: NiggleLogSettings.rulesKey)
            XCTAssertTrue(settings(bad).rulesNeedAttention)
            XCTAssertEqual(settings(bad).rules.rules, [])
            XCTAssertFalse(NiggleTriage.rulesAreValid(broken.map(\.triageRule)))
        }
        // Saving an invalid list is refused; an empty label is refused.
        XCTAssertFalse(store.saveRules(StoredTriageRules(professionalRule: "", rules: [{ var r = Fx.ruleB; r.fromDay = 0; return r }()])))
        XCTAssertFalse(store.saveRules(StoredTriageRules(professionalRule: "", rules: [{ var r = Fx.ruleB; r.label = " "; return r }()])))
        XCTAssertFalse(store.saveRules(StoredTriageRules(professionalRule: String(repeating: "z", count: 301), rules: [])))
        XCTAssertEqual(defaults.string(forKey: NiggleLogSettings.rulesKey), text)
    }

    func testNoRulesAreStoredByDefault() throws {
        let defaults = try suites.make()
        let store = settings(defaults)
        XCTAssertEqual(store.rules.rules, [], "the app ships no rule")
        XCTAssertEqual(store.rules.professionalRule, "")
        XCTAssertFalse(store.rulesNeedAttention)
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.rulesKey), "reading the default writes nothing")
        // A complaint saved with no rules stored still creates no rule.
        XCTAssertTrue(store.save(draft()))
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.rulesKey))
        XCTAssertEqual(store.rules.rules, [])
    }

    // MARK: Paused exercises

    func testPausedRoundTripResumeAndDelete() throws {
        let defaults = try suites.make()
        let text = Fx.storedPaused([Fx.pausedPress, Fx.pausedRow])
        defaults.set(text, forKey: NiggleLogSettings.pausedKey)
        let store = settings(defaults, today: "2031-03-22")
        XCTAssertEqual(store.paused, [Fx.pausedPress, Fx.pausedRow])
        XCTAssertTrue(store.save(Fx.pausedPress))
        XCTAssertEqual(defaults.string(forKey: NiggleLogSettings.pausedKey), text)

        XCTAssertFalse(store.resume(pausedId: Fx.pausedPress.id, on: "2031-03-09"), "before the paused day")
        XCTAssertTrue(store.resume(pausedId: Fx.pausedPress.id, on: "2031-03-20"))
        XCTAssertEqual(store.paused.first { $0.id == Fx.pausedPress.id }?.resumedDay, "2031-03-20")
        XCTAssertEqual(store.paused.count, 2)
        XCTAssertTrue(store.delete(pausedId: Fx.pausedRow.id))
        XCTAssertEqual(store.paused.map(\.id), [Fx.pausedPress.id])
    }

    func testDeletingANiggleUnlinksItsPausedExercises() throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        let store = settings(defaults)
        XCTAssertTrue(store.delete(niggleId: Fx.n2.id))
        XCTAssertEqual(store.paused.count, 2, "the pause stays")
        let press = try XCTUnwrap(store.paused.first { $0.id == Fx.pausedPress.id })
        XCTAssertNil(press.niggleId, "unlinked")
        XCTAssertEqual(press.exercise, "Fixture Press")
        XCTAssertEqual(press.reason, "Fixture reason A")
        XCTAssertEqual(store.paused.first { $0.id == Fx.pausedRow.id }, Fx.pausedRow)
    }

    // MARK: Ruling R42

    func testStoredStringsContainNoDeviceIdentifier() throws {
        let defaults = try suites.make()
        let store = settings(defaults, today: "2031-06-16")
        for n in [Fx.n1, Fx.n2, Fx.n3, Fx.n4, Fx.n5, Fx.n6, Fx.n7] {
            var fresh = n
            fresh.id = ""
            XCTAssertTrue(store.save(fresh), n.location)
        }
        XCTAssertTrue(store.saveRules(Fx.rules))
        for p in [Fx.pausedPress, Fx.pausedRow] {
            var fresh = p
            fresh.id = ""
            fresh.niggleId = nil
            XCTAssertTrue(store.save(fresh))
        }
        let ids = LabBookOwnershipAppFixture.everyId + [CoachPacketHarness.deviceId]
        for key in [NiggleLogSettings.entriesKey, NiggleLogSettings.rulesKey, NiggleLogSettings.pausedKey] {
            let text = try XCTUnwrap(defaults.string(forKey: key), key)
            XCTAssertFalse(text.contains("deviceId"), key)
            XCTAssertFalse(text.lowercased().contains("strap"), key)
            for id in ids { XCTAssertFalse(text.contains(id), "\(key) holds \(id)") }
        }
    }

    func testRemovingEveryRegisteredStrapLeavesTheLogReadable() async throws {
        typealias LB = LabBookOwnershipAppFixture
        let defaults = try suites.make()
        Fx.seed(defaults)
        let before = Stage6Text.raw(defaults)
        let store = try await LB.emptyStoreWithRegistry()
        let registry = DeviceRegistry(store: LB.registry(store))
        registry.reload()
        for id in [LB.b, LB.d, LB.n] { await registry.deleteDeviceData(id, store: store) }
        try await store.deleteAllData(deviceId: LB.a)
        await registry.forget(LB.b, store: store)
        await registry.forget(LB.d, store: store)

        XCTAssertEqual(Stage6Text.raw(defaults), before, "no strap operation touches a stored list")
        let settings = settings(defaults)
        XCTAssertEqual(settings.entries, [Fx.n1, Fx.n2, Fx.n4])
        XCTAssertEqual(settings.rules, Fx.rules)
        XCTAssertEqual(settings.paused, [Fx.pausedPress, Fx.pausedRow])
        XCTAssertEqual(CheckpointTimelineSettings(defaults: defaults).checkpoints, Fx.checkpoints)
    }
}
