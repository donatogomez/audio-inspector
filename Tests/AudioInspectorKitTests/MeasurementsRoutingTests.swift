import Foundation
import Testing

@testable import AudioInspectorApp

// R4's other half: **which surface the workspace shows, and that the measurements it moved have one
// owner.**
//
// Read off the composition root, where the section lives and where the choice is necessarily made:
// `WorkspaceSection` is `AudioInspectorApp`'s and `FeatureAnalysis` cannot see it. The shape is
// `DetailsRoutingTests`', deliberately — the two slices make the same kind of claim.

@Suite("App — routing the measurements section")
struct MeasurementsRoutingTests {

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioInspectorApp/RootView.swift")
    }

    private func code() throws -> [String] {
        try String(contentsOf: Self.root, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    /// The lines that choose a surface, and only those.
    private func routing() throws -> [String] {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        let rest = code[(start + 1)...]
        let end = try #require(rest.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "}" })
        return Array(rest[..<end])
    }

    // MARK: - 3.1 — the section is routed to its own surface

    @Test("selecting measurements shows the measurements surface")
    func measurementsShowsTheMeasurementsSurface() throws {
        let routing = try routing()
        #expect(routing.contains { $0.contains("case .measurements:") })
        #expect(routing.contains { $0.contains("ReportMeasurementsView(") })
    }

    /// **The four presentations are the ones the legacy page is handed**, built by the same four
    /// mappings from the same inspection — so a figure cannot differ between the two surfaces.
    @Test("the surface is handed the report's own four measurement presentations")
    func theSurfaceIsHandedTheReportsOwnPresentations() throws {
        let routing = try routing()
        for mapping in [
            "signalLevelMetricsPresentation(for: presentation.signalLevelMetrics)",
            "truePeakPresentation(for: presentation.truePeak)",
            "loudnessPresentation(for: presentation.loudness)",
            "programmeBandwidthPresentation(for: presentation.significantBandwidth)",
        ] {
            #expect(routing.contains { $0.contains(mapping) }, "the section does not receive \(mapping)")
        }
    }

    /// **The comparison reaches this section now, and it is the same one every other section is
    /// handed.** R4 asserted the opposite — that no comparison reached here — because the comparison
    /// still lived whole on the transitional page and R8 owned moving it. R8 moved it, so the property
    /// worth protecting is no longer *absence* but *identity*: the section is handed the comparison
    /// derived from the one read of the flow, not a second read that could belong to another operation.
    @Test("the measurements surface is handed the one comparison the root read")
    func theSectionIsHandedTheOneComparison() throws {
        let routing = try routing()
        let start = try #require(routing.firstIndex { $0.contains("ReportMeasurementsView(") })
        let rest = routing[(start + 1)...]
        let end = try #require(rest.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(")") })
        #expect(rest[..<end].contains { $0.contains("comparison: comparison") },
                "the section is not handed the comparison")
        // And the root reads the flow's comparison exactly once, so nothing it hands out can straddle
        // a change.
        #expect(try code().filter { $0.contains("let flowComparison = flow.comparison") }.count == 1)
    }

    /// **Total, with no default**, so a section added later has to be routed rather than silently
    /// inheriting the surface that stands in for the unfinished ones.
    @Test("every section is routed explicitly")
    func everySectionIsRoutedExplicitly() throws {
        let routing = try routing()
        #expect(!routing.contains { $0.contains("default:") }, "a section falls through to a default")
        for section in WorkspaceSection.allCases {
            let name = String(describing: section)
            #expect(routing.contains { $0.contains(".\(name)") }, "\(name) is not named in the routing")
        }
    }

    // MARK: - 3.1 — one visible owner

    /// **The section and the page it replaces are alternatives, never both.** The transitional report
    /// page is another branch of the same switch, so the four measurement blocks it carries cannot
    /// appear beside this section.
    @Test("each section is built exactly once, and no transitional page remains")
    func eachSectionIsBuiltOnce() throws {
        let calls = try code().filter { !$0.contains("private func") }
        #expect(calls.filter { $0.contains("ReportMeasurementsView(") }.count == 1)
        #expect(calls.filter { $0.contains("ReportDetailsView(") }.count == 1)
        for gone in ["legacyReportSurface(", "ReportView(", "ComparisonSection("] {
            #expect(!calls.contains { $0.contains(gone) }, "the root still builds \(gone)")
        }
    }

    /// R3 is untouched: Details still routes to Details, and never to the measurements surface.
    @Test("details still shows details")
    func detailsStillShowsDetails() throws {
        let routing = try routing()
        let details = try #require(routing.firstIndex { $0.contains("case .details:") })
        let next = try #require(routing[(details + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(next.contains("ReportDetailsView(report: presentation.report"))
    }

    /// The export survives the page's removal, where the hotfix put it: above the section routing, once.
    @Test("the export is still attached above the routing")
    func theExportSurvives() throws {
        let code = try code()
        let attach = try #require(code.firstIndex { $0.contains(".reportExportToolbar(") })
        let routing = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        #expect(attach < routing)
        #expect(code.filter { $0.contains(".reportExportToolbar(") }.count == 1)
    }

    // MARK: - 3.2 — R1 is untouched

    @Test("the workspace still defines exactly its five sections")
    func theWorkspaceStillHasFiveSections() {
        #expect(WorkspaceSection.allCases.count == 5)
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
    }

    /// **No new navigation.** The section is chosen by the value R1 owns; nothing here introduces a
    /// stack, a split view, a sidebar or a second selection.
    @Test("routing a second section introduces no navigation machinery")
    func noNavigationMachineryIsIntroduced() throws {
        let code = try code()
        for machinery in ["NavigationStack", "NavigationSplitView", "NavigationLink", "NavigationPath",
                          "TabView", "NavigationView"] {
            #expect(!code.contains { $0.contains(machinery) }, "the root introduces \(machinery)")
        }
        // The selection is still read from the one place R1 put it: the picker, and the routing.
        #expect(code.filter { $0.contains("navigation.section") }.count == 2,
                "the section is read from more places than the picker and the routing")
    }

    // MARK: - 4.5 — nothing beneath the surface moved

    /// **This slice computes nothing.** The section is built from presentations, so no decoder, no read
    /// and no accumulator can be reached from it — asserted over the two files it added.
    @Test("the measurements surface starts no work of its own")
    func theSurfaceStartsNoWork() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis")
        for file in ["ReportMeasurementsView.swift", "ReportMeasurementsPresentation.swift"] {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["AVFoundation", "AudioInspectorMedia", "AudioInspectorAnalysis", "Process",
                             "Accumulator", "decode", "Decoder", "Task {", "async"] {
                #expect(!text.contains(forbidden), "\(file) reaches for \(forbidden)")
            }
        }
    }
}
