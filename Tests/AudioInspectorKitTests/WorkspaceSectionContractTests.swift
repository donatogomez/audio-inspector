import Testing

@testable import AudioInspectorApp
@testable import FeatureAnalysis

// R1's first subject: **the five sections themselves**, before anything moves between them.
//
// Everything here is a value, so none of it needs a rendering — which is ADR-0026's own claim about its
// subject: structure and ownership are facts a test can read.

@Suite("App — the workspace's five sections")
struct WorkspaceSectionContractTests {

    /// The count and the order, both. A list asserted only by its length would let a section be
    /// renamed or moved without a failure, and the order is what a reader learns.
    @Test("there are exactly five sections, in reading order")
    func exactlyFiveSectionsInOrder() {
        #expect(WorkspaceSection.allCases.count == 5)
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
    }

    /// ADR-0026 §5's last row, and `inspection-workspace-navigation`'s *Nothing is restored on
    /// relaunch*: a fresh value is a fresh launch. Nothing is read from anywhere to produce it.
    @Test("a workspace begins at the overview")
    func aFreshWorkspaceBeginsAtTheOverview() {
        #expect(WorkspaceNavigation().section == .overview)
    }

    /// Two workspaces are two windows, or one window twice. Neither learns anything from the other,
    /// which is the whole of "no persistence" expressed as a value.
    @Test("a second workspace learns nothing from the first")
    func aSecondWorkspaceLearnsNothing() {
        var first = WorkspaceNavigation()
        first.select(.spectrum)
        #expect(first.section == .spectrum)
        #expect(WorkspaceNavigation().section == .overview)
    }

    @Test("every section can be selected, and selecting one selects exactly it")
    func everySectionIsSelectable() {
        for section in WorkspaceSection.allCases {
            var navigation = WorkspaceNavigation()
            navigation.select(section)
            #expect(navigation.section == section)
        }
    }

    /// The words are part of the contract because they are what a reader navigates by. Five distinct,
    /// non-empty names, and no section reachable only by an icon.
    @Test("each section is named, and no two share a name")
    func eachSectionIsNamed() {
        let labels = WorkspaceSection.allCases.map(WorkspaceCopy.label(for:))
        #expect(labels == ["Overview", "Measurements", "Waveform", "Spectrum", "Details"])
        #expect(Set(labels).count == labels.count)
        for label in labels {
            #expect(!label.isEmpty)
        }
    }

    /// **ADR-0026 §3: *Spectrum* is a navigation label and renames nothing.** The section is where a
    /// reader is going; the artefact keeps the name it has everywhere else, and this fails the moment
    /// someone "makes them consistent" in either direction.
    @Test("the spectrum section renames no artefact")
    func spectrumRenamesNothing() {
        #expect(WorkspaceCopy.label(for: .spectrum) == "Spectrum")
        #expect(SpectrogramCopy.title == "Spectrogram")
        #expect(WorkspaceCopy.label(for: .spectrum) != SpectrogramCopy.title)
    }

    /// The shell's chrome says what it already said. Moving three literals into a copy type was not a
    /// licence to rewrite them, and this is what makes the next rewrite deliberate.
    @Test("the shell's actions keep the words the surface already used")
    func theShellsActionsAreUnchanged() {
        #expect(WorkspaceCopy.chooseAnotherFile == "Choose another file…")
        #expect(WorkspaceCopy.startComparison == "Compare with another file…")
        #expect(WorkspaceCopy.closeComparison == "Close comparison")
    }
}
