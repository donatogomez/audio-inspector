import AudioInspectorDomain
import SwiftUI

/// **Waveform — the file's amplitude over time, given room.**
///
/// The first section whose content is a *drawing*, so the first that needs space rather than order.
/// ADR-0026 §9 says exactly what that space buys and what it does not: *"A section gives each drawing
/// room. It gives it nothing else."*
///
/// ## It gives a drawing room; it draws nothing new
///
/// The envelope, its buckets, the amplitude scale, the shared time axis and every sentence are the ones
/// production already produces. Nothing below reads a file, decodes one, runs an accumulator, recomputes
/// an envelope or retains a sample — the section is handed what the inspection already made.
///
/// ## Which drawing, decided once
///
/// It takes `ReportVisuals` — the **same value** the transitional report page is handed, built by the
/// same call in the same body — and asks it for `waveformSections`. So the workspace and that page can
/// never disagree about whether this is one file or two, and the pair still stands **in place of** the
/// single drawing rather than beside it (`audio-two-file-visual-presentation`).
///
/// It reads the comparison for that one question and no other. There is no comparison surface here, no
/// second lifecycle and no aggregate: R8 owns all three.
///
/// ## What room does not buy
///
/// No playback, playhead, zoom, pan, scrubbing, cursor, selection, loop, transport, hover readout,
/// interactive timestamp, alignment, overlay, difference drawing, correlation, similarity,
/// normalisation, gain matching or export. The drawing keeps `allowsHitTesting(false)`; a bigger still
/// drawing is still a still drawing.
public struct ReportWaveformView: View {
    private let sections: [ReportVisualSection]

    public init(visuals: ReportVisuals) {
        sections = visuals.waveformSections
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // **Exactly one**, whichever mode this is — `ReportVisuals`' own guarantee, kept as a
            // collection so *how many* stays something a test can read rather than a property of a
            // rendering nobody can assert.
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                switch section {
                case let .singleWaveform(presentation):
                    SingleWaveformWorkspace(presentation: presentation)
                case let .pairedWaveform(presentation):
                    PairedWaveformSection(presentation: presentation, sizing: .workspaceLane)
                case .singleSpectrogram, .pairedSpectrogram:
                    // Not reachable through `waveformSections`, and named rather than defaulted so a new
                    // kind of section fails to compile here instead of vanishing. The spectral drawings
                    // are R6's section, not this one's.
                    EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}

/// One file's envelope, filling the section.
///
/// The single-file section's own words, and its own drawing — put together here rather than reused from
/// `WaveformSection` for one reason: that type bakes in the report page's fixed strip, and the whole
/// point of this section is that the drawing is not a strip. Every string is still `WaveformCopy`'s.
///
/// **No `ScrollView`.** A flexible height inside one collapses to the content's ideal, which is the
/// opposite of what a workspace is for. The drawing is the part that yields when the prose needs room,
/// which is the right priority when the prose is what carries the meaning.
private struct SingleWaveformWorkspace: View {
    let presentation: WaveformPresentation

    var body: some View {
        let text = WaveformCopy.text(for: presentation)
        return VStack(alignment: .leading, spacing: 8) {
            if case let .envelope(envelope) = presentation, !envelope.buckets.isEmpty {
                WaveformDrawing(envelope: envelope, sizing: .workspaceSingle)
            }
            if let headline = text.headline {
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(headlineStyle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = text.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element for the whole thing, not one per bucket: a drawing cannot be read, and 2048 shapes
        // announced in sequence would be worse than silence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }

    /// The report page's own rule, unchanged: waiting and having nothing to draw are ordinary outcomes
    /// and recede; only a statement that producing the drawing did not succeed is read at full weight.
    /// Nothing is ever coloured by what the audio contains.
    private var headlineStyle: HierarchicalShapeStyle {
        switch presentation {
        case .loading, .envelope, .absent: .secondary
        case .failed: .primary
        }
    }
}
