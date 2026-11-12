import SwiftUI
import StrandDesign

// Stage 5 (events layer), specification §10.6, frames N1 to N13 of `design/round-s5-events/`. The
// note directly under the scorecard's verdict: the events of the judged week, then those of the
// earlier weeks the verdict looked back over, and a footnote that events do not change the verdict.
// It draws `CutScorecardPresentation.eventNote` and reads no store. The whole note opens the Events
// screen. With no note it draws nothing and takes no space.

struct ScorecardEventNoteView: View {
    let presentation: CutScorecardPresentation

    var body: some View {
        if let note = presentation.eventNote {
            card(note)
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.m)
        }
    }

    private func card(_ note: CutScorecardPresentation.EventNote) -> some View {
        NavigationLink {
            PersonalEventsView()
        } label: {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    if !note.lines.isEmpty {
                        heading(note.title, chevron: true)
                        lines(note.lines)
                    }
                    if let earlier = note.earlierTitle {
                        heading(earlier, chevron: note.lines.isEmpty)
                            .padding(.top, note.lines.isEmpty ? 0 : NoopTheme.Layout.s)
                        lines(note.earlierLines)
                    }
                    if let more = note.moreText {
                        Text(verbatim: more)
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: note.footnote)
                        .noopFont(.caption, color: false)
                        .foregroundStyle(NoopTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.noopPress)
        .accessibilityElement(children: .combine)
    }

    private func heading(_ text: String, chevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
            Text(verbatim: text)
                .noopFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if chevron { FormKitChevron() }
        }
    }

    private func lines(_ lines: [String]) -> some View {
        ForEach(lines, id: \.self) { line in
            Text(verbatim: line)
                .noopFont(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
