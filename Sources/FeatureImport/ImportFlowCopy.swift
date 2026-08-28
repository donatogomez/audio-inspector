/// The words the surface **before a report** can render: the starting screen, the running state and the
/// recoverable failure, which are three states of one shell rather than three screens.
///
/// ## Why the words come before the layout
///
/// The same reason `PairedVisualsCopy`, `SpectrogramCopy` and `WorkspaceCopy` exist: a surface whose
/// words are literals inside a view can only be swept by reading the view. Collected here, **every
/// sentence this surface can say is a value**, so a contract can be pinned to the sentence itself and a
/// word added later has nowhere to hide.
///
/// ## What it deliberately does not own
///
/// - **The failure's own sentence.** `ImportFlowModel` supplies *"That file could not be opened for
///   inspection."* and the surface presents it. Restating it here would give one fact two homes and let
///   them drift, so nothing below duplicates it.
/// - **The drop's sentences.** *"Drop one file at a time."*, *"That item cannot be inspected."* and
///   *"Wait for the current inspection to finish."* belong to `DropRejection`; *"Drop one audio file"*
///   belongs to `DropFeedbackOverlay`. Each keeps its single home.
/// - **Any quantity.** The running state is indeterminate because production has none to report: there
///   is no fraction, no unit count and no phase anywhere in the read path. No string here states a
///   percentage, a fraction, a count, a step or a time, and `ImportFlowCopyTests` refuses one.
///
/// ## `chooseAnotherFile` is written out rather than shared, and that is the boundary's doing
///
/// `WorkspaceCopy` carries the same six words for the report workspace, and reusing them is not a choice
/// this file gets to make: `FeatureImport` depends on `AudioInspectorDomain` alone and cannot see
/// `AudioInspectorApp` (ADR-0005, and `Scripts/check-boundaries.sh` enforces it). Sharing them would
/// mean lifting a presentation string into the domain, which is a far worse trade than writing six words
/// twice. The two surfaces have different lifecycles and may diverge; nothing here assumes they will not.
///
/// ## Transitional, and only until the surface is rebuilt
///
/// **`ImportFlowView` still renders its own literals**, so these values are declared and not yet read —
/// the shape `ImportFlowModel.comparedVisuals` used when its container arrived before its consumer. The
/// slice's next group moves the rendering onto them. Until it does, a change to a sentence below must be
/// made in both places or it will not reach the screen.
enum ImportFlowCopy {

    /// What the application does, stated for this build rather than for the roadmap. It names the act
    /// and its subject, and promises nothing about what an inspection will find.
    static let purpose = "Inspect a local audio file's technical properties."

    /// The primary action, and the only one on the surface. Sentence case and a trailing ellipsis,
    /// matching the panel it opens and the house style of every other action in the app.
    static let chooseFile = "Choose audio file…"

    /// The second mechanism, stated once and beside the action rather than buried in a paragraph.
    ///
    /// It is a **statement of an alternative**, not a target: the drop destination is the whole window,
    /// in every state, and no wording here narrows it (ADR-0014).
    static let dragAlternative = "Or drag one onto this window."

    /// **The product's trust guarantee, and the reason this file exists.**
    ///
    /// It states what the system already keeps — the source is opened read-only and the only file ever
    /// written is an export destination the user picks (ADR-0010, ADR-0013). Until now it was the tail of
    /// a sentence about dragging, and no test or requirement mentioned it, so it could be deleted by an
    /// ordinary layout edit and nothing would fail.
    ///
    /// It is pinned **verbatim** by `ImportFlowCopyTests`, and it is not a promise about results,
    /// privacy or safety — only about this file.
    static let readOnlyGuarantee = "The file is only read, never modified, moved or copied."

    /// What the surface says while an inspection is running.
    ///
    /// **Objectless on purpose.** It names the operation and nothing about its subject or its extent:
    /// the running state carries no file — `ImportFlowModel.State.working` has no payload, and the state
    /// begins *before* the panel has been answered — and the read path publishes no progress. A sentence
    /// naming a file or a phase would be false for part of the state it covers.
    static let inspecting = "Inspecting…"

    /// The way out of a failure, named for what it does.
    ///
    /// **Not *Try again*.** Nothing about the failed selection is retained — no URL, no bookmark
    /// (ADR-0010, ADR-0013) — so the action opens the file chooser exactly as the idle one does. A label
    /// that says *retry* would name something the system cannot do.
    static let chooseAnotherFile = "Choose another file…"

    /// **Every string this surface can say**, collected once so the sweep covers the surface rather than
    /// the repository. A sentence added above joins it by being added here too, which is the point: this
    /// list is the surface's vocabulary, and `ImportFlowCopyTests` reads it.
    static var everyRenderableString: [String] {
        [purpose, chooseFile, dragAlternative, readOnlyGuarantee, inspecting, chooseAnotherFile]
    }
}
