import XCTest
@testable import StrandAnalytics

final class CodexIntakeEventsPropertyTests: XCTestCase {
    func testIntakeAggregationConservesUniqueIntegerSamplesAndIgnoresOrder() {
        var seed = CodexPropertySeed(state: 0xC01605)
        for round in 0..<300 {
            let samples = (0..<64).map { index in
                IntakeSample(id: "\(index)", nutrient: index.isMultiple(of: 2) ? .protein : .energy,
                             startEpochSeconds: 1_925_596_800 + seed.next(7 * 86_400),
                             amount: Double(seed.next(300)), sourceId: "fixture")
            }
            func aggregate(_ input: [IntakeSample]) -> IntakeAggregationResult {
                IntakeAggregation.aggregate(samples: input, zoneLog: [], admittedSourceIds: nil,
                                            firstDay: "2030-01-01", lastDay: "2032-01-01")
            }
            let result = aggregate(samples)
            codexAssertFinite(result)
            XCTAssertEqual(result, aggregate(samples), "round \(round)")
            XCTAssertEqual(result, aggregate(samples.reversed()))
            XCTAssertEqual(result.totals.compactMap(\.proteinGrams).reduce(0, +),
                           samples.filter { $0.nutrient == .protein }.map(\.amount).reduce(0, +))
            XCTAssertEqual(result.totals.compactMap(\.energyKcal).reduce(0, +),
                           samples.filter { $0.nutrient == .energy }.map(\.amount).reduce(0, +))
            XCTAssertEqual(aggregate(samples + samples).totals, result.totals)
            let stored = result.totals.map {
                IntakeStoredDay(day: $0.day, proteinGrams: $0.proteinGrams, energyKcal: $0.energyKcal,
                                readAtEpochSeconds: 1)
            }
            let plan = IntakeAggregation.plan(result: result, stored: stored, readAtEpochSeconds: 2)
            codexAssertFinite(plan)
            XCTAssertTrue(plan.changedDays.isEmpty)
            XCTAssertTrue(plan.deletions.isEmpty)
            XCTAssertTrue(plan.upserts.allSatisfy { $0.key == IntakeAggregation.readAtKey })
        }
    }

    func testIntakeProgressExtremeInputsAreFiniteAndDeterministic() {
        var seed = CodexPropertySeed(state: 0xC01606)
        for _ in 0..<3_000 {
            let grams = seed.number(), floor = seed.number(), kcal = seed.number()
            let protein = IntakeProgress.protein(grams: grams, floorGrams: floor)
            codexAssertFinite(protein)
            XCTAssertEqual(protein, IntakeProgress.protein(grams: grams, floorGrams: floor))
            let targets = IntakeTargets(proteinFloorGrams: floor, energyLowKcal: 1_500,
                                        energyHighKcal: 2_000, energyHardFloorKcal: 1_200)
            let open = seed.next(2) == 0
            let energy = IntakeProgress.energy(kcal: kcal, targets: targets, dayIsOpen: open)
            codexAssertFinite(energy)
            XCTAssertEqual(energy, IntakeProgress.energy(kcal: kcal, targets: targets, dayIsOpen: open))
            if grams.isFinite, grams >= 0, floor.isFinite, floor > 0 {
                XCTAssertEqual(IntakeProgress.meetsFloor(grams: grams, floorGrams: floor), grams >= floor)
            }
        }
    }

    func testEventNormalizationVisibilityAndPacketBoundsOnGeneratedEvents() {
        var seed = CodexPropertySeed(state: 0xC01607)
        for round in 0..<300 {
            let events = (0..<40).map { index in
                PersonalEvent(id: "\(index)", kind: .custom, label: "Fixture \(index)",
                              startDay: CanonicalDay.adding(seed.next(20), to: "2031-01-01")!,
                              endDay: nil, note: "PRIVATE_\(round)_\(index)_END", sensitive: seed.next(2) == 0,
                              createdAt: index)
            }
            let normalized = PersonalEvents.normalized(events)
            XCTAssertEqual(normalized, PersonalEvents.normalized(events.reversed()))
            XCTAssertEqual(normalized, PersonalEvents.normalized(normalized))
            let visible = PersonalEvents.visible(events, includeSensitive: false)
            XCTAssertTrue(visible.allSatisfy { !$0.sensitive })
            let rows = PersonalEvents.packetLines(events: events, firstDay: "2031-01-01", lastDay: "2031-01-28",
                                                  includeSensitive: false)
            XCTAssertLessThanOrEqual(rows.joined(separator: "\n").utf8.count, PersonalEvents.packetByteAllowance)
            for event in events where event.sensitive { XCTAssertFalse(rows.joined().contains(event.note!)) }
            let slots = (0..<28).map { i -> PersonalEventSlot in
                let day = CanonicalDay.adding(i, to: "2031-01-01")!
                return PersonalEventSlot(firstDay: day, lastDay: day)
            }
            XCTAssertEqual(PersonalEvents.coveredSlots(events: events, slots: slots).count, slots.count)
        }
    }

