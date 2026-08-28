import SwiftUI

/// The import surface: the starting screen, the in-progress feedback, and the recoverable error state.
/// It renders **only** the states in which no report is available — presenting a report is
/// `FeatureAnalysis`'s job, and the composition root switches between the two.
///
/// Depends on the domain and SwiftUI only: no AppKit, no `URL`, no filesystem.
///
/// ## One frame, one region
///
/// The three pre-report states are **states of one surface**, not three surfaces. The frame — everything
/// a person needs whatever is happening — is built by a single code path that no state branches around,
/// and the three differ in exactly **one** place: `statusRegion`.
///
/// That single region is this structure's whole point. The surface used to insert the failure *above*
/// the action and the progress indicator *below* it, so the two states moved different things at
/// different heights and the frame shifted underneath the reader on precisely the transitions they were
/// watching. One region, in one position, cannot do that (`design.md` §4b, option B).
///
/// **The words are not this group's.** The frame still says what it said before; the copy this surface
/// will be rebuilt from is `ImportFlowCopy`, and the group that lays out the idle state is where it
/// starts being read.
public struct ImportFlowView: View {
    private let model: ImportFlowModel

    public init(model: ImportFlowModel) {
        self.model = model
    }

    /// **One read of the flow, one value derived from it.** Reading `state` several times in one body
    /// could, in principle, straddle a change; projecting it once cannot. A flow showing a report has no
    /// pre-report presentation and this renders nothing — the composition root never asks it to, and a
    /// surface that invented a starting screen over a finished inspection would be worse than an empty
    /// one.
    public var body: some View {
        if let presentation = PreInspectionPresentation(model.state) {
            shell(presentation)
        }
    }

    /// The frame every pre-report state shares, and the one region in which they differ.
    private func shell(_ presentation: PreInspectionPresentation) -> some View {
        VStack(spacing: 12) {
            Text("Audio Inspector")
                .font(.title2)
            Text("Choose a local audio file — or drag one onto this window — to inspect its technical properties. The file is only read, never modified, moved or copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(presentation.hasFailed ? "Try again" : "Choose audio file…") {
                Task { await model.selectAndInspect() }
            }
            .disabled(presentation.isInspecting)

            statusRegion(presentation)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// **The one place the three states differ.**
    ///
    /// Total, with no default: a case added to the presentation has to be answered here rather than
    /// falling through to nothing, which is the failure a `default` would hide — a state that reaches the
    /// surface and says nothing at all.
    ///
    /// Idle occupies it with nothing. The region is not reserved: an empty `VStack` member contributes
    /// no height and no spacing, so the idle frame is exactly the frame it was.
    @ViewBuilder
    private func statusRegion(_ presentation: PreInspectionPresentation) -> some View {
        switch presentation {
        case .idle:
            EmptyView()
        case .working:
            ProgressView()
                .controlSize(.small)
        case let .failed(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}
