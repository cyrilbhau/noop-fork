import XCTest
@testable import StrandDesign

/// Pins the Today ambient-field formula (`docs/personal/REDESIGN-IMPLEMENTATION.md` §3.7) and the fixed
/// palettes. The view only draws what `ambientBlobs(for:intensity:)` returns, so these cover what the user
/// sees except the rendering itself.
final class AmbientFieldTests: XCTestCase {

    private let accuracy = 1e-9

    private func blob(_ hues: Set<AmbientHue>, in blobs: [AmbientBlob]) -> AmbientBlob? {
        blobs.first { hues.contains($0.hue) }
    }

    private func recoveryBlob(_ blobs: [AmbientBlob]) -> AmbientBlob? {
        blob([.recoveryLow, .recoveryMid, .recoveryHigh], in: blobs)
    }

    private func assertBlob(_ b: AmbientBlob?, x: Double, y: Double, radius: Double, alpha: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let b else { return XCTFail("blob missing", file: file, line: line) }
        XCTAssertEqual(b.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(b.y, y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(b.radius, radius, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(b.alpha, alpha, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Formula

    func testSleepBlobAt0And50And100() {
        assertBlob(blob([.sleep], in: ambientBlobs(for: TodayScores(sleep: 0))), x: 40, y: 10, radius: 150, alpha: 0.16)
        assertBlob(blob([.sleep], in: ambientBlobs(for: TodayScores(sleep: 50))), x: 40, y: 10, radius: 235, alpha: 0.35)
        assertBlob(blob([.sleep], in: ambientBlobs(for: TodayScores(sleep: 100))), x: 40, y: 10, radius: 320, alpha: 0.54)
    }

    func testStrainBlobAt0AndHalfAndFull() {
        assertBlob(blob([.strain], in: ambientBlobs(for: TodayScores(strain: 0))), x: 380, y: 40, radius: 150, alpha: 0.16)
        assertBlob(blob([.strain], in: ambientBlobs(for: TodayScores(strain: 10.5))), x: 380, y: 40, radius: 235, alpha: 0.35)
        assertBlob(blob([.strain], in: ambientBlobs(for: TodayScores(strain: 21))), x: 380, y: 40, radius: 320, alpha: 0.54)
    }

    func testRecoveryBlobAt0And50And100() {
        assertBlob(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 0))), x: 210, y: -30, radius: 170, alpha: 0.18)
        assertBlob(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 50))), x: 210, y: -30, radius: 265, alpha: 0.39)
        assertBlob(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 100))), x: 210, y: -30, radius: 360, alpha: 0.60)
    }

    func testAllThreeScoresInMockupOrder() {
        // The mockups' "today:86,68,11.4": sleep, strain, then recovery drawn on top.
        let blobs = ambientBlobs(for: TodayScores(sleep: 86, recovery: 68, strain: 11.4))
        XCTAssertEqual(blobs.map(\.hue), [.sleep, .strain, .recoveryHigh])
        assertBlob(blobs[0], x: 40, y: 10, radius: 150 + 170 * 0.86, alpha: 0.16 + 0.38 * 0.86)
        assertBlob(blobs[1], x: 380, y: 40, radius: 150 + 170 * 11.4 / 21, alpha: 0.16 + 0.38 * 11.4 / 21)
        assertBlob(blobs[2], x: 210, y: -30, radius: 170 + 190 * 0.68, alpha: 0.18 + 0.42 * 0.68)
    }

    // MARK: - Missing data

    func testMissingScoreContributesNoBlob() {
        XCTAssertEqual(ambientBlobs(for: TodayScores(sleep: 80, strain: 9)).map(\.hue), [.sleep, .strain])
        XCTAssertEqual(ambientBlobs(for: TodayScores(recovery: 70)).map(\.hue), [.recoveryHigh])
        XCTAssertEqual(ambientBlobs(for: TodayScores(sleep: 80, recovery: 20)).map(\.hue), [.sleep, .recoveryLow])
    }

    func testNoScoresIsTheSingleNeutralBlob() {
        XCTAssertEqual(ambientBlobs(for: .empty), [AmbientBlob.neutral])
        XCTAssertEqual(AmbientBlob.neutral.hue, .neutral)
        XCTAssertEqual(AmbientBlob.neutral.alpha, 0.3, accuracy: accuracy)
    }

    func testNonFiniteScoreIsTreatedAsMissing() {
        XCTAssertEqual(ambientBlobs(for: TodayScores(sleep: .nan, recovery: .infinity, strain: -.infinity)),
                       [AmbientBlob.neutral])
        XCTAssertEqual(ambientBlobs(for: TodayScores(sleep: .nan, strain: 5)).map(\.hue), [.strain])
    }

    // MARK: - Recovery band

    func testRecoveryBandColourAtThresholds() {
        XCTAssertEqual(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 33)))?.hue, .recoveryLow)
        XCTAssertEqual(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 34)))?.hue, .recoveryMid)
        XCTAssertEqual(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 66)))?.hue, .recoveryMid)
        XCTAssertEqual(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 67)))?.hue, .recoveryHigh)
    }

    func testRecoveryHueMapsEveryBand() {
        XCTAssertEqual(AmbientHue.recovery(.low), .recoveryLow)
        XCTAssertEqual(AmbientHue.recovery(.mid), .recoveryMid)
        XCTAssertEqual(AmbientHue.recovery(.high), .recoveryHigh)
    }

    // MARK: - Intensity

    func testIntensityMultipliers() {
        XCTAssertEqual(AmbientIntensity.subtle.multiplier, 0.6)
        XCTAssertEqual(AmbientIntensity.balanced.multiplier, 1.0)
        XCTAssertEqual(AmbientIntensity.vivid.multiplier, 1.4)
        XCTAssertEqual(AmbientIntensity.allCases.map(\.rawValue), ["subtle", "balanced", "vivid"])
    }

    func testIntensityScalesAlphaOnly() {
        let scores = TodayScores(sleep: 50, recovery: 50, strain: 10.5)
        let balanced = ambientBlobs(for: scores, intensity: .balanced)
        for intensity in AmbientIntensity.allCases {
            let scaled = ambientBlobs(for: scores, intensity: intensity)
            XCTAssertEqual(scaled.count, balanced.count)
            for (s, b) in zip(scaled, balanced) {
                XCTAssertEqual(s.hue, b.hue)
                XCTAssertEqual(s.x, b.x, accuracy: accuracy)
                XCTAssertEqual(s.y, b.y, accuracy: accuracy)
                XCTAssertEqual(s.radius, b.radius, accuracy: accuracy)
                XCTAssertEqual(s.alpha, b.alpha * intensity.multiplier, accuracy: accuracy)
            }
        }
    }

    func testIntensityAppliesToNeutralBlob() {
        XCTAssertEqual(ambientBlobs(for: .empty, intensity: .subtle).first?.alpha ?? -1, 0.18, accuracy: accuracy)
    }

    func testAlphaIsCappedAtOne() {
        let blob = AmbientBlob(hue: .sleep, x: 0, y: 0, radius: 100, alpha: 0.9)
        XCTAssertEqual(blob.scaled(by: .vivid).alpha, 1)
        XCTAssertEqual(blob.scaled(by: .subtle).alpha, 0.54, accuracy: accuracy)
        // The strongest score blob (recovery 100, α 0.60) at Vivid stays within 0…1.
        let vivid = ambientBlobs(for: TodayScores(recovery: 100), intensity: .vivid)
        XCTAssertEqual(vivid.first?.alpha ?? -1, 0.84, accuracy: accuracy)
        for preset in AmbientPreset.all {
            for b in preset.blobs(intensity: .vivid) {
                XCTAssertLessThanOrEqual(b.alpha, 1, "\(preset)")
            }
        }
    }

    // MARK: - Clamping

    func testOutOfRangeInputsAreClamped() {
        XCTAssertEqual(ambientBlobs(for: TodayScores(sleep: 140)), ambientBlobs(for: TodayScores(sleep: 100)))
        XCTAssertEqual(ambientBlobs(for: TodayScores(sleep: -20)), ambientBlobs(for: TodayScores(sleep: 0)))
        XCTAssertEqual(ambientBlobs(for: TodayScores(strain: 30)), ambientBlobs(for: TodayScores(strain: 21)))
        XCTAssertEqual(ambientBlobs(for: TodayScores(strain: -1)), ambientBlobs(for: TodayScores(strain: 0)))
        XCTAssertEqual(ambientBlobs(for: TodayScores(recovery: 120)), ambientBlobs(for: TodayScores(recovery: 100)))
        XCTAssertEqual(ambientBlobs(for: TodayScores(recovery: -5)), ambientBlobs(for: TodayScores(recovery: 0)))
        // Band colour follows the clamped value.
        XCTAssertEqual(recoveryBlob(ambientBlobs(for: TodayScores(recovery: -5)))?.hue, .recoveryLow)
        XCTAssertEqual(recoveryBlob(ambientBlobs(for: TodayScores(recovery: 120)))?.hue, .recoveryHigh)
    }

    // MARK: - Presets

    func testRecoveryPresetTakesBandColour() {
        XCTAssertEqual(AmbientPreset.recovery(.high).baseBlobs.first?.hue, .recoveryHigh)
        XCTAssertEqual(AmbientPreset.recovery(.mid).baseBlobs.first?.hue, .recoveryMid)
        XCTAssertEqual(AmbientPreset.recovery(.low).baseBlobs.first?.hue, .recoveryLow)
        XCTAssertEqual(AmbientPreset.recovery(nil).baseBlobs.first?.hue, .neutral)
        XCTAssertEqual(AmbientPreset.recovery(.high).baseBlobs.last?.hue, .hrv)
    }

    func testPresetsMatchMockupSamples() {
        XCTAssertEqual(AmbientPreset.sleep.baseBlobs, [
            AmbientBlob(hue: .sleep, x: 120, y: 20, radius: 290, alpha: 0.48),
            AmbientBlob(hue: .rem, x: 380, y: 120, radius: 180, alpha: 0.28),
            AmbientBlob(hue: .deep, x: 10, y: 220, radius: 180, alpha: 0.35),
        ])
        XCTAssertEqual(AmbientPreset.training.baseBlobs.map(\.hue), [.lift, .strain])
        XCTAssertEqual(AmbientPreset.health.baseBlobs.map(\.hue), [.recoveryHigh, .hrv, .heart])
        XCTAssertEqual(AmbientPreset.strapAway.baseBlobs.first, AmbientBlob.neutral)
    }

    func testEveryPresetIsNonEmptyAndScales() {
        for preset in AmbientPreset.all {
            let base = preset.baseBlobs
            XCTAssertFalse(base.isEmpty, "\(preset)")
            XCTAssertEqual(preset.blobs(), base, "\(preset)")
            for (s, b) in zip(preset.blobs(intensity: .subtle), base) {
                XCTAssertEqual(s.alpha, b.alpha * 0.6, accuracy: accuracy, "\(preset)")
            }
        }
    }
}
