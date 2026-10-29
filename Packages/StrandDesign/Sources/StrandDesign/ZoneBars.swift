import SwiftUI

// MARK: - ZoneBars (redesign §3.6 item 6)
//
// Time in heart-rate zones: one row per zone, Zone 5 at the top down to Zone 1 (the round 3 workout detail
// order), each a capsule in its zone colour over a track, with a caller-supplied trailing label ("13 min",
// "42%"). Zone names come from the caller so the app localises them; this view holds no copy of its own.

public struct ZoneBars: View {

    /// How a row's bar width is derived from its value.
    public enum Scale: Sendable {
        /// Share of the total across all zones (a 30 % bar is 30 % of the time).
        case total
        /// Relative to the largest zone, which fills the track.
        case largest
    }

    /// One zone row.
    public struct Row: Identifiable, Sendable {
        /// 1…5; values outside clamp to the nearest zone for the colour.
        public var zone: Int
        public var name: String
        /// Time (or any weight) in the zone. Nil or negative counts as nothing in the zone.
        public var value: Double?
        public var trailing: String

        public var id: Int { zone }

        public init(zone: Int, name: String, value: Double?, trailing: String) {
            self.zone = zone
            self.name = name
            self.value = value
            self.trailing = trailing
        }
    }

    public var rows: [Row]
    public var scale: Scale
    /// False renders the final state immediately (widgets, snapshots, already-seen content).
    public var animates: Bool

    /// Rows in the order given (pass Zone 5 first to match the mockups).
    public init(rows: [Row], scale: Scale = .total, animates: Bool = true) {
        self.rows = rows
        self.scale = scale
        self.animates = animates
        _grown = State(initialValue: !animates)
    }

    /// Five rows from parallel arrays indexed by zone (index 0 = Zone 1), drawn Zone 5 first.
    /// Arrays shorter than five leave the missing zones with no name, no value and no label.
    public init(
        names: [String],
        values: [Double?],
        trailingLabels: [String],
        scale: Scale = .total,
        animates: Bool = true
    ) {
        let rows = (1...5).reversed().map { zone -> Row in
            let i = zone - 1
            return Row(
                zone: zone,
                name: i < names.count ? names[i] : "",
                value: i < values.count ? values[i] : nil,
                trailing: i < trailingLabels.count ? trailingLabels[i] : ""
            )
        }
        self.init(rows: rows, scale: scale, animates: animates)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: Bool

    // MARK: - Pure geometry

    /// Bar widths as fractions 0…1 of the track, in input order. Nil, negative and non-finite values count as
    /// zero. If nothing is positive every fraction is 0 (never NaN), so an empty workout draws bare tracks.
    public static func fractions(_ values: [Double?], scale: Scale = .total) -> [Double] {
        let clean = values.map { v -> Double in
            guard let v, v.isFinite, v > 0 else { return 0 }
            return v
        }
        let denominator: Double
        switch scale {
        case .total: denominator = clean.reduce(0, +)
        case .largest: denominator = clean.max() ?? 0
        }
        guard denominator > 0, denominator.isFinite else { return clean.map { _ in 0 } }
        return clean.map { min($0 / denominator, 1) }
    }

    // MARK: - Body

    private static let barHeight: CGFloat = 10
    private static let nameWidth: CGFloat = 28
    private static let trailingWidth: CGFloat = 56

    public var body: some View {
        let widths = Self.fractions(rows.map(\.value), scale: scale)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                let zoneColor = NoopTheme.zoneColor(row.zone)
                HStack(spacing: NoopTheme.Layout.s) {
                    Text(row.name)
                        .noopFont(.pill, color: false)
                        .foregroundStyle(zoneColor)
                        .lineLimit(1)
                        .frame(minWidth: Self.nameWidth, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NoopTheme.track)
                            Capsule()
                                .fill(zoneColor)
                                .frame(width: geo.size.width * CGFloat(widths[i]))
                                .scaleEffect(x: grown || reduceMotion ? 1 : 0, y: 1, anchor: .leading)
                                .opacity(grown || !reduceMotion ? 1 : 0)
                                .animation(barAnimation(index: i), value: grown)
                        }
                    }
                    .frame(height: Self.barHeight)
                    Text(row.trailing)
                        .noopFont(.footnote)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(minWidth: Self.trailingWidth, alignment: .trailing)
                }
                .padding(.vertical, NoopTheme.Layout.s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(row.name))
                .accessibilityValue(Text(row.trailing))
            }
        }
        .animation(NoopTheme.Motion.resolved(NoopTheme.Motion.bar, reduceMotion: reduceMotion), value: widths)
        .onAppear { if animates { grown = true } }
    }

    /// Bars grow from the leading edge on the bar spring, staggered top to bottom; Reduce Motion fades.
    private func barAnimation(index: Int) -> Animation {
        reduceMotion
            ? NoopTheme.Motion.reduced
            : NoopTheme.Motion.bar.delay(Double(index) * NoopTheme.Motion.barStagger)
    }
}

#if DEBUG
#Preview("ZoneBars") {
    VStack(spacing: 24) {
        ZoneBars(
            names: ["Z1", "Z2", "Z3", "Z4", "Z5"],
            values: [60, 240, 600, 780, 180],
            trailingLabels: ["1 min", "4 min", "10 min", "13 min", "3 min"]
        )
        // No time in any zone: bare tracks, no NaN widths.
        ZoneBars(
            names: ["Z1", "Z2", "Z3", "Z4", "Z5"],
            values: [nil, nil, nil, nil, nil],
            trailingLabels: ["–", "–", "–", "–", "–"],
            scale: .largest
        )
    }
    .padding(18)
    .frame(width: 370)
    .background(NoopTheme.cardSolid)
    .preferredColorScheme(.dark)
}
#endif
