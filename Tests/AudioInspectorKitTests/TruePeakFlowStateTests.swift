import AudioInspectorDomain
import FeatureImport
import Foundation
import Testing

// True peak as flow state, at the `ImportFlowModel` layer: that it reaches the surface in each of its
// states, that it disturbs nothing beside it, and that a superseded operation's result cannot land on
// the file the user is now looking at.
//
// Scoped deliberately. The general progressive-delivery mechanism is already pinned by the waveform's,
// the spectrogram's and the signal levels' own flow-state suites; what is new here is that a **fourth**
// analysis travels beside the other three without any of them being disturbed — which is the property
// the shared read makes worth re-checking, since three of the four now settle from one decode.
//
// Every sequence is driven by explicit signals on a scripted action. No sleeps, no polling, no
// assumption about the order two tasks are scheduled in.

/// An action whose updates are released by the test, one at a time.
@MainActor
private final class SteppedTruePeakAction {
    let report: InspectionReport
    private var pending: [InspectionUpdate] = []
    private var pendingOutcome: SourceInspectionOutcome?
    private var gate: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private(set) var runCount = 0

    init(report: InspectionReport) { self.report = report }

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
    func deliver(truePeak: TruePeakOutcome) { release(.truePeak(truePeak)) }
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
@Suite("Feature — true peak flow state")
struct TruePeakFlowStateTests {
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

    private func measurement(_ peak: Float = 0.5) throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 100, truePeak: peak))
        return try #require(TruePeakMeasurement(channels: [channel], method: method))
    }

    private func metrics() throws -> SignalLevelMetrics {
        let channel1 = try #require(SignalLevelMetrics.Channel(sampleCount: 100, peakSample: 0.5, rms: 0.2, dcOffset: 0, clippedSampleCount: 0))
        return try #require(SignalLevelMetrics(
            channels: [channel1],
            overallPeakSample: 0.5, overallRMS: 0.2, overallDCOffset: 0, overallClippedSampleCount: 0
        ))
    }

    private func presentation(of model: ImportFlowModel) -> InspectionPresentation? {
        guard case let .report(presentation) = model.state else { return nil }
        return presentation
    }

    // MARK: Loading never clears or blocks the report

    /// The report appears while the true peak is still loading, exactly as it does for the three
    /// analyses before it.
    @Test("the report appears while the true peak is still loading")
    func theReportDoesNotWaitForTheTruePeak() async throws {
        let action = SteppedTruePeakAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.report == action.report)
        #expect(shown.truePeak == .loading, "the report was withheld or the state fabricated")

        action.finish(.inspected(
            action.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .unavailable, truePeak: .unavailable
        ))
        await running.value
    }

    // MARK: Settling — each state reaches the surface as itself

    @Test("an available measurement replaces loading without touching anything beside it")
    func availableSettlesWithoutDisturbingItsNeighbours() async throws {
        let action = SteppedTruePeakAction(report: report())
        let model = ImportFlowModel(action: action.run)
        let measured = try measurement(1.1)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        // The signal levels settle first, so the assertion below is about a neighbour that is really
        // there rather than one that was still loading anyway.
        action.deliver(signalLevelMetrics: .available(try metrics()))
        await Task.yield()
        action.deliver(truePeak: .available(measured))
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.truePeak == .available(measured))
        #expect(shown.report == action.report, "the report changed when the true peak settled")
        #expect(shown.signalLevelMetrics == .available(try metrics()), "a settled neighbour was disturbed")
        #expect(shown.waveform == .loading)
        #expect(shown.spectrogram == .loading)

        action.finish(.inspected(
            action.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .available(try metrics()), truePeak: .available(measured)
        ))
        await running.value
    }

    @Test("an absent measurement is shown as an absence, not as a failure")
    func absentSettlesAsItself() async throws {
        let action = SteppedTruePeakAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        action.deliver(truePeak: .unavailable)
        await Task.yield()

        #expect(try #require(presentation(of: model)).truePeak == .unavailable)

        action.finish(.inspected(
            action.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .unavailable, truePeak: .unavailable
        ))
        await running.value
    }

    /// A failed measurement carries **its own** message to the surface and degrades nothing else — not
    /// the report's status, not its warnings, not a neighbouring analysis.
    @Test("a failed measurement never degrades the report or its neighbours")
    func failedNeverDegradesAnythingElse() async throws {
        let action = SteppedTruePeakAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        action.deliver(signalLevelMetrics: .available(try metrics()))
        await Task.yield()
        action.deliver(truePeak: .failed(message: "The true peak for this file could not be measured."))
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.truePeak == .failed(message: "The true peak for this file could not be measured."))
        #expect(shown.report.status == .completed, "a failed measurement degraded the inspection status")
        #expect(shown.report.warnings.isEmpty, "a failed measurement added a warning to the report")
        #expect(shown.signalLevelMetrics == .available(try metrics()))

        action.finish(.inspected(
            action.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .available(try metrics()),
            truePeak: .failed(message: "The true peak for this file could not be measured.")
        ))
        await running.value
    }

    /// Cancellation leaves the state untouched rather than showing an absence: a cancelled operation is
    /// the user replacing something, and it says nothing whatever about the file.
    @Test("a cancelled measurement leaves the state untouched rather than showing an absence")
    func cancelledLeavesTheStateUntouched() async throws {
        let action = SteppedTruePeakAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        action.deliverReport()
        await Task.yield()
        action.deliver(truePeak: .cancelled)
        await Task.yield()

        #expect(try #require(presentation(of: model)).truePeak == .loading, "a cancellation was shown as a state")

        action.finish(.inspected(
            action.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .unavailable, truePeak: .unavailable
        ))
        await running.value
    }

    /// **A late result from a replaced operation must not land on the file now on screen.** The measured
    /// value would look entirely plausible there, which is exactly why it has to be dropped.
    @Test("a late true peak from a replaced operation is discarded")
    func aLateResultFromASupersededOperationIsDiscarded() async throws {
        let first = SteppedTruePeakAction(report: report(named: "first"))
        let second = SteppedTruePeakAction(report: report(named: "second"))
        let actions = SequencedActions([first, second])
        let model = ImportFlowModel(action: actions.run)

        let firstRun = Task { await model.selectAndInspect() }
        await first.waitUntilStarted()
        first.deliverReport()
        await Task.yield()

        // The user picks another file before the first inspection's true peak has settled.
        let secondRun = Task { await model.selectAndInspect() }
        await second.waitUntilStarted()
        second.deliverReport()
        await Task.yield()

        // The superseded operation now answers.
        first.deliver(truePeak: .available(try measurement(0.9)))
        await Task.yield()

        let shown = try #require(presentation(of: model))
        #expect(shown.report == second.report, "the superseded operation replaced the file on screen")
        #expect(shown.truePeak == .loading, "a stale true peak landed on the current file")

        first.finish(.inspected(
            first.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .unavailable, truePeak: .unavailable
        ))
        second.finish(.inspected(
            second.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .unavailable, truePeak: .unavailable
        ))
        _ = await firstRun.value
        _ = await secondRun.value
    }
}

/// Hands each `selectAndInspect` to the next scripted action in order.
@MainActor
private final class SequencedActions {
    private var remaining: [SteppedTruePeakAction]

    init(_ actions: [SteppedTruePeakAction]) { remaining = actions }

    func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        guard !remaining.isEmpty else { return .cancelled }
        return await remaining.removeFirst().run(onUpdate)
    }
}
