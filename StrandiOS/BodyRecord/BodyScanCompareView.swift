import SwiftUI
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10.4, frames J1 to J11 of
// `design/round-s4-body-record/`: two scans side by side, the older on the left whatever is chosen.
// Each row is the field name, then the earlier value, the later value and the change; at the
// largest text sizes the three are stacked. The screen draws `BodyScanComparison` and decides nothing.

/// The comparison, pushed with the two chosen scan ids; nil ids mean the two newest.
struct BodyScanCompareView: View {
    let earlierId: String?
    let laterId: String?

    var body: some View {
        BodyRecordGate {
            BodyRecordContextReader {
                BodyScanCompareScreen(context: $0, earlierId: earlierId, laterId: laterId)
            }
        }
    }
}

struct BodyScanCompareScreen: View {
    private let context: BodyRecordContext
    @StateObject private var model: BodyRecordModel
    @EnvironmentObject private var repo: Repository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var earlierId: String?
    @State private var laterId: String?
    @State private var addingScan = false
    @ScaledMetric(relativeTo: .body) private var column = BodyRecordLayout.compareColumn

    init(context: BodyRecordContext, earlierId: String?, laterId: String?, model: BodyRecordModel? = nil) {
        self.context = context
        _earlierId = State(initialValue: earlierId)
        _laterId = State(initialValue: laterId)
        _model = StateObject(wrappedValue: model ?? context.model())
    }

    private var comparison: BodyScanComparison { model.comparison(earlierId: earlierId, laterId: laterId) }
    private var stacks: Bool {
        BodyRecordPresenter.comparisonUsesStackedRows(accessibilityTextSize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        let shown = comparison
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                if let empty = shown.emptyText {
                    NoopGlassCard { BodyRecordNote(text: empty) }.padding(.top, NoopTheme.Layout.l)
                    if let add = shown.addScanTitle { BodyRecordButton(title: add) { addingScan = true } }
                } else {
                    if let one = shown.oneScanText {
                        NoopGlassCard { BodyRecordNote(text: one) }.padding(.top, NoopTheme.Layout.l)
                    } else {
                        choosers(shown)
                    }
                    table(shown.rows, oneScan: shown.oneScanText != nil)
                    if !shown.derivedRows.isEmpty { table(shown.derivedRows, oneScan: shown.oneScanText != nil) }
                    ForEach(shown.notes, id: \.self) { BodyRecordNote(text: $0) }
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: BodyRecordPresenter.compareScansTitle))
        .task(id: repo.refreshSeq) { await model.load() }
        .sheet(isPresented: $addingScan, onDismiss: { Task { await model.load() } }) {
            BodyScanSheetScreen(context: context, editing: nil)
        }
    }

    /// J8: each menu offers every scan except the one chosen in the other.
    private func choosers(_ shown: BodyScanComparison) -> some View {
        HStack(spacing: NoopTheme.Layout.s) {
            chooser(BodyRecordPresenter.earlierTitle, choices: shown.earlierChoices, selected: shown.earlierScanId) {
                earlierId = $0
                laterId = shown.laterScanId
            }
            chooser(BodyRecordPresenter.laterTitle, choices: shown.laterChoices, selected: shown.laterScanId) {
                laterId = $0
                earlierId = shown.earlierScanId
            }
        }
        .padding(.top, NoopTheme.Layout.l)
    }

    private func chooser(_ title: String, choices: [BodyScanChoice], selected: String?,
                         choose: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(choices, id: \.scanId) { choice in
                Button { choose(choice.scanId) } label: { Text(verbatim: choice.dateText) }
            }
        } label: {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: title).noopFont(.caption)
                Text(verbatim: choices.first { $0.scanId == selected }?.dateText ?? "")
                    .noopFont(.rowTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NoopTheme.Layout.m)
            .background(NoopTheme.card, in: RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius,
                                                             style: .continuous))
        }
    }

    private func table(_ rows: [BodyScanComparisonRow], oneScan: Bool) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                if !stacks, !oneScan { columnTitles }
                ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                    if index > 0 { Divider().overlay(NoopTheme.separator) }
                    rowView(row, oneScan: oneScan)
                }
            }
        }
    }

    private var columnTitles: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            Spacer(minLength: 0)
            Text(verbatim: BodyRecordPresenter.earlierTitle).noopFont(.caption).frame(width: column, alignment: .trailing)
            Text(verbatim: BodyRecordPresenter.laterTitle).noopFont(.caption).frame(width: column, alignment: .trailing)
            Text(verbatim: BodyRecordPresenter.changeTitle).noopFont(.caption).frame(width: column, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowView(_ row: BodyScanComparisonRow, oneScan: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.label).noopFont(.bodySmall)
                Spacer(minLength: NoopTheme.Layout.s)
                if oneScan { BodyRecordValue(text: row.earlierText, unit: row.unit) }
            }
            if !oneScan {
                if stacks {
                    BodyRecordLabelledLine(label: BodyRecordPresenter.earlierTitle, value: row.earlierText)
                    BodyRecordLabelledLine(label: BodyRecordPresenter.laterTitle, value: row.laterText)
                    if let change = row.changeText {
                        BodyRecordLabelledLine(label: BodyRecordPresenter.changeTitle, value: change)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                        Text(verbatim: row.unit).noopFont(.unit)
                        Spacer(minLength: 0)
                        cell(row.earlierText)
                        cell(row.laterText)
                        cell(row.changeText ?? "")
                    }
                }
                HStack(spacing: NoopTheme.Layout.s) {
                    if let direction = row.directionText { Text(verbatim: direction).noopFont(.caption) }
                    if let percent = row.percentText { Text(verbatim: percent).noopFont(.caption) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cell(_ text: String) -> some View {
        Text(verbatim: text)
            .noopFont(.footnote, color: false)
            .monospacedDigit()
            .foregroundStyle(NoopTheme.textPrimary)
            .multilineTextAlignment(.trailing)
            .frame(width: column, alignment: .trailing)
    }
}
