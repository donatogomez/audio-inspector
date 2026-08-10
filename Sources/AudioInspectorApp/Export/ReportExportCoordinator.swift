import AudioInspectorDomain
import FeatureAnalysis
import Foundation

/// Orchestrates a single export: suggest a name → ask for a destination → (if not cancelled) encode
/// with the existing `ReportExporting` → write the bytes atomically → report the outcome. It reuses
/// the consolidated JSON v1 exporter **without changing its semantics**, and never recalculates the
/// report, touches Domain, persists a destination, creates a bookmark, or uses `FileManager` in
/// production.
///
/// The destination selection is an injected seam (`DestinationProvider`) so unit tests substitute a
/// known temporary URL for the real `NSSavePanel`.
@MainActor
struct ReportExportCoordinator {
    /// Returns a chosen destination URL, or `nil` when the user cancels.
    typealias DestinationProvider = @MainActor (_ suggestedName: String) async -> URL?

    private let exporter: any ReportExporting
    private let chooseDestination: DestinationProvider

    init(exporter: any ReportExporting, chooseDestination: @escaping DestinationProvider) {
        self.exporter = exporter
        self.chooseDestination = chooseDestination
    }

    func export(_ report: InspectionReport, signalLevelMetrics: SignalLevelMetrics?) async -> ExportOutcome {
        let suggestedName = SuggestedExportName.forReport(report)

        // Ask for the destination first: on cancellation, nothing is encoded or written.
        guard let destination = await chooseDestination(suggestedName) else {
            return .cancelled
        }

        let data: Data
        do {
            data = try exporter.export(report, signalLevelMetrics: signalLevelMetrics)
        } catch {
            return .encodingFailed // encoding failure is distinct from a write failure
        }

        do {
            try data.write(to: destination, options: [.atomic]) // one-shot, atomic; no FileManager
        } catch {
            return .writeFailed
        }

        return .succeeded
    }
}
