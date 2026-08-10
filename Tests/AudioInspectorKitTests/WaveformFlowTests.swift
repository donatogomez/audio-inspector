import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import CryptoKit
import FeatureImport
import Foundation
import Testing

// The wiring: one security-scoped window covering both reads, a report that appears before the
// waveform, and a newer selection that supersedes an older one without ever showing an error for it.
//
// Deterministic throughout — the scripted actions here settle exactly when the test says so, using
// continuations rather than sleeps or polling.

// MARK: - Scripted actions

/// An action that hands back a report on demand and finishes only when told to, so a test can observe
/// the window in which the report is visible and the waveform is still loading.
@MainActor
private final class SuspendedAction {
    private var deliverContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<SourceInspectionOutcome, Never>?
    /// Requests that arrived before the action reached the matching suspension point. Recorded rather
    /// than dropped, so a test never depends on how many scheduling hops it takes to get there.
    private var pendingDeliver = false
    private var pendingOutcome: SourceInspectionOutcome?

    private(set) var callCount = 0
    private(set) var cancellationsObserved = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?

    let report: InspectionReport
    /// Whether being cancelled should settle the call. `false` lets a test hold a superseded operation
    /// open and choose exactly what it eventually returns.
    private let finishesOnCancellation: Bool

    init(report: InspectionReport, finishesOnCancellation: Bool = true) {
        self.report = report
        self.finishesOnCancellation = finishesOnCancellation
    }

    /// Waits to be told to deliver the report, hands it over, then waits again for the outcome — so a
    /// test controls both moments without a sleep and without polling.
    ///
    /// The handler is used strictly within the call: it is not `@escaping`, and nothing here needs it
    /// to be, which keeps the production contract as tight as it is.
    func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        callCount += 1
        startContinuation?.resume()
        startContinuation = nil

        if !pendingDeliver {
            await withCheckedContinuation { deliverContinuation = $0 }
        }
        pendingDeliver = false
        onUpdate(.report(report))