    private func packet(eventRows: [String]) -> CoachPacketInput {
        CoachPacketInput(generatedAt: "2031-01-08T07:00:00+00:00", rangeStartDay: "2031-01-02",
                         rangeEndDay: "2031-01-08", sections: [.events], days: [], strainFactor: 1,
                         scorecard: .switchedOff, body: [], hrvBaseline: nil, restingHrBaseline: nil,
                         steps: [], workouts: [], intake: .switchedOff, events: .rows(eventRows))
    }

    func testPacketGeneratedTextSanitizationAndDeterminism() {
        var seed = CodexPropertySeed(state: 0xC01608)
        let alphabet = Array("Fixture é中🙂\n\t\r :;\\\u{0000}")
        for _ in 0..<1_000 {
            let text = String((0..<seed.next(240)).map { _ in alphabet[seed.next(alphabet.count)] })
            let sanitized = CoachPacket.sanitize(text)
            XCTAssertLessThanOrEqual(sanitized.utf8.count, 48)
            XCTAssertEqual(sanitized, CoachPacket.sanitize(sanitized))
            XCTAssertFalse(sanitized.unicodeScalars.contains { $0.properties.generalCategory == .control })
            let input = packet(eventRows: ["  " + text])
            let rendered = CoachPacket.render(input)
            XCTAssertEqual(rendered, CoachPacket.render(input))
            XCTAssertLessThanOrEqual(rendered.utf8.count, CoachPacket.byteBudget(rangeDays: 7))
        }
    }

    func testPacketScanSeesGeneratedRawIdentifiersAfterTheTextCut() {
        var seed = CodexPropertySeed(state: 0xC01616)
        for _ in 0..<300 {
            let identifier = "fixture-device-\(seed.next(1_000_000))"
            let raw = String(repeating: "x", count: 100) + identifier
            let input = packet(eventRows: [])
            let text = CoachPacket.render(input)
            let findings = CoachPacket.scan(input, rendered: text, identifiers: [identifier], freeText: [raw, raw])
            XCTAssertFalse(findings.isEmpty)
            XCTAssertEqual(findings.count, Set(findings).count)
            XCTAssertTrue(findings.allSatisfy { !$0.contains(identifier) })
            XCTAssertFalse(CoachPacket.scan(input, rendered: text, identifiers: nil).isEmpty)
        }
    }

    func testPacketBudgetForGeneratedUntrustedEventRows() {
        // The renderer promises a total, bounded result even for rows not produced by stage 5.
        // Repeated legal sentinel rows must be bounded just like repeated indented rows.
        var seed = CodexPropertySeed(state: 0xC01609)
        for _ in 0..<50 {
            let count = 1 + seed.next(400)
            let rows = Array(repeating: PersonalEvents.packetIntroRow, count: count)
            let bytes = CoachPacket.render(packet(eventRows: rows)).utf8.count
            let budget = CoachPacket.byteBudget(rangeDays: 7)
            if bytes > budget {
                let smallest = (1...count).first {
                    CoachPacket.render(packet(eventRows: Array(repeating: PersonalEvents.packetIntroRow, count: $0))).utf8.count > budget
                }!
                let shrunkBytes = CoachPacket.render(packet(eventRows: Array(repeating: PersonalEvents.packetIntroRow, count: smallest))).utf8.count
                let previousBytes = CoachPacket.render(packet(eventRows: Array(repeating: PersonalEvents.packetIntroRow, count: smallest - 1))).utf8.count
                XCTFail("Generated count \(count); shrunk to \(smallest) repeated intro rows (\(shrunkBytes) bytes); previous \(previousBytes); budget \(budget)")
                return
            }
        }
    }
}
