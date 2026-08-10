import AudioInspectorDomain
import FeatureImport
import Foundation
import Testing

// Signal level metrics as flow state, at the `ImportFlowModel` layer: how it settles without disturbing
// the report, and how a superseded operation's result is kept from landing on the file the user is now
// looking at. Mirrors `SpectrogramFlowStateTests`, scoped to what group 5 actually added — the general
// progressive-delivery mechanism is already pinned there and is not re-proven wholesale here.
//
// Every sequence here is driven by explicit signals on a scripted action. No sleeps, no polling, no
// assumption about the order two tasks are scheduled in.

/// An action whose report and signal level metrics are released by the test, one at a time.
@MainActor
private final class SteppedAction {
    let report: InspectionReport
    private var pending: [InspectionUpdate] = []
    private var pendingOutcome: SourceInspectionOutcome?
    private var gate: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private(set) var runCount = 0

    init(report: InspectionReport) {
        self.report = report
    }

    func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        runCount += 1
        startContinuation?.resume()
        startContinuation = nil

        while true {
            while !pending.isEmpty {
                onUpdate(pending.removeFirst())
            }
            if let outcome = pendingOutcome {
                pendingOutcome = nil
                return outcome
            }
            await withCheckedContinuation { gate = $0 }
        }
    }

    func waitUntilStarted() async {
        guard runCount == 0 else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func deliverReport() { release(.report(report)) }
    func deliver(signalLevelMetrics: SignalLevelMetricsOutcome) { release(.signalLevelMetrics(signalLevelMetrics)) }

    private func release(_ update: InspectionUpdate) {
        pending.append(update)
        gate?.resume()
        gate = nil
    }

    func finish(_ outcome: SourceInspectionOutcome) {
        pendingOutcome = outcome
        gate?.resume()
        gate = nil
    }
}

@MainActor
@Suite("Feature — signal level metrics flow state")
struct SignalLevelMetricsFlowStateTests {
    private func report(named name: String = "fixture") -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .completed
        )
    }

    private func metrics() -> SignalLevelMetrics {
        SignalLevelMetrics(
            channels: [SignalLevelMetrics.Channel(sampleCount: 100, peakSample: 0.5, rms: 0.2, dcOffset: 0, clippedSampleCount: 0)],
            overallPeakSample: 0.5, overallRMS: 0.2, overallDCOffset: 0, overallClippedSampleCount: 0
        )
    }

    private func presentation(of model: ImportFlowModel) -> InspectionPresentation? {
        guard case let .report(presentation) = model.state else { return nil }
        return presentation
    }

    // MARK: Loading never clears or blocks the report

    /// The report appears while signal level metrics are still loading, exactly as it does for the
    /// waveform and the spectrogram. Loading is never mistaken for an absence of a report.
    @Test("the report appears while signal level metrics are still loading")
    func theReportDoesNotWaitForSignalLevelMetrics() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.report == action.report)
        #expect(shown.signalLevelMetrics == .loading, "the report was withheld or the state fabricated")

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await running.value
    }

    // MARK: Settling

    @Test("an available reading replaces loading without touching the report")
    func availableSettlesWithoutTouchingTheReport() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)
        let measured = metrics()

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        action.deliver(signalLevelMetrics: .available(measured))
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.signalLevelMetrics == .available(measured))
        #expect(shown.report.status == .completed, "the report was disturbed")

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .available(measured)))
        await running.value
    }

    /// A failure to measure must not degrade the inspection's own status — it is a limit of measuring,
    /// never a finding about the file (ADR-0016 decision 14, ADR-0018).
    @Test("a failed reading never degrades the inspection status")
    func aFailedReadingNeverDegradesStatus() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        action.deliver(signalLevelMetrics: .failed(message: "boom"))
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.signalLevelMetrics == .failed(message: "boom"))
        #expect(shown.report.status == .completed, "a measurement failure degraded the inspection")

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .failed(message: "boom")))
        await running.value
    }

    /// Cancellation has no visible state: a result belonging to an operation the user replaced is
    /// discarded, never rendered as an absence.
    @Test("a cancelled reading leaves the state untouched rather than showing an absence")
    func cancelledIsNotVisible() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        action.deliver(signalLevelMetrics: .cancelled)
        await Task.yield()

        #expect(presentation(of: model)?.signalLevelMetrics == .loading, "cancellation was rendered as a state")
        #expect(SignalLevelMetricsState(.cancelled) == nil)

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .cancelled))
        await running.value
    }

    // MARK: A superseded operation cannot land on the current one

    @Test("a late signal level metrics result from a replaced operation is discarded")
    func aStaleResultIsDropped() async throws {
        let first = SteppedAction(report: report(named: "first"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        await first.waitUntilStarted()
        first.deliverReport()
        await Task.yield()
        #expect(presentation(of: model)?.report.file.displayName == "first")

        // The user picks another file while the first's signal level metrics are still pending.
        let second = SteppedAction(report: report(named: "second"))
        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        second.deliverReport()
        await Task.yield()
        #expect(presentation(of: model)?.report.file.displayName == "second")

        // The first operation now finishes, late. Nothing of it may reach the second's presentation.
        first.deliver(signalLevelMetrics: .available(metrics()))
        await Task.yield()
        first.finish(.inspected(first.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .available(metrics())))
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.report.file.displayName == "second", "a stale operation replaced the current report")
        #expect(shown.signalLevelMetrics == .loading, "a stale reading landed on the current operation")

        second.finish(.inspected(second.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await secondRun.value
        await firstRun.value
    }
}
