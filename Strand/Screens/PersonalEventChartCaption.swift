import SwiftUI
import StrandDesign

/// The text under a chart that names its event dots (stage 5 specification §10.5): one line per
/// event, then "and n more". Nil draws nothing and takes no height. Lines wrap at large text sizes;
/// nothing truncates a date. Shared with macOS; it decides nothing and reads no store.
struct PersonalEventChartCaption: View {
    let caption: PersonalEventCaption?

    init(_ caption: PersonalEventCaption?) {
        self.caption = caption
    }

    var body: some View {
        if let caption {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                ForEach(caption.lines, id: \.self) { line in
                    Text(verbatim: line)
                        .noopFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let more = caption.moreText {
                    Text(verbatim: more)
                        .noopFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The chart's own spoken value already ends with these lines (the marks' text), so the
            // caption is not read a second time.
            .accessibilityHidden(true)
        }
    }
}
