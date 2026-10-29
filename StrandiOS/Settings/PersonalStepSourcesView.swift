#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Separate source readings and a local, held-out check of the existing strap estimate.
/// Trial results never change calibration, Health records, or the dashboard's measured total.
struct PersonalStepSourcesView: View {
    let day: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("noop.stepWalkValidationTrials.v1") private var savedTrials = ""
    @State private var healthSteps: Int?
    @State private var strapSteps: Int?
    @State private var selectedSource: String?
    @State private var trialSource: String?
    @State private var countedSteps = ""
    @State private var result: StepWalkValidation.Result?
    @State private var busy = false
    @State private var readFailed = false
    @State private var showCalibration = false
    @State private var loadRequest = UUID()
    @State private var analysisRequest = UUID()

    private var trials: [StepWalkValidation.Trial] {
        guard let data = savedTrials.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StepWalkValidation.Trial].self, from: data)) ?? []
    }
    private var activeTrial: StepWalkValidation.Trial? { trials.first { $0.endedAt == nil } }
    private var completedTrial: StepWalkValidation.Trial? { trials.first { $0.endedAt != nil } }
    private var displayedResult: StepWalkValidation.Result? {
        guard let result, result.trialId == completedTrial?.id else { return nil }
        return result
    }
    private var coefficient: Double {
        profile.stepsManualCoefficient > 0 ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                    Text(verbatim: day).noopFont(.footnote)
                    NoopGlassCard {
                        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                            metric("Apple Health", value: healthSteps.map { $0.formatted() })
                            metric("Strap estimate", value: strapSteps.map { "~" + $0.formatted() })
                            Text("These are separate readings. They are not added together. Health steps can miss walks without your phone; the strap estimate is not yet validated for accuracy.")
                                .noopFont(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                            if let descriptor = MetricCatalog.metric(key: "steps", source: Repository.appleHealthSource) {
                                NavigationLink("Apple Health history") { MetricDetailView(metric: descriptor) }
                            }
                            if selectedSource != nil,
                               let descriptor = MetricCatalog.metric(key: "steps_est", source: Repository.whoopSource) {
                                NavigationLink("Strap estimate history") { MetricDetailView(metric: descriptor) }
                            }
                            Button("Calibration") { showCalibration = true }
                        }
                    }
                    walkCheck
                    if readFailed {
                        Text("Could not read strap motion. Let sync finish, then try again.")
                            .noopFont(.footnote)
                            .foregroundStyle(NoopTheme.strain)
                    }
                }
                .padding(NoopTheme.Layout.gutter)
            }
            .background(NoopTheme.canvas)
            .navigationTitle("Step sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(repo.refreshSeq)-\(repo.deviceId)-\(savedTrials)") { await load() }
            .sheet(isPresented: $showCalibration) {
                StepsCalibrationSheet(repo: repo) { showCalibration = false }
            }
        }
    }

    private var walkCheck: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                Text("Phone-free walk check").noopFont(.rowTitle)
                Text("Start here, leave your phone behind, and count 500–1,000 steps while wearing the strap. Return and finish the check, then let the strap sync.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if let active = activeTrial {
                    Text(active.startedAt, style: .time).noopFont(.bodySmall)
                    TextField("Steps you counted", text: $countedSteps)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Steps you counted")
                    Button("Finish walk") { finish(active) }
                        .disabled(busy || Int(countedSteps).map { !StepWalkValidation.countedStepRange.contains($0) } != false)
                    Button("Cancel", role: .cancel) { save(trials.filter { $0.id != active.id }) }
                } else {
                    Button("Start walk") { start() }
                        .disabled(busy || trialSource == nil || !coefficient.isFinite || coefficient <= 0)
                    if trialSource == nil {
                        Text("A paired WHOOP 4.0 is required for this check.").noopFont(.footnote)
                    } else if coefficient <= 0 {
                        Text("Calibrate the strap estimate before starting a walk check.").noopFont(.footnote)
                    }
                }
                if let trial = completedTrial {
                    Divider().overlay(NoopTheme.separator)
                    Text(trial.startedAt, format: .dateTime.month().day().hour().minute()).noopFont(.footnote)
                    metric("Steps you counted", value: trial.countedSteps.map { $0.formatted() })
                    metric("Strap estimate", value: displayedResult?.estimatedSteps.map { "~" + $0.formatted() })
                    if let error = displayedResult?.absoluteErrorPercent {
                        metric("Absolute error", value: error.formatted(.number.precision(.fractionLength(1))) + "%")
                    }
                    Text(verdictText).noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    if let diagnostics = displayedResult?.diagnostics {
                        metric("Motion samples", value: diagnostics.usableMotionSampleCount.formatted())
                        metric("Largest recording gap", value: diagnostics.maximumGapSeconds.map { $0.formatted() + " s" })
                        metric("Start gap", value: diagnostics.startGapSeconds.map { $0.formatted() + " s" })
                        metric("End gap", value: diagnostics.endGapSeconds.map { $0.formatted() + " s" })
                    }
                    Button("Check synced motion") { Task { await analyze(trial) } }.disabled(busy)
                }
                Text("This check uses the calibration saved at its start and requires motion samples across the walk with no gap over five seconds. A passing result applies only to this walk.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if busy { ProgressView() }
            }
        }
    }

    private var verdictText: String {
        switch displayedResult?.verdict {
        case nil: return String(localized: "Check synced motion")
        case .pass: return String(localized: "Within 10% for this walk")
        case .fail: return String(localized: "Over 10% error for this walk")
        default:
            let reasons = displayedResult?.incompleteReasons ?? []
            if reasons.contains(.invalidMotionSamples) || reasons.contains(.conflictingTimestamps)
                || reasons.contains(.nonFiniteMotion) {
                return String(localized: "This check cannot be scored from the recorded data.")
            }
            if reasons.contains(.insufficientMotion), !reasons.contains(.insufficientMotionSamples) {
                return String(localized: "Recorded motion cannot produce a step estimate for this walk.")
            }
            return String(localized: "Incomplete motion coverage. Let the strap sync and check again.")
        }
    }

    private func metric(_ label: LocalizedStringKey, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.m) {
            Text(label).noopFont(.bodySmall)
            Spacer(minLength: NoopTheme.Layout.m)
            Text(verbatim: value ?? "—").noopFont(.bodySmall)
        }
    }

    private func save(_ values: [StepWalkValidation.Trial]) {
        guard let data = try? JSONEncoder().encode(Array(values.prefix(10))),
              let text = String(data: data, encoding: .utf8) else { return }
        savedTrials = text
    }

    private func start() {
        guard let source = trialSource, coefficient.isFinite, coefficient > 0 else { return }
        do {
            let calibration = try StepWalkValidation.CalibrationSnapshot(
                coefficient: coefficient, sampleDays: profile.stepsCalibrationSampleDays,
                confidence: profile.stepsCalibrationConfidence, manual: profile.stepsManualCoefficient > 0)
            let trial = try StepWalkValidation.Trial(sourceDeviceId: source, startedAt: Date(), calibration: calibration)
            save([trial] + trials.filter { $0.endedAt != nil })
            countedSteps = ""
            result = nil
        } catch { readFailed = true }
    }

    private func finish(_ trial: StepWalkValidation.Trial) {
        guard let count = Int(countedSteps),
              let finished = try? trial.completed(endedAt: Date(), countedSteps: count) else { return }
        result = nil
        save([finished] + trials.filter { $0.id != trial.id })
        Task { await analyze(finished) }
    }

    @MainActor
    private func load() async {
        let request = UUID()
        loadRequest = request
        healthSteps = nil; strapSteps = nil; selectedSource = nil; trialSource = nil
        let requestSource = repo.deviceId
        let devices = model.deviceRegistry?.devices ?? []
        let activeId = model.deviceRegistry?.activeDeviceId ?? requestSource
        let pairedSource = devices.first(where: {
            $0.id == requestSource && DeviceFamily.confirmedRegistryFamily(model: $0.model, brand: $0.brand) == .whoop4
        })?.id
        guard let store = await repo.storeHandle() else {
            guard !Task.isCancelled, loadRequest == request else { return }
            result = nil; readFailed = true; return
        }
        do {
            let rows = try await store.appleDaily(deviceId: Repository.appleHealthSource, from: day, to: day)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: day),
                  let end = Calendar.current.date(byAdding: .day, value: 1, to: date) else { return }
            let owner = await IntelligenceEngine.resolveDayOwner(
                day: day, from: Int(date.timeIntervalSince1970), to: Int(end.timeIntervalSince1970) - 1,
                store: store, devices: devices, activeId: activeId,
                registry: DeviceRegistryStore(dbQueue: store.registryWriter), fallbackDeviceId: requestSource)
            let ownerSource = devices.first(where: {
                $0.id == owner && DeviceFamily.confirmedRegistryFamily(model: $0.model, brand: $0.brand) == .whoop4
            })?.id
            let estimated: Int?
            if let ownerSource {
                estimated = try await store.metricSeries(deviceId: ownerSource + "-noop", key: "steps_est", from: day, to: day)
                    .first.flatMap { $0.value.isFinite && $0.value >= 0 && $0.value < Double(Int.max) ? Int($0.value.rounded()) : nil }
            } else { estimated = nil }
            guard !Task.isCancelled, loadRequest == request, requestSource == repo.deviceId else { return }
            healthSteps = rows.first?.steps
            strapSteps = estimated
            selectedSource = ownerSource
            trialSource = pairedSource
            readFailed = false
            if let trial = completedTrial { await analyze(trial) }
        } catch {
            guard !Task.isCancelled, loadRequest == request, requestSource == repo.deviceId else { return }
            healthSteps = nil; strapSteps = nil; selectedSource = nil; result = nil; readFailed = true
        }
    }

    @MainActor
    private func analyze(_ trial: StepWalkValidation.Trial) async {
        let request = UUID()
        analysisRequest = request
        guard let bounds = trial.motionQueryBounds else { result = nil; return }
        busy = true
        defer { if analysisRequest == request { busy = false } }
        guard let store = await repo.storeHandle() else {
            guard !Task.isCancelled, analysisRequest == request, completedTrial?.id == trial.id else { return }
            result = nil; readFailed = true; return
        }
        do {
            let samples = try await store.gravitySamples(
                deviceId: trial.sourceDeviceId, from: bounds.lowerBound,
                to: bounds.upperBound, limit: 200_000)
            // This is an explicit continuity check, not an assertion of the sensor's sampling rate.
            let policy = try StepWalkValidation.CoveragePolicy(maximumGapSeconds: 5, maximumBoundaryGapSeconds: 5)
            let analyzed = StepWalkValidation.analyze(trial: trial, gravity: samples, coveragePolicy: policy)
            guard !Task.isCancelled, analysisRequest == request, completedTrial?.id == trial.id else { return }
            result = analyzed
            readFailed = false
        } catch {
            guard !Task.isCancelled, analysisRequest == request, completedTrial?.id == trial.id else { return }
            result = nil; readFailed = true
        }
    }
}
#endif
