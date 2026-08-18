import Testing

import AudioInspectorDomain
@testable import FeatureImport

/// Tests the import flow's observable state, driven by an injected action — no panel, no filesystem,
/// no SwiftUI. Reports are plain in-memory values.
@MainActor
@Suite("Feature — import flow model")
struct ImportFlowModelTests {

    /// A scripted action returning a fixed outcome, counting invocations.
    @MainActor
    final class ScriptedAction {
        private(set) var callCount = 0
        private let outcome: SourceInspectionOutcome
        init(_ outcome: SourceInspectionOutcome) { self.outcome = outcome }
        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            callCount += 1
            return outcome
        }
    }

    /// An action that suspends until released — to observe the in-flight state.
    @MainActor
    final class ControllableAction {
        private(set) var callCount = 0
        private var continuation: CheckedContinuation<SourceInspectionOutcome, Never>?
        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            callCount += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ outcome: SourceInspectionOutcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }

    /// An action returning a different report on each call — for consecutive selections.
    @MainActor
    final class SequenceAction {
        private var outcomes: [SourceInspectionOutcome]
        init(_ outcomes: [SourceInspectionOutcome]) { self.outcomes = outcomes }
        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome { outcomes.removeFirst() }
    }

    private func makeReport(named name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 1_024,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(sampleRate: .available(44_100)),
            warnings: [],
            status: .completed
        )
    }

    // MARK: - Success

    @Test func startsIdle() {
        #expect(ImportFlowModel(action: ScriptedAction(.cancelled).run).state == .idle)
    }

    @Test func inspectedOutcomeBecomesTheReportStateAndRunsTheActionOnce() async {
        let report = makeReport(named: "clip.wav")
        let action = ScriptedAction(.inspected(report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        let model = ImportFlowModel(action: action.run)

        await model.selectAndInspect()

        #expect(model.state == .report(InspectionPresentation(report: report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))
        #expect(action.callCount == 1)
    }

    // MARK: - Cancellation (neutral, no error)

    @Test func cancellingFromIdleReturnsToIdle() async {
        let model = ImportFlowModel(action: ScriptedAction(.cancelled).run)

        await model.selectAndInspect()

        #expect(model.state == .idle) // no error surfaced
    }

    @Test func cancellingAfterAReportKeepsThePreviousReport() async {
        let first = makeReport(named: "first.wav")
        let sequence = SequenceAction([.inspected(first, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable), .cancelled])
        let model = ImportFlowModel(action: sequence.run)

        await model.selectAndInspect()
        #expect(model.state == .report(InspectionPresentation(report: first, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))

        await model.selectAndInspect() // user opens the panel again and cancels
        #expect(model.state == .report(InspectionPresentation(report: first, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))) // exactly where they were, no error
    }

    // MARK: - Preparation failure (before any inspection)

    @Test func preparationFailureBecomesARecoverableMessage() async {
        let model = ImportFlowModel(action: ScriptedAction(.preparationFailed).run)

        await model.selectAndInspect()

        #expect(model.state == .failed(message: "That file could not be opened for inspection."))
    }

    // MARK: - A global inspection failure is still a report

    @Test func aFailedReportIsPresentedAsAReportNotAsAFlowError() async {
        let error = InspectionError(code: .fileOpenFailed, message: "could not open")
        let failedReport = InspectionReport(
            file: AudioFileReference(
                displayName: "broken.wav",
                fileExtension: "wav",
                sizeBytes: nil,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: "broken.wav", locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(error)
        )
        let model = ImportFlowModel(action: ScriptedAction(.inspected(failedReport, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)).run)

        await model.selectAndInspect()

        // The domain already models this; the flow must not convert it into its own `failed` state.
        #expect(model.state == .report(InspectionPresentation(report: failedReport, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))
    }

    // MARK: - Re-entrancy

    @Test func aSecondSelectionIsIgnoredWhileOneIsInFlight() async {
        let action = ControllableAction()
        let model = ImportFlowModel(action: action.run)
        let report = makeReport(named: "clip.wav")

        let first = Task { await model.selectAndInspect() }
        while action.callCount == 0 { await Task.yield() }

        #expect(model.state == .working)

        await model.selectAndInspect() // ignored while working
        #expect(action.callCount == 1)

        action.finish(.inspected(report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await first.value
        #expect(model.state == .report(InspectionPresentation(report: report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))
    }

    // MARK: - Consecutive selections

    @Test func aSecondSelectionReplacesThePreviousReport() async {
        let first = makeReport(named: "first.wav")
        let second = makeReport(named: "second.wav")
        let model = ImportFlowModel(action: SequenceAction([.inspected(first, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable), .inspected(second, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)]).run)

        await model.selectAndInspect()
        #expect(model.state == .report(InspectionPresentation(report: first, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))

        await model.selectAndInspect()
        #expect(model.state == .report(InspectionPresentation(report: second, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))
    }

    @Test func selectingAgainAfterAPreparationFailureCanSucceed() async {
        let report = makeReport(named: "clip.wav")
        let model = ImportFlowModel(action: SequenceAction([.preparationFailed, .inspected(report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)]).run)

        await model.selectAndInspect()
        #expect(model.state == .failed(message: "That file could not be opened for inspection."))

        await model.selectAndInspect()
        #expect(model.state == .report(InspectionPresentation(report: report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable)))
    }
}