        if let pendingOutcome {
            self.pendingOutcome = nil
            return pendingOutcome
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { finishContinuation = $0 }
        } onCancel: {
            Task { @MainActor in self.observeCancellation() }
        }
    }

    /// Suspends until this action has actually been invoked, so a test never has to guess how many
    /// scheduling hops that takes.
    func waitUntilStarted() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    /// Suspends until this action has observed its cancellation.
    func waitUntilCancelled() async {
        guard cancellationsObserved == 0 else { return }
        await withCheckedContinuation { cancellationContinuation = $0 }
    }

    private func observeCancellation() {
        cancellationsObserved += 1
        cancellationContinuation?.resume()
        cancellationContinuation = nil
        if finishesOnCancellation {
            finish(.inspected(report, waveform: .cancelled, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        }
    }

    /// Releases the report, leaving the waveform still in flight.
    func deliverReport() {
        guard let continuation = deliverContinuation else {
            pendingDeliver = true
            return
        }
        deliverContinuation = nil
        continuation.resume()
    }

    func finish(_ outcome: SourceInspectionOutcome) {
        guard let continuation = finishContinuation else {
            pendingOutcome = outcome
            return
        }
        finishContinuation = nil
        continuation.resume(returning: outcome)
    }
}

// MARK: - Coordinator

@MainActor
@Suite("App — waveform coordination")
struct WaveformCoordinationTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func sha256(of url: URL) throws -> SHA256Digest {
        try SHA256.hash(data: Data(contentsOf: url))
    }

    @Test("a real file yields a report and an available waveform from one selection")
    func realFileProducesBoth() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "wired", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 44_100),
                in: directory
            )
            let coordinator = SourceInspectionCoordinator()

            var delivered: InspectionReport?
            let outcome = await coordinator.inspect(url, onUpdate: { if case let .report(report) = $0 { delivered = report } })

            guard case let .inspected(report, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome, got \(outcome)"); return
            }
            #expect(delivered == report, "the report handed back early is the one in the outcome")
            guard case let .available(envelope) = waveform else {
                Issue.record("expected an available waveform, got \(waveform)"); return
            }
            #expect(envelope.frameCount == 44_100)
            #expect(envelope.channelCount == 2)
        }
    }

    @Test("a waveform that is absent leaves the report exactly as it was")
    func absentWaveformKeepsTheReport() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "absent", format: .wav, signal: .silence, frames: 4_410),
                in: directory
            )
            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in FakeWaveformGenerating(.absent) }
            )

            let outcome = await coordinator.inspect(url, onUpdate: { _ in })

            guard case let .inspected(report, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(waveform == .unavailable)
            #expect(report.properties.sampleRate == .available(44_100), "the properties are untouched")
        }
    }

    @Test("a waveform failure is neutral: the report survives and carries no framework text")
    func failedWaveformIsNeutral() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "failing", format: .wav, signal: .silence, frames: 4_410),
                in: directory
            )
            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in
                    FakeWaveformGenerating(failingWith: WaveformError(code: .readFailed, message: "internal"))
                }
            )

            let outcome = await coordinator.inspect(url, onUpdate: { _ in })

            guard case let .inspected(report, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            guard case let .failed(message) = waveform else {
                Issue.record("expected a failed waveform, got \(waveform)"); return
            }
            #expect(!message.contains("/"), "no path reaches the message")
            #expect(!message.lowercased().contains("avaudio"), "no framework name reaches the message")
            #expect(!message.contains("waveform_"), "no stable code reaches the message")
            if case .failed = report.status {
                Issue.record("a waveform failure must not turn the report into a global failure")
            }
        }
    }

    @Test("a cancelled generation is reported as cancellation, never as a limitation of the file")
    func cancelledWaveformIsItsOwnOutcome() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "cancelled", format: .wav, signal: .silence, frames: 4_410),
                in: directory
            )
            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in
                    FakeWaveformGenerating(failingWith: WaveformError(code: .cancelled, message: "Cancelled."))
                }
            )

            let outcome = await coordinator.inspect(url, onUpdate: { _ in })

            guard case let .inspected(_, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(waveform == .cancelled)
            #expect(waveform != .unavailable, "cancellation must not be dressed up as an absence")
        }
    }

    @Test("a global inspection failure skips the sample read entirely")
    func globalFailureSkipsTheWaveform() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("not-audio.wav")
            try Data("definitely not audio".utf8).write(to: url)

            let generator = FakeWaveformGenerating(.absent)
            let coordinator = SourceInspectionCoordinator(makeWaveformGenerator: { _ in generator })

            let outcome = await coordinator.inspect(url, onUpdate: { _ in })

            guard case let .inspected(report, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            guard case .failed = report.status else {
                Issue.record("expected a globally failed report"); return
            }
            #expect(waveform == .unavailable)
            #expect(await generator.callCount == 0, "no samples are read when nothing could be read at all")
        }
    }

    @Test("the generator receives the same safe reference the use case did")
    func generatorReceivesTheSameReference() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "same-reference", format: .wav, signal: .silence, frames: 4_410),
                in: directory
            )
            let generator = FakeWaveformGenerating(.absent)
            let coordinator = SourceInspectionCoordinator(makeWaveformGenerator: { _ in generator })

            var delivered: InspectionReport?
            _ = await coordinator.inspect(url, onUpdate: { if case let .report(report) = $0 { delivered = report } })

            #expect(await generator.callCount == 1)
            #expect(await generator.lastFile == delivered?.file, "one reference, one operation")
        }
    }

    /// The window has to cover the samples, not just the properties: the generator runs *inside* the
    /// coordinator's `defer`, so anything it needs is still accessible when it runs.
    @Test("the security-scoped window is still open while the waveform is generated")
    func scopeCoversTheWaveform() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "scope", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 8_820),
                in: directory
            )
            // The real generator opens the file itself. If the coordinator had released access before
            // reaching it — or opened a second scope of its own — this could not come back available.
            let coordinator = SourceInspectionCoordinator()

            let outcome = await coordinator.inspect(url, onUpdate: { _ in })

            guard case let .inspected(_, waveform, _, _) = outcome, case .available = waveform else {
                Issue.record("expected an available waveform, got \(outcome)"); return
            }
        }
    }

    @Test("the source file is byte-identical after a full selection")
    func sourceIsUnchanged() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "untouched", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 44_100),
                in: directory
            )
            let before = try sha256(of: url)

            _ = await SourceInspectionCoordinator().inspect(url, onUpdate: { _ in })

            #expect(try sha256(of: url) == before)
        }
    }
}

// MARK: - Flow model

