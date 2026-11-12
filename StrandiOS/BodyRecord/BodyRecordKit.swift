import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10: the pieces the body-record
// screens share. Presentation only: every word and figure comes from `BodyRecordPresenter` through
// the models in Strand/Data/BodyRecordModel.swift; nothing here formats a number, a date or a sentence.

/// Geometry of `design/round-s4-body-record/` that has no `NoopTheme` token.
enum BodyRecordLayout {
    /// The skeleton blocks of frame G1.
    static let skeletonHeight: CGFloat = 64
    static let skeletonOpacity: Double = 0.6
    /// The comparison's value columns at the default text size.
    static let compareColumn: CGFloat = 84
    /// A sheet's controls while a save is in flight.
    static let busyOpacity: Double = 0.4
}

// MARK: - Wiring

/// What the body-record screens read and write through. The app's is built from the repository and
/// the profile; the debug demo supplies its own through the environment.
@MainActor
struct BodyRecordContext {
    let store: BodyRecordStore
    let weighIns: WeighInStore
    let unitSystem: () -> UnitSystem
    let locale: () -> Locale
    let now: () -> Date
    let timeZone: () -> TimeZone

    static func live(repository: Repository, profile: ProfileStore) -> BodyRecordContext {
        let provider = BodyMeasurementProvider.live(repository: repository, profile: profile)
        return BodyRecordContext(
            store: BodyRecordStore(repository: repository, provider: provider),
            weighIns: WeighInStore(repository: repository, provider: provider),
            unitSystem: {
                UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
            },
            locale: { AppClock.formattingLocale },
            now: { Date() },
            timeZone: { TimeZone.current })
    }

    /// The local day the clock is on.
    var today: String { LocalDayWindows(timeZone: timeZone()).dayKey(for: now()) }

    /// The device's decimal separator, "." when the locale has none.
    var decimalSeparator: Character { Character(Locale.current.decimalSeparator ?? ".") }

    func model() -> BodyRecordModel {
        BodyRecordModel(store: store, unitSystem: unitSystem, locale: locale)
    }

    func sheetModel(editing: BodyScan?) -> BodyScanSheetModel {
        let now = now
        let zone = timeZone
        return BodyScanSheetModel(store: store, weighIns: weighIns, editing: editing, unitSystem: unitSystem(),
                                  decimalSeparator: decimalSeparator,
                                  today: { LocalDayWindows(timeZone: zone()).dayKey(for: now()) })
    }

    func benchmarkModel(key: String?) -> BenchmarkSheetModel {
        BenchmarkSheetModel(store: store, key: key, decimalSeparator: decimalSeparator, now: now())
    }
}

private struct BodyRecordContextKey: EnvironmentKey {
    static let defaultValue: BodyRecordContext? = nil
}

extension EnvironmentValues {
    /// Set only by the debug demo, so that pushed screens and sheets read its synthetic store.
    var bodyRecordContextOverride: BodyRecordContext? {
        get { self[BodyRecordContextKey.self] }
        set { self[BodyRecordContextKey.self] = newValue }
    }
}

/// Resolves the context a body-record screen runs on and hands it to `content`.
struct BodyRecordContextReader<Content: View>: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.bodyRecordContextOverride) private var override
    @ViewBuilder let content: (BodyRecordContext) -> Content

    var body: some View {
        content(override ?? BodyRecordContext.live(repository: repo, profile: profile))
    }
}

/// Every pushed body-record screen exists only while the flag is on: when it goes off the screen
/// leaves the stack and nothing is deleted.
struct BodyRecordGate<Content: View>: View {
    @ObservedObject private var flag = BodyRecordSettings.enabledFlag
    @Environment(\.bodyRecordContextOverride) private var override
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: () -> Content

    /// The demo shows its frames whatever the simulator's own switch says.
    private var reachable: Bool { flag.isEnabled || override != nil }

    var body: some View {
        Group {
            if reachable { content() } else { NoopTheme.canvas.ignoresSafeArea() }
        }
        .onChangeCompat(of: reachable) { if !$0 { dismiss() } }
        .onAppear { if !reachable { dismiss() } }
    }
}

// MARK: - Health row

/// The Health tab's way into the body record (§10.1): "Body record" with the date of the last scan.
/// Mounted only while the flag is on.
struct BodyRecordHealthRowView: View {
    let showsDivider: Bool
    @EnvironmentObject private var repo: Repository

    var body: some View {
        BodyRecordContextReader { HealthRowContent(context: $0, showsDivider: showsDivider,
                                                   refreshSequence: repo.refreshSeq) }
    }

    private struct HealthRowContent: View {
        let context: BodyRecordContext
        let showsDivider: Bool
        let refreshSequence: Int
        @State private var row: BodyRecordHealthRow?

        var body: some View {
            NavigationLink(value: RedesignRoute.bodyRecord) {
                NoopListRow(LocalizedStringKey(BodyRecordPresenter.title), systemImage: "figure.stand",
                            color: NoopTheme.textPrimary, detail: row?.detail, showsDivider: showsDivider)
            }
            .task(id: refreshSequence) {
                let scans = await context.store.scans()
                row = BodyRecordPresenter.healthRow(enabled: true, scans: scans, locale: context.locale())
            }
        }
    }
}

// MARK: - Shared pieces

/// One figure: label on the left, the number and its unit on the right, and an optional caption.
struct BodyRecordFigureRow: View {
    let figure: BodyScanFigure
    var showsDivider = true

    var body: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            if showsDivider { Divider().overlay(NoopTheme.separator) }
            HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                Text(verbatim: figure.label)
                    .noopFont(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NoopTheme.Layout.s)
                BodyRecordValue(text: figure.valueText, unit: figure.unit)
            }
            if let caption = figure.caption {
                BodyRecordNote(text: caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A number with its unit beside it, in the primary text colour.
struct BodyRecordValue: View {
    let text: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
            Text(verbatim: text)
                .noopFont(.rowNumber, color: false)
                .monospacedDigit()
                .foregroundStyle(NoopTheme.textPrimary)
            if !unit.isEmpty {
                Text(verbatim: unit)
                    .noopFont(.unit, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
            }
        }
    }
}

/// A neutral sentence under a figure or a card.
struct BodyRecordNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .noopFont(.footnote, color: false)
            .foregroundStyle(NoopTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A label and its value on one line, e.g. "Since the previous reading" and "+15 s".
struct BodyRecordLabelledLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
            Text(verbatim: label).noopFont(.footnote)
            Spacer(minLength: NoopTheme.Layout.s)
            Text(verbatim: value)
                .noopFont(.footnote, color: false)
                .monospacedDigit()
                .foregroundStyle(NoopTheme.textPrimary)
        }
    }
}

/// A full-width button in the body-record cards.
struct BodyRecordButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .noopFont(.button, color: false)
                .foregroundStyle(NoopTheme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.noopPress)
    }
}

/// The section title used on every body-record screen, from a presenter string.
struct BodyRecordSectionTitle: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .noopFont(.sectionTitle)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NoopTheme.Layout.sectionTop)
            .padding(.bottom, NoopTheme.Layout.sectionBottom)
    }
}
