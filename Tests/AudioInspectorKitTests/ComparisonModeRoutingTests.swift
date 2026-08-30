import Foundation
import Testing

import AudioInspectorDomain
import FeatureAnalysis
import FeatureImport
@testable import AudioInspectorApp

// R8's other half: **which surface each section shows in each mode, and that nothing about the reader
// moved.** Read off the composition root, where the section lives and where the choice is made.

@Suite("App — routing the comparison mode")
struct ComparisonModeRoutingTests {

    private func code() throws -> [String] {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/AudioInspectorApp/RootView.swift"),
            encoding: .utf8
        )
        .components(separatedBy: .newlines)
        .filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
        }
    }

    private func routing() throws -> [String] {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        return Array(code[start...].prefix { !$0.contains("Divider()") })
    }

    private func report(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 1_024, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)),
            properties: TechnicalProperties(
                container: .available("wav"), duration: .available(1.0),
                sampleRate: .available(44_100), channelCount: .available(2),
                bitDepth: .available(16), codec: .available("lpcm")),
            warnings: [], status: .completed)
    }

    private var everyComparisonState: [ImportFlowModel.ComparisonState] {
        [
            .none,
            .loading,
            .ready(FileComparison(first: report("a.wav"), second: report("b.wav")), nil, nil),
            .failed(message: "The second file could not be opened."),
        ]
    }

    // MARK: - A mode, not a section

    /// **The five are the same five.** A comparison adds none, removes none and renames none — it is a
    /// mode of what each section contains (ADR-0026 §2, §3).
    @Test("a comparison adds no section and no navigation")
    func aComparisonAddsNoSection() throws {
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
        #expect(!WorkspaceSection.allCases.contains { String(describing: $0).localizedCaseInsensitiveContains("compar") })
        let code = try code()
        for machinery in ["NavigationStack", "NavigationSplitView", "NavigationLink", "NavigationPath",
                          "TabView", "NavigationView", "WorkspaceMode", "comparisonSection"] {
            #expect(!code.contains { $0.contains(machinery) }, "the root introduces \(machinery)")
        }
        // The selection is still read from the two places R1 put it, and persisted nowhere.
        #expect(code.filter { $0.contains("navigation.section") }.count == 2)
        #expect(!code.contains { $0.contains("UserDefaults") })
    }

    /// **One read of the flow's comparison**, so the five sections, the drawings and the controls can
    /// never disagree about whether this window has one file or two.
    @Test("every section is handed the same one comparison")
    func oneComparisonIsReadOnce() throws {
        let code = try code()
        #expect(code.filter { $0.contains("let flowComparison = flow.comparison") }.count == 1)
        #expect(code.filter { $0.contains("let comparison = Self.comparisonPresentation(for: flowComparison)") }.count == 1)
        let routing = try routing()
        #expect(routing.contains { $0.contains("ReportDetailsView(report: presentation.report, comparison: comparison)") })
        #expect(routing.contains { $0.contains("comparison: comparison") })
        #expect(routing.filter { $0.contains("Self.reportVisuals(for: presentation, in: flowComparison)") }.count == 2)
    }

    /// Both overviews exist, are alternatives, and neither is reachable from the other's state.
    @Test("the overview routes by comparison state, totally")
    func theOverviewRoutesByState() throws {
        let routing = try routing()
        let overview = try #require(routing.firstIndex { $0.contains("case .overview:") })
        let branch = Array(routing[overview...])
        #expect(branch.contains { $0.contains("switch comparison {") })
        #expect(branch.contains { $0.contains("case .none:") })
        #expect(branch.contains { $0.contains("InspectionOverviewView(") })
        #expect(branch.contains { $0.contains("case .loading, .ready, .failed:") })
        #expect(branch.contains { $0.contains("ComparisonOverviewView(") })
        #expect(!branch.contains { $0.contains("default:") })
    }

    /// Exactly one of the two overviews can be on screen, and exactly three states reach the comparison
    /// one — the same split the transitional page used, now pointing at a surface of its own.
    @Test("each comparison state reaches exactly one overview")
    func eachStateReachesOneOverview() {
        var inspection = 0, comparison = 0
        for state in everyComparisonState {
            switch RootView.comparisonPresentation(for: state) {
            case .none: inspection += 1
            case .loading, .ready, .failed: comparison += 1
            }
        }
        #expect(inspection == 1)
        #expect(comparison == 3)
    }

    // MARK: - The visual sections, which needed nothing

    /// R5 and R6 built these against `ReportVisuals`, which has paired the two files since it shipped —
    /// so the drawings have always worked in comparison mode. R8 changed neither.
    @Test("the visual sections pair through the value they already took")
    func theVisualSectionsAreUnchanged() {
        let ready = ImportFlowModel.ComparisonState.ready(
            FileComparison(first: report("a.wav"), second: report("b.wav")), nil, nil)
        let presentation = InspectionPresentation(report: report("a.wav"), waveform: .unavailable)
        // A pair that has not settled its drawings is not a pair — unchanged by R8.
        #expect(RootView.reportVisuals(for: presentation, in: ready)
                == .single(waveform: .absent, spectrogram: .loading))
        #expect(RootView.reportVisuals(for: presentation, in: .none)
                == .single(waveform: .absent, spectrogram: .loading))
    }

    // MARK: - The controls, none of which moved

    /// R8 removed a page. **None of these lived in it**, so none of them moved, and none was added.
    @Test("every control the reader had is still here")
    func everyControlSurvives() throws {
        let code = try code()
        #expect(code.contains { $0.contains("Button(WorkspaceCopy.startComparison)") })
        #expect(code.contains { $0.contains("Button(WorkspaceCopy.closeComparison)") })
        #expect(code.contains { $0.contains("flow.dismissComparison()") })
        #expect(code.contains { $0.contains("Button(WorkspaceCopy.chooseAnotherFile)") })
        #expect(code.contains { $0.contains("flow.selectAndCompare()") })
        #expect(code.contains { $0.contains("flow.selectAndInspect()") })
    }

    /// The export is where the hotfix put it and R8 did not move it: once, above the section routing, so
    /// it is reachable from all five sections and in every comparison state.
    @Test("the export is untouched by this slice")
    func theExportIsUntouched() throws {
        let code = try code()
        let attach = try #require(code.firstIndex { $0.contains(".reportExportToolbar(") })
        let routing = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        #expect(attach < routing)
        #expect(code.filter { $0.contains(".reportExportToolbar(") }.count == 1)
        // And it takes no comparison: the document exported is one file's report, as it has always been.
        let start = try #require(code.firstIndex { $0.contains(".reportExportToolbar(") })
        let end = try #require(code[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == ")" })
        for line in code[start...end] {
            #expect(!line.contains("comparison"), "a comparison reaches the export: \(line)")
        }
    }

    // MARK: - What the page took with it

    @Test("nothing in the root builds the removed surfaces")
    func theRemovedSurfacesAreNotBuilt() throws {
        let calls = try code().filter { !$0.contains("private func") }
        for gone in ["legacyReportSurface(", "ReportView(", "ComparisonSection(", "warningSummary"] {
            #expect(!calls.contains { $0.contains(gone) }, "the root still builds \(gone)")
        }
    }
}