@MainActor
@Suite("Feature — waveform flow state")
struct WaveformFlowStateTests {
    private func report(named name: String = "fixture") -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 1, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .completed
        )
    }

    private func envelope() -> WaveformEnvelope {
        WaveformEnvelope.empty(channelCount: 2)!
    }

    @Test("the report appears while the waveform is still loading")
    func reportAppearsBeforeTheWaveform() async throws {
        let action = SuspendedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await Task.yield()
        action.deliverReport()
        await Task.yield()

        #expect(model.state == .report(InspectionPresentation(report: action.report, waveform: .loading)))

        action.finish(.inspected(action.report, waveform: .available(envelope()), spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await running.value

        #expect(model.state == .report(InspectionPresentation(
            report: action.report, waveform: .available(envelope()), spectrogram: .unavailable,
            signalLevelMetrics: .unavailable
        )))
    }

    @Test("an unavailable waveform replaces loading without touching the report")
    func unavailableReplacesLoading() async throws {
        let action = SuspendedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await Task.yield()
        action.deliverReport()
        await Task.yield()
        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await running.value

        #expect(model.state == .report(InspectionPresentation(
            report: action.report, waveform: .unavailable, spectrogram: .unavailable,
            signalLevelMetrics: .unavailable
        )))
    }

    @Test("a failed waveform never becomes a failed flow")
    func failedWaveformKeepsTheReport() async throws {
        let action = SuspendedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await Task.yield()
        action.deliverReport()
        await Task.yield()
        action.finish(.inspected(action.report, waveform: .failed(message: "The waveform could not be produced."), spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await running.value

        guard case let .report(presentation) = model.state else {
            Issue.record("a waveform failure must not replace the report, got \(model.state)"); return
        }
        #expect(presentation.report == action.report)
        #expect(presentation.waveform == .failed(message: "The waveform could not be produced."))
    }

    /// The specification's re-entrancy rule: while the *inspection* runs, another selection is ignored
    /// and the running one is unaffected.
    @Test("a selection made while the inspection is still running is ignored")
    func selectionDuringInspectionIsIgnored() async throws {
        let first = SuspendedAction(report: report(named: "first"))
        let second = SuspendedAction(report: report(named: "second"))
        let model = ImportFlowModel(action: first.run)

        let running = Task { await model.selectAndInspect() }
        await Task.yield()

        // No report delivered yet, so the state is still `.working`.
        #expect(model.state == .working)
        await model.inspectDroppedSource(using: second.run)

        #expect(second.callCount == 0, "the second selection never started")

        // Let the first one complete so the test can end; the assertions above already hold.
        first.deliverReport()
        first.finish(.inspected(first.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await running.value
        #expect(first.callCount == 1)
    }

    /// Once the report is on screen the inspection is over and only the waveform is pending, so a new
    /// selection is accepted — and it must cancel the old generation rather than race it.
    @Test("a selection made while only the waveform is pending supersedes it")
    func selectionDuringWaveformSupersedes() async throws {
        let first = SuspendedAction(report: report(named: "first"))
        let second = SuspendedAction(report: report(named: "second"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        await Task.yield()
        first.deliverReport()
        await Task.yield()
        #expect(model.state == .report(InspectionPresentation(report: first.report, waveform: .loading)))

        // Accepted: the inspection has finished, only the samples are still being read.
        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        await first.waitUntilCancelled()
        #expect(second.callCount == 1, "the second selection did start")
        #expect(first.cancellationsObserved == 1, "the pending generation was cancelled")

        second.deliverReport()
        await Task.yield()
        second.finish(.inspected(second.report, waveform: .available(envelope()), spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await secondRun.value
        _ = await firstRun.value

        guard case let .report(presentation) = model.state else {
            Issue.record("expected the second report, got \(model.state)"); return
        }
        #expect(presentation.report.file.displayName == "second")
        #expect(presentation.waveform == .available(envelope()))
    }

    @Test("a superseded result can never overwrite the newer one")
    func staleResultsAreDropped() async throws {
        let first = SuspendedAction(report: report(named: "first"), finishesOnCancellation: false)
        let second = SuspendedAction(report: report(named: "second"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        await Task.yield()
        first.deliverReport()
        await Task.yield()

        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        second.deliverReport()
        await Task.yield()
        second.finish(.inspected(second.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await secondRun.value

        // The superseded operation now tries to report a completely different result. It must not land.
        first.finish(.inspected(first.report, waveform: .available(envelope()), spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        _ = await firstRun.value

        guard case let .report(presentation) = model.state else {
            Issue.record("expected a report, got \(model.state)"); return
        }
        #expect(presentation.report.file.displayName == "second", "the stale result overwrote the newer one")
        #expect(presentation.waveform == .unavailable)
    }

    @Test("cancelling the panel keeps the report that was already on screen")
    func cancellingThePanelKeepsThePreviousReport() async throws {
        let first = SuspendedAction(report: report(named: "first"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        await Task.yield()
        first.deliverReport()
        await Task.yield()
        first.finish(.inspected(first.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable))
        await firstRun.value

        let settled = model.state
        await model.inspectDroppedSource(using: { _ in .cancelled })

        #expect(model.state == settled, "a dismissed panel restores exactly what was there")
    }
}
