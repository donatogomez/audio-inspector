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
    ///
    /// **Four elements, in reading order**: what the application does, the way to begin, the second way
    /// to begin, and what it promises about the file. They are the *frame* rather than the idle state's
    /// own content, because the capability says so in both of its requirements — the purpose, the action
    /// and the drag-and-drop alternative are *"present in every one of them"*, and the read-only
    /// statement is required *"in every one of its states"* and *"SHALL NOT be conditional on any
    /// state"*. A person who has just been told an inspection failed still needs to know that their file
    /// was not touched.
    ///
    /// The sentence they replace carried three of these claims at once — purpose, dragging and the
    /// guarantee, in one line of secondary text — so none of them could be given its own weight. Nothing
    /// is dropped and nothing is added; the three claims are separated, and the heading that repeated the
    /// window's own title bar is gone.
    ///
    /// **The region sits fourth, between the alternative and the guarantee**, so the guarantee is last
    /// and the varying content never pushes it off the reader's line of sight (`design.md` §4b option B,
    /// and §5's *"quiet, last, and always present"*).
    private func shell(_ presentation: PreInspectionPresentation) -> some View {
        VStack(spacing: 12) {
            Text(ImportFlowCopy.purpose)
                .font(.title3)
                .multilineTextAlignment(.center)

            // The one action on this surface, and the only thing on it that can be invoked. Dragging is
            // an alternative stated in words, never a second control — a person using the keyboard alone
            // must be able to do everything this surface offers.
            Button(presentation.hasFailed ? "Try again" : ImportFlowCopy.chooseFile) {
                Task { await model.selectAndInspect() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(presentation.isInspecting)

            Text(ImportFlowCopy.dragAlternative)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            statusRegion(presentation)

            Text(ImportFlowCopy.readOnlyGuarantee)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
    /// no height and no spacing, so idle reads as the frame alone.
    ///
    /// **It renders none of the frame's words**, and `IdleSurfaceTests` asserts that: the four sentences
    /// belong to every state, and what belongs to one state belongs here.
    @ViewBuilder
    private func statusRegion(_ presentation: PreInspectionPresentation) -> some View {
        switch presentation {
        case .idle:
            EmptyView()
        case .working:
            // **The indicator and the sentence travel together**, because a spinner alone leaves the
            // reader to infer what is happening from an animation. What the sentence may say is settled
            // by what the flow knows, and it knows almost nothing: the state carries no file — it begins
            // before the open panel has been answered — and the read path publishes no fraction, no unit
            // count and no phase. So it names the operation and stops there. No file, no stage, no
            // figure, no estimate.
            //
            // **And no way to stop it**, because there is none to offer: `ImportFlowModel` exposes no
            // cancellation and keeps its task private. Dismissing the open panel is a different thing —
            // it ends the *selection* and the flow treats it as neutral, returning the reader where they
            // were — and a control that claimed to cancel an inspection would be naming something the
            // system cannot do.
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(ImportFlowCopy.inspecting)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .failed(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}
