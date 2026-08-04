import Testing

@testable import AudioInspectorApp

/// Tests the local suggested-name rule: drop the source extension, add `-inspection.json`, neutralize
/// path separators, fall back to `inspection.json` when no valid base remains. Never uses a path.
@Suite("App — suggested export name")
struct SuggestedExportNameTests {

    @Test func normalNameDropsExtensionAndAddsSuffix() {
        #expect(SuggestedExportName.make(fromDisplayName: "interview-side-a.m4a") == "interview-side-a-inspection.json")
    }

    @Test func multipleDotsDropOnlyTheLastExtension() {
        #expect(SuggestedExportName.make(fromDisplayName: "my.song.final.flac") == "my.song.final-inspection.json")
    }

    @Test func nameWithoutExtensionJustGetsTheSuffix() {
        #expect(SuggestedExportName.make(fromDisplayName: "recording") == "recording-inspection.json")
    }

    @Test func emptyNameFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "") == "inspection.json")
    }

    @Test func whitespaceOnlyNameFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "   ") == "inspection.json")
    }

    @Test func pathSeparatorsAreNeutralized() {
        let name = SuggestedExportName.make(fromDisplayName: "a/b:c.wav")
        #expect(name == "abc-inspection.json")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test func nameOfOnlySeparatorsFallsBack() {
        #expect(SuggestedExportName.make(fromDisplayName: "///") == "inspection.json")
    }
}
