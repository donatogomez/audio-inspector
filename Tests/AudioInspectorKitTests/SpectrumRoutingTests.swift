import Foundation
import Testing

@testable import AudioInspectorApp

// R6's other half: **which surface the workspace shows, and that the drawing it moved has one owner.**
//
// Read off the composition root, where the section lives and where the choice is necessarily made.
// The shape is `DetailsRoutingTests`', `MeasurementsRoutingTests`' and `WaveformRoutingTests`' —
// the four slices make the same kind of claim.

@Suite("App — routing the spectrum workspace")
struct SpectrumRoutingTests {

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

    @Test("selecting spectrum shows the spectrum workspace")
    func spectrumShowsTheWorkspace() throws {
        let routing = try routing()
        #expect(routing.contains { $0.contains("case .spectrum:") })
        #expect(routing.contains { $0.contains("ReportSpectrumView(") })
    }

    /// **Which drawing is shown is decided once, for every visual surface.** The workspace is handed the
    /// same `ReportVisuals` the waveform workspace and the transitional page are handed, from the same
    /// call and the same one read of the comparison.
    @Test("the workspace is handed the report's own visuals")
    func theWorkspaceIsHandedTheReportsOwnVisuals() throws {
        let routing = try routing()
        let handOff = "ReportSpectrumView(visuals: Self.reportVisuals(for: presentation, in: flowComparison))"
        #expect(routing.contains { $0.contains(handOff) })
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

    /// **The workspace and the page it replaces are alternatives, never both**, and every surface is
    /// built exactly once in the whole root.
    @Test("every surface is built exactly once, and they are alternatives")
    func everySurfaceIsBuiltOnce() throws {
        let routing = try routing()
        let workspace = try #require(routing.firstIndex { $0.contains("ReportSpectrumView(") })
        let calls = try code().filter { !$0.contains("private func") }
        for surface in ["ReportSpectrumView(", "ReportWaveformView(", "ReportDetailsView(",
                        "ReportMeasurementsView(", "InspectionOverviewView(", "ComparisonOverviewView("] {
            #expect(calls.filter { $0.contains(surface) }.count == 1, "\(surface) is built more than once")
        }
        for gone in ["legacyReportSurface(", "ReportView(", "ComparisonSection("] {
            #expect(!calls.contains { $0.contains(gone) }, "the root still builds \(gone)")
        }
    }

    /// **No section stands in for another any more.** Every one of the five routes to a surface of its
    /// own, in both modes.
    @Test("no section falls back to another's surface")
    func noSectionStandsInForAnother() throws {
        let routing = try routing()
        let overview = try #require(routing.firstIndex { $0.contains("case .overview") })
        for section in [".details", ".measurements", ".waveform", ".spectrum"] {
            #expect(!routing[overview].contains(section), "\(section) falls into the overview branch")
        }
    }

    /// R3, R4 and R5 are untouched: their sections still route to their own surfaces.
    @Test("details, measurements and waveform still show their own surfaces")
    func theEarlierSectionsAreUntouched() throws {
        let routing = try routing()
        #expect(routing.contains { $0.contains("ReportDetailsView(report: presentation.report") })
        #expect(routing.contains { $0.contains("ReportMeasurementsView(") })
        let waveform = "ReportWaveformView(visuals: Self.reportVisuals(for: presentation, in: flowComparison))"
        #expect(routing.contains { $0.contains(waveform) })
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

    /// **No new navigation.** A fourth spatial section is still chosen by the value R1 owns.
    @Test("routing a fourth section introduces no navigation machinery")
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
