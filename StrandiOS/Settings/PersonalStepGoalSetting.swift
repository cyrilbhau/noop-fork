#if os(iOS)
import SwiftUI
import StrandDesign

// Personal iPhone preference only; it never changes calibration or stored sensor data.
struct PersonalStepGoalSetting: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PersonalWidgetMetrics.stepGoalKey) private var goal = 0
    @State private var showStepSources = false

    private let choices = [0, 2_000, 3_000, 5_000, 7_500, 10_000, 12_500, 15_000, 20_000]

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            FormRow(label: "Daily step goal") {
                Picker("Daily step goal", selection: $goal) {
                    Text("Not set").tag(0)
                    ForEach(choices.filter { $0 > 0 }, id: \.self) { value in
                        Text(value.formatted()).font(StrandFont.bodyNumber).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Text("Used by the personal steps widget. WHOOP 4.0 steps are estimates from motion; a goal does not make them measured steps.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Step sources") { showStepSources = true }
        }
        .sheet(isPresented: $showStepSources) {
            PersonalStepSourcesView(day: Repository.localDayKey(Date()))
        }
        .onChange(of: goal) { _, _ in
            Task { await WidgetSnapshot.publish(from: model) }
        }
    }
}
#endif
