import XCTest
import Foundation

final class CodexChartAxisPropertyTests: XCTestCase {
    func testProductionAxisMathWithFixedSeedGeneratedPositions() throws {
        // This target cannot depend on SwiftUI's design package. Compile the unchanged pure
        // declarations from its production file; no copied algorithm or target edit is needed.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = root.appendingPathComponent("Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let marker = try XCTUnwrap(text.range(of: "/// The fixed-height strip of event dots under a plot"))
        let math = String(text[..<marker.lowerBound]).replacingOccurrences(of: "import SwiftUI", with: "import Foundation")
        let scratch = root.appendingPathComponent("build/codex-axis-property-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let mathURL = scratch.appendingPathComponent("Axis.swift")
        let driverURL = scratch.appendingPathComponent("main.swift")
        let binary = scratch.appendingPathComponent("probe")
        try math.write(to: mathURL, atomically: true, encoding: .utf8)
        let driver = #"""
        import Foundation
        var state: UInt64 = 0xC01615
        func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state % UInt64(n))
        }
        for _ in 0..<5_000 {
            let count = next(100)
            let covered = (0..<count).map { _ in next(2) == 0 }
            let xs = (0..<count).map { _ in Double(next(200) - 100) }
            for marks in [NoopChartAxisMarks.points(covered: covered), NoopChartAxisMarks.bars(covered: covered),
                          NoopChartAxisMarks.values(xs, covered: covered, domain: -50...50)] {
                precondition(marks.fractions.allSatisfy { $0.isFinite && (0...1).contains($0) })
                precondition(marks.fractions == Array(Set(marks.fractions)).sorted())
                let width = CGFloat(next(600) + 1)
                let offsets = ChartAxisMarkLayout.offsets(marks, width: width, leading: 2, trailing: 3, minSpacing: 8)
                precondition(offsets.allSatisfy { $0.isFinite && $0 >= 2 && $0 <= width - 3 })
                precondition(offsets == Array(Set(offsets)).sorted())
            }
        }
        print("5000 chart-axis cases passed")
        """#
        try driver.write(to: driverURL, atomically: true, encoding: .utf8)
        func run(_ arguments: [String]) throws -> (Int32, String) {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        let compiled = try run(["swiftc", "-module-cache-path", scratch.appendingPathComponent("cache").path,
                                mathURL.path, driverURL.path, "-o", binary.path])
        XCTAssertEqual(compiled.0, 0, compiled.1)
        guard compiled.0 == 0 else { return }
        let result = try run([binary.path])
        XCTAssertEqual(result.0, 0, result.1)
        XCTAssertTrue(result.1.contains("5000 chart-axis cases passed"), result.1)
    }
}
