import Foundation
import Testing

@testable import AudioInspectorApp

// R5's other half: **which surface the workspace shows, and that the drawing it moved has one owner.**
//
// Read off the composition root, where the section lives and where the choice is necessarily made:
// `WorkspaceSection` is `AudioInspectorApp`'s and `FeatureAnalysis` cannot see it. The shape is
// `DetailsRoutingTests`' and `MeasurementsRoutingTests`', deliberately — the three slices make the same
// kind of claim.

@Suite("App — routing the waveform workspace")
struct WaveformRoutingTests {

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

    private func routing() throws -> [String] {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        let rest = code[(start + 1)...]
        let end = try #require(rest.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "}" })
        return Array(rest[..<end])
    }

    // MARK: - 4.1 — the section is routed to its own surface

    @Test("selecting waveform shows the waveform workspace")
    func waveformShowsTheWorkspace() throws {
        let routing = try routing()
        #expect(routing.contains { $0.contains("case .waveform:") })
        #expect(routing.contains { $0.contains("ReportWaveformView(") })
    }

    /// **Which drawing is shown is decided once, for both surfaces.** The workspace is handed the same
    /// `ReportVisuals` the transitional page is handed, built by the same call from the same one read of
    /// the comparison — so a pair can never appear on one and a single drawing on the other.
    @Test("the workspace is handed the report's own visuals")
    func theWorkspaceIsHandedTheReportsOwnVisuals() throws {
        let routing = try routing()
        let handOff = "ReportWaveformView(visuals: Self.reportVisuals(for: presentation, in: flowComparison))"
        #expect(routing.contains { $0.contains(handOff) })
        // The same call every visual surface uses, so there is exactly one rule about which drawings
        // are shown. R6 added the spectrum workspace as the third caller; a fourth would mean a surface
        // deciding for itself.
        let code = try code()
        #expect(code.filter { $0.contains("Self.reportVisuals(for:") }.count == 2,
                "the visuals are derived from more places than the two visual workspaces")
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

    // MARK: - 4.1 — one visible owner

    /// **The workspace and the page it replaces are alternatives, never both.** The drawing the page
    /// carries cannot appear beside the section named for it.
    @Test("the workspace and the legacy report page are alternatives")
    func theWorkspaceAndTheLegacyPageAreAlternatives() throws {
        let routing = try routing()
        let workspace = try #require(routing.firstIndex { $0.contains("ReportWaveformView(") })
        let calls = try code().filter { !$0.contains("private func") }
        #expect(calls.filter { $0.contains("ReportWaveformView(") }.count == 1)
        #expect(calls.filter { $0.contains("ReportDetailsView(") }.count == 1)
        #expect(calls.filter { $0.contains("ReportMeasurementsView(") }.count == 1)
        for gone in ["legacyReportSurface(", "ReportView(", "ComparisonSection("] {
            #expect(!calls.contains { $0.contains(gone) }, "the root still builds \(gone)")
        }
    }

    /// Overview keeps the transitional page, until R7 builds its own. **Waveform does not, and neither
    /// does Spectrum since R6** — the branch that stands in for unfinished sections must not reclaim a
    /// section that has its own surface.
    @Test("only overview still shows the transitional page")
    func onlyOverviewStillShowsTheTransitionalPage() throws {
        let routing = try routing()
        let legacy = try #require(routing.firstIndex { $0.contains("case .overview") })
        #expect(!routing[legacy].contains(".waveform"), "waveform falls into the transitional branch")
        #expect(!routing[legacy].contains(".spectrum"), "spectrum falls into the transitional branch")
        #expect(!routing[legacy].contains(".details"))
        #expect(!routing[legacy].contains(".measurements"))
    }

    /// R3 and R4 are untouched: their sections still route to their own surfaces.
    @Test("details and measurements still show their own surfaces")
    func detailsAndMeasurementsAreUntouched() throws {
        let routing = try routing()
        #expect(routing.contains { $0.contains("case .details:") })
        #expect(routing.contains { $0.contains("ReportDetailsView(report: presentation.report") })
        #expect(routing.contains { $0.contains("case .measurements:") })
        #expect(routing.contains { $0.contains("ReportMeasurementsView(") })
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

    // MARK: - 4.2 — R1 is untouched

    @Test("the workspace still defines exactly its five sections")
    func theWorkspaceStillHasFiveSections() {
        #expect(WorkspaceSection.allCases.count == 5)
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
    }

    /// **No new navigation.** A section that is now spatial is still chosen by the value R1 owns.
    @Test("routing a third section introduces no navigation machinery")
    func noNavigationMachineryIsIntroduced() throws {
        let code = try code()
        for machinery in ["NavigationStack", "NavigationSplitView", "NavigationLink", "NavigationPath",
                          "TabView", "NavigationView"] {
            #expect(!code.contains { $0.contains(machinery) }, "the root introduces \(machinery)")
        }
        #expect(code.filter { $0.contains("navigation.section") }.count == 2,
                "the section is read from more places than the picker and the routing")
    }
}
