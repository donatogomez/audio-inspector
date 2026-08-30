import Foundation
import Testing

import AudioInspectorDomain
import FeatureAnalysis
import FeatureImport
@testable import AudioInspectorApp

// R7's other half: **which surface the Overview shows, and the one thing removing the old page would
// have taken with it.**
//
// Read off the composition root, where the section lives and where the choice is necessarily made:
// `WorkspaceSection` is `AudioInspectorApp`'s and `FeatureAnalysis` cannot see it.

@Suite("App — routing the overview section")
struct OverviewRoutingTests {

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

    /// The `.overview` branch, from its own `case` to the end of the routing switch.
    private func overviewBranch() throws -> [String] {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("case .overview:") })
        return Array(code[start...].prefix(while: { !$0.contains("Divider()") }))
    }

    private func reference(_ name: String) -> AudioFileReference {
        AudioFileReference(
            displayName: name, fileExtension: "wav", sizeBytes: 1_024, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
        )
    }

    private func report(_ name: String) -> InspectionReport {
        InspectionReport(
            file: reference(name),
            properties: TechnicalProperties(
                container: .available("wav"), duration: .available(1.0),
                sampleRate: .available(44_100), channelCount: .available(2),
                bitDepth: .available(16), codec: .available("lpcm")
            ),
            warnings: [],
            status: .completed
        )
    }

    /// Every state the flow's comparison can be in — the four the root has to answer.
    private var everyComparisonState: [ImportFlowModel.ComparisonState] {
        [
            .none,
            .loading,
            .ready(FileComparison(first: report("a.wav"), second: report("b.wav")), nil, nil),
            .failed(message: "The second file could not be opened."),
        ]
    }

    // MARK: - 3.1 — the overview has a surface of its own

    @Test("selecting the overview shows the overview surface")
    func theOverviewShowsItsOwnSurface() throws {
        let branch = try overviewBranch()
        #expect(branch.contains { $0.contains("InspectionOverviewView(") })
        #expect(branch.contains { $0.contains("report: presentation.report") })
        // The same mapping every other section's values go through, so a figure or a drawing cannot
        // differ between this surface and the section that owns it.
        #expect(branch.contains { $0.contains("Self.waveformPresentation(for: presentation.waveform)") })
        for measurement in ["signalLevelMetricsPresentation(for: presentation.signalLevelMetrics)",
                            "truePeakPresentation(for: presentation.truePeak)",
                            "loudnessPresentation(for: presentation.loudness)",
                            "programmeBandwidthPresentation(for: presentation.significantBandwidth)"] {
            #expect(branch.contains { $0.contains(measurement) }, "the overview is not handed \(measurement)")
        }
    }

    /// **All five sections are real now.** None of the five routes to the transitional page
    /// unconditionally.
    @Test("every section has a surface of its own")
    func everySectionHasItsOwnSurface() throws {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        let routing = Array(code[start...].prefix(while: { !$0.contains("Divider()") }))
        for surface in ["ReportDetailsView(", "ReportMeasurementsView(", "ReportWaveformView(",
                        "ReportSpectrumView(", "InspectionOverviewView("] {
            #expect(routing.contains { $0.contains(surface) }, "\(surface) is not routed")
        }
        #expect(WorkspaceSection.allCases.count == 5)
    }

    // MARK: - 3.2 / 4.7 — the comparison the old page was carrying

    /// **The split is on the comparison, and it is total.** A new comparison state has to be answered
    /// here rather than silently falling to one side — which is exactly how the comparison would go
    /// missing. R8 changed what the second side is: the transitional page became a Comparison Overview
    /// of its own, and the split itself is unchanged.
    @Test("the overview splits on the comparison, with no default")
    func theSplitIsOnTheComparisonAndIsTotal() throws {
        let branch = try overviewBranch()
        #expect(branch.contains { $0.contains("switch comparison {") })
        #expect(branch.contains { $0.contains("case .none:") })
        #expect(branch.contains { $0.contains("case .loading, .ready, .failed:") })
        #expect(!branch.contains { $0.contains("default:") }, "a comparison state falls through to a default")
        #expect(branch.contains { $0.contains("ComparisonOverviewView(report: presentation.report, comparison: comparison)") })
    }

    /// **The page R7 could not remove is gone.** R7 kept `legacyReportSurface` because it was the only
    /// route the comparison had onto the screen; R8 gave the comparison routes of its own in all five
    /// sections, so the page has no caller left — and neither the page, the view it built, nor the
    /// comparison surface inside it exists any more.
    @Test("the transitional page is gone, and both overviews are built once")
    func theTransitionalPageIsGone() throws {
        let calls = try code().filter { !$0.contains("private func") }
        for gone in ["legacyReportSurface(", "ReportView(", "ComparisonSection("] {
            #expect(!calls.contains { $0.contains(gone) }, "the root still builds \(gone)")
        }
        #expect(calls.filter { $0.contains("InspectionOverviewView(") }.count == 1)
        #expect(calls.filter { $0.contains("ComparisonOverviewView(") }.count == 1)
    }

    /// Three of the four comparison states still reach the page that carries the comparison, and exactly
    /// one — no comparison at all — reaches the new surface. Asserted against the mapping the branch
    /// switches on, rather than against a rendering nobody can read.
    @Test("the comparison survives in every state it can be in")
    func theComparisonSurvives() {
        var reachingTheComparison = 0
        var reachingTheOverview = 0
        for state in everyComparisonState {
            switch RootView.comparisonPresentation(for: state) {
            case .none: reachingTheOverview += 1
            case .loading, .ready, .failed: reachingTheComparison += 1
            }
        }
        #expect(reachingTheOverview == 1, "the overview is reached for a window that has a comparison")
        #expect(reachingTheComparison == 3, "a comparison state no longer reaches the comparison")
    }

    /// A pair that has settled its drawings is still a comparison, so it still reaches the page — the
    /// distinction the split deliberately does **not** make.
    @Test("a settled pair reaches the comparison, not the overview")
    func aSettledPairReachesTheComparison() {
        let ready = ImportFlowModel.ComparisonState.ready(
            FileComparison(first: report("a.wav"), second: report("b.wav")), nil, nil
        )
        #expect(RootView.comparisonPresentation(for: ready) != .none)
        // And the visuals for that same state are *not* a pair yet, which is why splitting on them
        // would have dropped the comparison's loading and failure states.
        #expect(RootView.reportVisuals(
            for: InspectionPresentation(report: report("a.wav"), waveform: .unavailable), in: ready
        ) == .single(waveform: .absent, spectrogram: .loading))
    }

    /// **Closing a comparison returns the reader to the real Inspection Overview.** `dismissComparison()`
    /// puts the flow back to `.none`, and `.none` is the one case that routes to the new surface — so the
    /// round trip in and out of comparison mode ends where it began. That the flow reaches `.none` by
    /// this route is R1's `WorkspaceNavigationLifecycleTests`' claim; what belongs here is that `.none`
    /// routes to the overview.
    @MainActor
    @Test("closing a comparison routes back to the inspection overview")
    func closingAComparisonReturnsToTheOverview() {
        let flow = ImportFlowModel(action: { _ in .cancelled })
        flow.dismissComparison()
        #expect(flow.comparison == .none)
        #expect(RootView.comparisonPresentation(for: flow.comparison) == .none,
                "a closed comparison no longer routes to the overview")
    }

    /// **R7 builds no comparison surface of its own.** The Comparison Overview is R8's, gated by a
    /// vocabulary sweep R7 does not run, so the new surface must not name a comparison at all — not a
    /// type, not a difference, not a phrase meaning the two files match, not an aggregate over them.
    @Test("the overview surface names no comparison, difference, match or aggregate")
    func theOverviewBuildsNoComparisonSurface() throws {
        let overview = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis/InspectionOverviewView.swift")
        let source = try String(contentsOf: overview, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
        for absent in ["ComparisonView", "ComparisonPresentation", "FileComparison",
                       "MeasurementComparison", "PairedVisuals", "ComparisonCopy",
                       "differences", "differ", "similarity", "match", "same", "score", "percentage"] {
            #expect(!source.contains { $0.localizedCaseInsensitiveContains(absent) },
                    "the overview names \(absent)")
        }
        // And the root hands it no comparison: its initialiser takes the report, the drawing and the
        // four measurements, and nothing about a second file.
        let branch = try overviewBranch()
        let call = branch.drop { !$0.contains("InspectionOverviewView(") }.prefix { !$0.contains(")") }
        #expect(!call.contains { $0.localizedCaseInsensitiveContains("comparison") },
                "the overview is handed a comparison")
    }

    // MARK: - 4.8 — nothing beneath this slice changed

    /// The export survives the page's removal, where the hotfix put it: above the section routing, once,
    /// and reachable whatever the comparison is doing.
    @Test("the export is still attached above the routing")
    func theExportSurvives() throws {
        let code = try code()
        let attach = try #require(code.firstIndex { $0.contains(".reportExportToolbar(") })
        let routing = try #require(code.firstIndex { $0.contains("switch navigation.section") })
        #expect(attach < routing)
        #expect(code.filter { $0.contains(".reportExportToolbar(") }.count == 1)
    }

    /// **No new navigation.** The section is still chosen by the value R1 owns, and no content on the
    /// overview moves the reader.
    @Test("giving the overview content introduces no navigation machinery")
    func noNavigationMachineryIsIntroduced() throws {
        let code = try code()
        for machinery in ["NavigationStack", "NavigationSplitView", "NavigationLink", "NavigationPath",
                          "TabView", "NavigationView"] {
            #expect(!code.contains { $0.contains(machinery) }, "the root introduces \(machinery)")
        }
        #expect(code.filter { $0.contains("navigation.section") }.count == 2,
                "the section is read from more places than the picker and the routing")
        // Nothing below the composition root learns which section is selected.
        #expect(!code.contains { $0.contains("InspectionOverviewView(section") })
    }

    /// R1's five sections, in R1's order, and R2–R6's surfaces still routed to their own sections.
    @Test("the workspace and the earlier slices are unchanged")
    func theEarlierSlicesAreUnchanged() throws {
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
        let code = try code()
        #expect(code.contains { $0.contains("ReportDetailsView(report: presentation.report") })
        let waveform = "ReportWaveformView(visuals: Self.reportVisuals(for: presentation, in: flowComparison))"
        #expect(code.contains { $0.contains(waveform) })
        let spectrum = "ReportSpectrumView(visuals: Self.reportVisuals(for: presentation, in: flowComparison))"
        #expect(code.contains { $0.contains(spectrum) })
    }
}
