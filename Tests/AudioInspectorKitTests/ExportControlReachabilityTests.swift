import Foundation
import Testing

@testable import AudioInspectorApp

// **The gap that let the export disappear.** Every existing export suite asserts the *document*: its
// contents, its schema, its isolation from the comparison. Not one asserted that a reader could reach
// the action at all — so when the redesign moved `ReportView` out of the single-file surface, the
// control left with it and every test stayed green.
//
// These read the composition root, where the control is now attached, and hold the property those
// suites could not: **a window that has a report can export it, from wherever the reader is standing.**

@Suite("App — the export action is reachable")
struct ExportControlReachabilityTests {

    private func code(of path: String) throws -> [String] {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(path),
            encoding: .utf8
        )
        .components(separatedBy: .newlines)
        .filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
        }
    }

    private func root() throws -> [String] { try code(of: "Sources/AudioInspectorApp/RootView.swift") }

    /// **Attached to the surface, not to a section.** `reportSurface` is the one place that exists
    /// exactly when a report does, so the control is reachable from all five sections and in every
    /// comparison state — and it is applied once, so it neither multiplies nor vanishes with any of them.
    @Test("the export is attached to the report surface itself")
    func theExportIsAttachedToTheSurface() throws {
        let root = try root()
        #expect(root.contains { $0.contains(".reportExportToolbar(") },
                "the composition root attaches no export action")
        #expect(root.filter { $0.contains(".reportExportToolbar(") }.count == 1,
                "the export is attached more than once")

        // It is applied to the surface, not inside the section switch — otherwise it would be reachable
        // from one section and not the others, which is the defect this suite exists for.
        let attach = try #require(root.firstIndex { $0.contains(".reportExportToolbar(") })
        let sectionSwitch = try #require(root.firstIndex { $0.contains("switch navigation.section") })
        #expect(attach < sectionSwitch, "the export is attached inside the section routing")
    }

    /// The action is handed the same values the export payload has always been built from, so moving the
    /// control cannot change the document.
    @Test("the export is handed the report and all four measurements")
    func theExportIsHandedThePayloadsInputs() throws {
        let root = try root()
        for input in ["report: presentation.report",
                      "signalLevelMetricsPresentation(for: presentation.signalLevelMetrics)",
                      "truePeakPresentation(for: presentation.truePeak)",
                      "loudnessPresentation(for: presentation.loudness)",
                      "programmeBandwidthPresentation(for: presentation.significantBandwidth)",
                      "export: export"] {
            #expect(root.contains { $0.contains(input) }, "the export action is not handed \(input)")
        }
    }

    /// **Exactly one owner of the window's toolbar.** Two would put two Export buttons on screen while a
    /// comparison is open, which is how a "restore the control" fix quietly becomes a duplicate.
    @Test("exactly one production toolbar attaches the export")
    func exactlyOneToolbarOwner() throws {
        let feature = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: feature, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var owners: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains(".toolbar") { owners.append(file.lastPathComponent) }
            }
        }
        #expect(owners == ["ReportExportToolbar.swift"], "the toolbar is attached by \(owners)")
    }

    /// **No section carries an export of its own.** The hotfix took it out of the report page; R8 then
    /// removed that page entirely, so the property is now asserted where it has to hold — over every
    /// surface a reader can be looking at.
    @Test("no section carries an export of its own")
    func noSectionCarriesAnExport() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/FeatureAnalysis/ReportView.swift").path),
            "the transitional report page is back"
        )
        for section in ["InspectionOverviewView", "ComparisonOverviewView", "ReportDetailsView",
                        "ReportMeasurementsView", "ReportWaveformView", "ReportSpectrumView"] {
            let source = try code(of: "Sources/FeatureAnalysis/\(section).swift")
            for residue in ["Export JSON", "ReportExportModel", "ReportExportAction", "exportModel",
                            ".toolbar"] {
                #expect(!source.contains { $0.contains(residue) }, "\(section) carries \(residue)")
            }
        }
    }
}
