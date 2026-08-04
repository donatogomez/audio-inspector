/// Why a drop could not be turned into an inspection, expressed in the vocabulary of the import
/// surface. It carries **no `URL`, no AppKit type and no filesystem type** — the composition root
/// decides that a payload is unusable and reports only the reason (ADR-0010, ADR-0014).
///
/// A rejection is **not** an inspection failure: it never becomes `ImportFlowModel.State.failed`,
/// because a user who accidentally drops two files must not lose the report already on screen. It
/// travels on a channel orthogonal to the flow state.
///
/// Only cases with a real producer exist; each maps to exactly one check in the drop handler.
public enum DropRejection: Equatable, Sendable, CaseIterable {
    /// More than one item was dropped. The first is never taken silently: choosing one of several
    /// would be a selection the user did not make.
    case multipleItems
    /// The payload could not be turned into a single inspectable local file — nothing usable, a
    /// non-local item, a folder, or something the system positively types as non-audio.
    case unsupportedItem
    /// An inspection is already running, so the drop starts nothing.
    case inspectionInProgress

    /// The presentable text. Centralised here so the wording exists in exactly one place and never
    /// leaks a path, a URL or a framework error.
    public var message: String {
        switch self {
        case .multipleItems: "Drop one file at a time."
        case .unsupportedItem: "That item cannot be inspected."
        case .inspectionInProgress: "Wait for the current inspection to finish."
        }
    }
}
