import Testing

@testable import AudioInspectorApp

/// Tests the local suggested-name rule: separators become `-` (so segments stay distinguishable),
/// runs of `-` collapse, the source extension is dropped, edge separators/dots are trimmed, and an
/// empty or degenerate base falls back to `inspection.json`. Never uses a path.
@Suite("App — suggested export name")
struct SuggestedExportNameTests {

    // MARK: - Ordinary names

    @Test func normalNameDropsExtensionAndAddsSuffix() {
        #expect(SuggestedExportName.make(fromDisplayName: "interview-side-a.m4a") == "interview-side-a-inspection.json")
    }

    @Test func multipleDotsDropOnlyTheLastExtension() {
        #expect(SuggestedExportName.make(fromDisplayName: "my.song.final.flac") == "my.song.final-inspection.json")
    }

    @Test func nameWithoutExtensionJustGetsTheSuffix() {
        #expect(SuggestedExportName.make(fromDisplayName: "recording") == "recording-inspection.json")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(SuggestedExportName.make(fromDisplayName: "  spaced .wav") == "spaced-inspection.json")
    }

    // MARK: - Separators become hyphens (no ambiguous concatenation)

    @Test func separatorsBecomeHyphensKeepingSegmentsDistinct() {
        #expect(SuggestedExportName.make(fromDisplayName: "a/b:c.wav") == "a-b-c-inspection.json")
    }

    @Test func numericSegmentsAreNotFusedTogether() {
        // The regression this rule exists for: removing separators would yield a misleading "0102".
        #expect(SuggestedExportName.make(fromDisplayName: "01/02.wav") == "01-02-inspection.json")
    }

    @Test func repeatedSeparatorsCollapseIntoASingleHyphen() {
        #expect(SuggestedExportName.make(fromDisplayName: "a//b::c.wav") == "a-b-c-inspection.json")
        #expect(SuggestedExportName.make(fromDisplayName: "a--b.wav") == "a-b-inspection.json")
    }

    @Test func noProducedNameContainsAPathSeparator() {
        let name = SuggestedExportName.make(fromDisplayName: "a/b:c.wav")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    // MARK: - Dots at the edges (never a hidden or degenerate name)

    @Test func leadingDotDoesNotProduceAHiddenName() {
        let name = SuggestedExportName.make(fromDisplayName: ".hidden")
        #expect(name == "hidden-inspection.json")
        #expect(!name.hasPrefix("."))
    }

    @Test func trailingDotIsDropped() {
        #expect(SuggestedExportName.make(fromDisplayName: "recording.") == "recording-inspection.json")
    }

    @Test func singleDotFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: ".") == "inspection.json")
    }

    @Test func doubleDotFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "..") == "inspection.json")
    }

    // MARK: - Degenerate input falls back

    @Test func emptyNameFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "") == "inspection.json")
    }

    @Test func whitespaceOnlyNameFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "   ") == "inspection.json")
    }

    @Test func nameOfOnlySeparatorsFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "///") == "inspection.json")
    }

    @Test func nameOfOnlySeparatorsDotsAndSpacesFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: " . / : ") == "inspection.json")
    }

    // MARK: - Length (documented behaviour, not a truncation requirement)

    @Test func longNamesKeepTheirBaseUntruncated() {
        // Documents current behaviour: the rule does not truncate. A name long enough to exceed the
        // filesystem limit surfaces later as a write failure, not as a silently altered name.
        let base = String(repeating: "x", count: 250)
        #expect(SuggestedExportName.make(fromDisplayName: base + ".wav") == base + "-inspection.json")
    }
}
