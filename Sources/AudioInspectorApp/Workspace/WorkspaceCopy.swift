/// The words the workspace shell itself renders: the five section names, the navigation control they
/// sit in, and the actions in the shell's own chrome.
///
/// ## Why the shell has a copy type at all
///
/// The same reason `PairedVisualsCopy` and `SpectrogramCopy` have one: a surface whose words are
/// literals scattered through a view can only be swept by reading the view. Collected here, **every
/// string this shell can render is a value**, so `WorkspaceCopyTests` covers the surface rather than the
/// repository, and a word added later has nowhere to hide.
///
/// It is not a rewrite. `chooseAnotherFile`, `startComparison` and `closeComparison` are the sentences
/// `RootView` already showed, moved verbatim; the section names are ADR-0026 §3's, unchanged.
///
/// ## What it may not say
///
/// This shell is the surface that introduces a **second file**, so `inspection-workspace-navigation`'s
/// fourth requirement applies to it entire: nothing here states, implies or offers an aggregate over a
/// comparison. No count of properties that agree, differ or cannot be compared; no percentage,
/// similarity, score, confidence or verdict; no ordering by importance; and no phrase meaning that the
/// two files match. **The way through names its destination and says nothing about what is behind it.**
///
/// That extends to numbers of every kind: a count is a number, so no string here carries a digit, and
/// `WorkspaceCopyTests` refuses one. It is the cheapest way to make `"3 differences"` impossible to add
/// quietly, and the shell has never had a legitimate use for a figure.
enum WorkspaceCopy {

    /// A section's name — the only place the five are put into words.
    ///
    /// Total, with no default: a section added to `WorkspaceSection` must be named here rather than
    /// falling through to a placeholder.
    ///
    /// *Spectrum* is the reader's destination; the drawing is still a spectrogram everywhere else
    /// (ADR-0026 §3).
    static func label(for section: WorkspaceSection) -> String {
        switch section {
        case .overview: "Overview"
        case .measurements: "Measurements"
        case .waveform: "Waveform"
        case .spectrum: "Spectrum"
        case .details: "Details"
        }
    }

    /// What the navigation control is, spoken. The sections are named in words rather than by icon, so
    /// the control needs only to say what the choice is about.
    static let sectionNavigation = "Section"

    /// The way to inspect a different primary file. `RootView`'s own wording, unchanged.
    static let chooseAnotherFile = "Choose another file…"

    /// The way through to a comparison. It **names the destination** and describes nothing about what
    /// will be found there — the fourth requirement's third scenario, in one string.
    static let startComparison = "Compare with another file…"

    /// The way back out of one. It says what it does to the surface, and nothing about the two files.
    static let closeComparison = "Close comparison"

    /// **Every string this shell can render**, collected once so the sweep covers the surface rather
    /// than the repository. A section added to `WorkspaceSection` joins it automatically.
    static var everyRenderableString: [String] {
        WorkspaceSection.allCases.map(label(for:))
            + [sectionNavigation, chooseAnotherFile, startComparison, closeComparison]
    }
}
