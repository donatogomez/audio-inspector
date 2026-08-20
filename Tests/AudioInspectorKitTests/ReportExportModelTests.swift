import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

/// Tests for the Feature's transient export state. No SwiftUI, no snapshots — only the observable
/// phase transitions driven by an injected action. The report is a plain in-memory value.
@MainActor
@Suite("Feature — report export model")
struct ReportExportModelTests {

    /// A scripted export action that returns a fixed outcome and counts invocations.
    @MainActor
    final class CountingAction {
        private(set) var callCount = 0
        private let outcome: ExportOutcome
        init(_ outcome: ExportOutcome) { self.outcome = outcome }
        func run(
            _: InspectionReport, _: ReportMeasurements
        ) async -> ExportOutcome {
            callCount += 1
            return outcome
        }
    }

    /// An export action that suspends until the test releases it — to observe the in-flight phase.
    @MainActor
    final class ControllableAction {
        private(set) var callCount = 0
        private var continuation: CheckedContinuation<ExportOutcome, Never>?
        func run(
            _: InspectionReport, _: ReportMeasurements
        ) async -> ExportOutcome {
            callCount += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ outcome: ExportOutcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }

    private let sample = report(status: .completed)

    @Test func successMapsToSucceededAndInvokesActionOnce() async {
        let action = CountingAction(.succeeded)
        let model = ReportExportModel(action: action.run)

        await model.export(sample, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil))

        #expect(model.phase == .succeeded)
        #expect(action.callCount == 1)
    }

    @Test func cancellationReturnsToIdle() async {
        let model = ReportExportModel(action: CountingAction(.cancelled).run)
        await model.export(sample, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil))
        #expect(model.phase == .idle) // cancellation is NOT an error
    }

    @Test func encodingFailureBecomesPresentableMessage() async {
        let model = ReportExportModel(action: CountingAction(.encodingFailed).run)
        await model.export(sample, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil))
        #expect(model.phase == .failed(message: "The report could not be encoded."))
    }

    @Test func writeFailureBecomesPresentableMessage() async {
        let model = ReportExportModel(action: CountingAction(.writeFailed).run)
        await model.export(sample, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil))
        #expect(model.phase == .failed(message: "The file could not be written."))
    }

    @Test func duplicateExportIsPreventedWhileExporting() async {
        let action = ControllableAction()
        let model = ReportExportModel(action: action.run)

        let first = Task { await model.export(sample, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil)) }
        while action.callCount == 0 { await Task.yield() } // wait until the action is in flight

        #expect(model.phase == .exporting)

        await model.export(sample, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil)) // second call while exporting → ignored (no re-invocation)
        #expect(action.callCount == 1)

        action.finish(.succeeded)
        await first.value
        #expect(model.phase == .succeeded)
    }
}
