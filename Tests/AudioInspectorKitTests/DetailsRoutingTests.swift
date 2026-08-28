import Foundation
import Testing

@testable import AudioInspectorApp

// R3's other half: **which surface the workspace shows, and that the content it moved has one owner.**
//
// Read off the composition root, where the section lives and where the choice is necessarily made:
// `WorkspaceSection` is `AudioInspectorApp`'s and `FeatureAnalysis` cannot see it.

@Suite("App — routing the details section")
struct DetailsRoutingTests {

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

    // MARK: - 1.2 — the section is routed, and nothing else changes

    @Test("selecting details shows the details surface")
    func detailsShowsTheDetailsSurface() throws {
        let routing = try routing()
        #expect(routing.contains { $0.contains("case .details:") })
        #expect(routing.contains { $0.contains("ReportDetailsView(report: presentation.report)") })
    }

    /// **Total, with no default**, so a section added later has to be routed rather than silently
    /// inheriting the surface that stands in for the unfinished ones.
    @Test("every section is routed explicitly")
    func everySectionIsRoutedExplicitly() throws {
        let routing = try routing()
        #expect(!routing.contains { $0.contains("default:") }, "a section falls through to a default")
        for section in WorkspaceSection.allCases {
            let name = String(describing: section)
            #expect(
                routing.contains { $0.contains(".\(name)") },
                "\(name) is not named in the routing"
            )
        }
    }

    /// **No new navigation.** The section is chosen by the value R1 owns; nothing here introduces a
    /// stack, a split view, a sidebar or a second selection.
    @Test("routing a section introduces no navigation machinery")
    func noNavigationMachineryIsIntroduced() throws {
        let code = try code()
        for machinery in ["NavigationStack", "NavigationSplitView", "NavigationLink", "NavigationPath",
                         "TabView", "NavigationView"] {
            #expect(!code.contains { $0.contains(machinery) }, "the root introduces \(machinery)")
        }
        // The selection is still read from the one place R1 put it.
        #expect(code.filter { $0.contains("navigation.section") }.count == 2,
                "the section is read from more places than the picker and the routing")
    }

    // MARK: - 1.3 — one visible owner

    /// **Details and the page it replaces are alternatives, never both.** The legacy report page is one
    /// branch of the same switch, so the blocks Details presents cannot appear twice on screen.
    @Test("details and the legacy report page are alternatives")
    func detailsAndTheLegacyPageAreAlternatives() throws {
        let routing = try routing()
        let details = try #require(routing.firstIndex { $0.contains("ReportDetailsView(") })
        let legacy = try #require(routing.firstIndex { $0.contains("legacyReportSurface(") })
        #expect(details != legacy, "both surfaces are built in the same branch")

        // Each is *built* exactly once in the whole root, so neither is rendered a second time
        // elsewhere. Declarations are excluded — what matters is how many places render one.
        let calls = try code().filter { !$0.contains("private func") }
        #expect(calls.filter { $0.contains("ReportDetailsView(") }.count == 1)
        #expect(calls.filter { $0.contains("legacyReportSurface(") }.count == 1)
        #expect(calls.filter { $0.contains("ReportView(") }.count == 1)
    }

    /// The legacy page is untouched by this slice: it still carries the comparison, in the same call,
    /// with the same presentation.
    @Test("the legacy report page still carries the comparison, unchanged")
    func theLegacyPageStillCarriesTheComparison() throws {
        let code = try code()
        #expect(code.contains { $0.contains("comparison: Self.comparisonPresentation(for: comparison)") })
        #expect(code.contains { $0.contains("export: export") })
    }

    // MARK: - 4.1 — R1 is untouched

    @Test("the workspace still defines exactly its five sections")
    func theWorkspaceStillHasFiveSections() {
        #expect(WorkspaceSection.allCases.count == 5)
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
    }

    /// Filling a section moves nothing: the rule that returns the reader to the overview is the one R1
    /// wrote, applied in the one place it was applied before.
    @Test("filling a section changes nothing about how the selection moves")
    func theSelectionRuleIsUnchanged() throws {
        let code = try code()
        #expect(code.filter { $0.contains(".observe(") }.count == 1)
        #expect(code.contains { $0.contains(".onChange(of: PrimaryInspection(flow.state))") })

        var navigation = WorkspaceNavigation()
        navigation.select(.details)
        #expect(navigation.section == .details)
        navigation.observe(.none)
        #expect(navigation.section == .details, "an absent inspection moved the reader")
    }
}
