/// What the surface **before a report** is showing, as one value.
///
/// The flow owns four states; three of them mean *there is nothing to present yet*, and this is those
/// three. It exists so the surface has **one** thing to switch on instead of reading `state` once for the
/// failure, once for the button's label and once for whether the button is available — three reads that
/// can, in principle, straddle a change, and three places to update when a state is added.
///
/// ## It owns no lifecycle, and holds nothing
///
/// A pure projection of `ImportFlowModel.State`, recomputed and stored nowhere. It starts no operation,
/// decides no navigation, knows nothing of the panel, of drag and drop, or of the workspace's sections.
/// **`ImportFlowModel` remains the only source of truth**, and nothing here can drift from it because
/// there is nothing here to drift.
///
/// ## `report` is not one of its cases, and that is the point
///
/// A report is not an absence of one, so the initialiser is **failable**: a flow showing a report has no
/// pre-report presentation, and says so by returning `nil` rather than by degrading into `idle`. Folding
/// it into `idle` would compile, would look harmless, and would render an empty starting screen over a
/// finished inspection — which is exactly the failure `PreInspectionPresentationTests` refuses.
enum PreInspectionPresentation: Equatable {
    /// Nothing has been chosen yet.
    case idle

    /// An inspection is under way.
    ///
    /// **It carries nothing, because nothing is known.** The state begins when the operation does — which
    /// is *before* the open panel has been answered — so there is no file to name; and the read path
    /// publishes no fraction, no unit count and no phase, so there is no progress to state.
    case working

    /// No inspection could be started at all.
    ///
    /// The message is **the flow's own**, carried through unaltered. It is an associated value rather
    /// than a constant because it belongs to the operation that failed, not to this surface's vocabulary:
    /// a copy owner restating it would give one fact two homes and let them drift apart.
    ///
    /// A file that opens but cannot be read is **not** this case — it produces a report whose status is
    /// `failed`, and the workspace presents it.
    case failed(message: String)

    /// The projection, and the only one.
    ///
    /// **Total, with no default.** A state added to the flow is a compile error here rather than a
    /// silently empty region, which is the whole reason the switch is written out rather than defaulted.
    init?(_ state: ImportFlowModel.State) {
        switch state {
        case .idle: self = .idle
        case .working: self = .working
        case let .failed(message): self = .failed(message: message)
        case .report: return nil // a report is presented by the workspace, not by this surface
        }
    }

    /// Whether an inspection is under way — the one question the surface's controls ask of this value.
    var isInspecting: Bool { self == .working }

    /// Whether no inspection could be started. A predicate about the state, not a sentence about it:
    /// what the surface *says* lives in `ImportFlowCopy` and in the flow's own message.
    var hasFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
