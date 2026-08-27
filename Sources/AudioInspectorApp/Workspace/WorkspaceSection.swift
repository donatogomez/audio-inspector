/// The five areas an inspection is presented as, of which exactly one is selected at a time
/// (ADR-0026 §3).
///
/// **The same five exist in both modes.** A comparison changes what a section *contains*; it adds,
/// removes, reorders and renames nothing here. That is the whole reason this is a closed enumeration
/// rather than a list built from what happens to be available: a section whose artefact is absent or
/// failed is still a section, and there is no expression anywhere that could narrow the five to four.
///
/// **`spectrum` is a navigation label, not a rename** (ADR-0026 §3). The artefact stays a spectrogram,
/// the capability stays `audio-two-file-visual-presentation`, and `SpectrogramCopy.title` is untouched.
/// Sections are named for where a reader is going; the drawing keeps the name it has everywhere else.
///
/// **It lives in the composition root and may not leave it.** `AudioInspectorDomain`, `FeatureImport`
/// and `FeatureAnalysis` cannot observe which section is selected — asserted by
/// `WorkspaceOwnershipTests`, not merely intended. It is deliberately `internal`: nothing outside this
/// module has any business naming a section, and `AppContainer.makeRootView()` is the whole of the
/// public surface.
///
/// **What it deliberately is not.** Not `Codable` and not persisted (ADR-0026 §5 launches at
/// `overview`); it carries no domain identifier, knows nothing of reports or comparisons, and has no
/// child routes. Its words live in `WorkspaceCopy`, so a label can be rewritten without touching the
/// structure a reader navigates.
///
/// - `CaseIterable` is the navigation control's own list, in reading order, and the value the contract
///   test asserts is exactly five. Without it the order would be restated wherever the sections are
///   offered, which is how a sixth appears in one place and not another.
/// - `Hashable` is what a SwiftUI selection needs: `Picker` matches its tag by hashing, and `ForEach`
///   identifies by `\.self`.
///
/// Nothing else is conformed to. `Identifiable` would duplicate `Hashable`'s job here, and an `id` on
/// a section is the first step toward a route.
enum WorkspaceSection: CaseIterable, Hashable {
    /// The entry point. **R1 builds no content for it** — `add-inspection-overview` (R7) does, to
    /// ADR-0026 §6 exactly.
    case overview
    case measurements
    case waveform
    /// The spectrogram's section. Named for the reader's destination; see the note above.
    case spectrum
    case details
}
