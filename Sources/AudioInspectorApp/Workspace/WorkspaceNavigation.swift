import FeatureImport
import Foundation

/// What the shell needs to know about the **primary** inspection in order to decide where a reader is.
///
/// It is deliberately tiny. The alternative — watching `ImportFlowModel.State` itself — would compare
/// two whole inspections on every render, and an inspection carries an envelope and a spectral model:
/// thousands of floats compared to answer a question about a `UUID`. This carries the two facts the
/// rule actually reads and nothing else.
///
/// It is a **projection**, recomputed from the flow and stored nowhere. There is no second lifecycle
/// here: `ImportFlowModel` remains the only source of truth about the inspection, and this names none
/// of its operation numbers, tasks or guards.
enum PrimaryInspection: Equatable {
    /// Nothing is on screen to be a section *of* — the flow is idle, still working, or the file could
    /// not be opened for inspection at all.
    case none

    /// A report is on screen.
    ///
    /// `id` is `AudioFileReference.id`, minted per inspection (see `AudioFileReference`), which is what
    /// makes "a new primary inspection" distinguishable from "the same one publishing another analysis".
    /// Choosing the same file twice mints a new one, so a genuine re-inspection is a new report here.
    ///
    /// `failedGlobally` is `InspectionStatus.failed`: **still a report**, about a file the reader chose
    /// (`ImportFlowModel`'s own note says so), which is why it is a fact carried here rather than folded
    /// into `none`.
    case report(id: UUID, failedGlobally: Bool)

    /// Total, with no default: a state added to the flow has to be answered here rather than quietly
    /// arriving as `none`, which would silently make it a navigation event or silently stop being one.
    init(_ state: ImportFlowModel.State) {
        switch state {
        case .idle, .working, .failed:
            self = .none
        case let .report(presentation):
            // Total here too, and for the sharper reason: a status added to the domain must be decided
            // to be a navigation event or not, rather than defaulting into one silently.
            let failedGlobally = switch presentation.report.status {
            case .failed: true
            case .completed, .partial: false
            }
            self = .report(id: presentation.report.file.id, failedGlobally: failedGlobally)
        }
    }
}

/// Where the reader is, and the whole of what moves them (ADR-0026 §4–§5).
///
/// ## Why this is a value the composition root holds, and not a field of the flow
///
/// ADR-0018's test, one layer up: a value belongs where the thing it describes lives. A report, an
/// analysis and a comparison describe **a file**; the selected section describes **a reader**. Inside
/// `ImportFlowModel` it would sit among operation numbers, cancellation and stale guards, and the first
/// bug would be a section that moved because an analysis settled. **It takes part in no stale guard**:
/// operation numbers exist to stop one inspection's result landing beside another's, and a selection
/// belongs to no operation.
///
/// ## The lifetime, and why the memory is load-bearing rather than decoration
///
/// `acknowledged` is not a second copy of anything the flow knows. It records **which inspection this
/// value has already reacted to**, so that `observe` is idempotent: called twice with the same report it
/// moves nobody, which is what makes "an analysis settling does not move the reader" a property of this
/// type rather than a property of how often SwiftUI happens to call it.
///
/// It is also what keeps a **cancelled** picker harmless. Choosing another file and then dismissing the
/// panel takes the flow `.report(A)` → `.working` → `.report(A)`; without the memory the return would
/// read as a new report and send the reader to the overview after they cancelled. So `none` is ignored
/// entirely — nothing on screen moves nobody — and only a *different* report is a navigation event.
///
/// ## What it cannot see
///
/// There is no comparison here, in any form. A comparison starting, becoming ready, being dismissed,
/// being superseded or failing changes nothing in this type because there is nothing for it to change:
/// no input carries it. That is structural, and `WorkspaceOwnershipTests` asserts it stays so.
///
/// Nothing here is written anywhere that survives a launch. A fresh value is a fresh launch, and a fresh
/// launch is the overview.
struct WorkspaceNavigation {
    /// The section the reader is in. The overview, until they say otherwise or a new file arrives.
    private(set) var section: WorkspaceSection = .overview

    /// The inspection `observe` has already answered for, or `nil` before the first report.
    private var acknowledged: UUID?

    /// The reader chose a section. The only thing that selects one directly, which is why the property
    /// above is not settable: a stray assignment somewhere in a view would be a second way to navigate.
    mutating func select(_ section: WorkspaceSection) {
        self.section = section
    }

    /// The primary inspection changed, or was re-published. **The only rule that moves the reader.**
    ///
    /// - Nothing on screen moves nobody, so `none` returns immediately. Working, idle and a file that
    ///   could not be opened are all `none`, and none of the three is a navigation event.
    /// - The same report moves nobody, however many times it is published. Every analysis settling on a
    ///   report already acknowledged arrives here and is answered by the guard below.
    /// - A **new** report is acknowledged whatever its status, so its own later settlings are quiet too.
    /// - Only a new report that did **not** fail globally returns the reader to the overview. A failed
    ///   inspection is still a report about a file the reader chose, and a failure is not a place to
    ///   send someone (`design.md` §4, scenario 7).
    mutating func observe(_ primary: PrimaryInspection) {
        guard case let .report(id, failedGlobally) = primary else { return }
        guard id != acknowledged else { return }
        acknowledged = id
        guard !failedGlobally else { return }
        section = .overview
    }
}
