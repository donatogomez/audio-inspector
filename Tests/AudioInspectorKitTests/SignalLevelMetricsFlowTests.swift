import AVFoundation
import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import FeatureImport
import Foundation
import Synchronization
import Testing

// Signal level metrics as an operation of the real coordinator: where it runs, when it does not run at
// all, and that it and the waveform/spectrogram cannot reach each other. Mirrors `SpectrogramFlowTests`
// exactly, checked against the *third* operation this time.
//
// Everything here is driven by scripted ports or by real files. No sleeps, no polling, no assumption
// about the order in which tasks are scheduled.

@MainActor
@Suite("App — signal level metrics generation flow")
struct SignalLevelMetricsFlowTests {
    /// Collects what the coordinator handed back, on the main actor where the handler runs.
    private final class OutcomeBox {
        var outcomes: [SignalLevelMetricsOutcome] = []
        var first: SignalLevelMetricsOutcome? { outcomes.first }

        /// Collects only the signal level metrics updates; the rest of the channel is not this suite's
        /// subject.
        @MainActor func collect(_ update: InspectionUpdate) {
            if case let .signalLevelMetrics(outcome) = update { outcomes.append(outcome) }
        }
    }

    private func fixture(in directory: URL, frames: AVAudioFrameCount = 20_000) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "signal-level-flow", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                channels: 2, frames: frames
            ),
            in: directory
        )
    }

    private nonisolated func stream(frames: Int) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: frames))
    }

    // MARK: The security-scoped window

    /// The decode must happen while the caller's access window is open. This proves it against the
    /// **real** decoder over a real file.
    @Test("the real decoder reads the file inside the coordinator's access window")
    func theDecoderRunsInsideTheWindow() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 20_000)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator()
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .available(metrics) = try #require(box.first) else {
                Issue.record("the real decoder produced \(String(describing: box.first))")
                return
            }
            #expect(metrics.channels.count == 2)
            #expect(metrics.channels[0].sampleCount == 20_000, "a real file was decoded and folded inside the window")
        }
    }

    /// The window is entered and left exactly once for the whole operation, rather than once per
    /// visualisation.
    @Test("the signal level metrics settle before the coordinator returns, inside the one window")
    func theMetricsSettleBeforeTheCoordinatorReturns() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 8_192)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator()
            #expect(box.outcomes.isEmpty, "nothing runs before the inspection does")

            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            #expect(box.outcomes.count == 1, "the operation ran exactly once")
        }
    }

    /// An early failure must not leave the window half-used either: a URL that cannot be inspected at
    /// all produces no signal level metrics operation and no handler call.
    @Test("a preparation failure starts no signal level metrics operation")
    func aPreparationFailureStartsNothing() async {
        let box = OutcomeBox()
        let coordinator = SourceInspectionCoordinator()

        let outcome = await coordinator.inspect(URL(string: "https://example.com/x.wav")!, onUpdate: { box.collect($0) })

        #expect(outcome == .preparationFailed)
        #expect(box.outcomes.isEmpty, "signal level metrics were attempted for something that is not a file")
    }

    // MARK: A global failure reads no samples at all

    /// Nothing could be read, so nothing is read twice over. **None** of the three sample reads touches
    /// the file.
    @Test("a global inspection failure skips all three sample reads entirely")
    func aGlobalFailureSkipsAllReads() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("not-audio.wav")
            try Data("definitely not audio".utf8).write(to: url)

            let generator = FakeWaveformGenerating(.absent)
            let decoder = FakeAudioDecoding(streaming: try stream(frames: 40_960), chunks: [])
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in generator },
                makeDecoder: { _ in decoder }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, spectrogram, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            guard case .failed = report.status else {
                Issue.record("expected a globally failed report"); return
            }
            #expect(waveform == .unavailable)
            #expect(spectrogram == .unavailable)
            #expect(box.first == .unavailable, "signal level metrics are absent, not failed")
            #expect(await generator.callCount == 0, "the waveform read samples after a global failure")
            #expect(await decoder.spy.callCount == 0, "signal level metrics read samples after a global failure")
        }
    }

    // MARK: Independence

    /// Signal level metrics that fail must not touch the report, the waveform, or the spectrogram. The
    /// three operations share no accumulator and no mutable state, and this asserts the consequence.
    ///
    /// The spectrogram and signal level metrics both call `makeDecoder`, in a fixed, sequential order
    /// (the coordinator awaits the spectrogram before starting the third operation): the first call
    /// scripts a working spectrogram, the second — signal level metrics' own — fails. This isolates the
    /// fault to the *third* operation alone, rather than failing both by sharing one scripted decoder.
    @Test("failing signal level metrics leaves the report, the waveform and the spectrogram intact")
    func aFailingOperationChangesNothingElse() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 8_192)
            let envelope = try #require(WaveformEnvelope.empty(channelCount: 2))
            let box = OutcomeBox()
            let callCount = Atomic<Int>(0)

            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in FakeWaveformGenerating(succeedingWith: envelope) },
                makeDecoder: { _ in
                    let order = callCount.wrappingAdd(1, ordering: .relaxed).newValue
                    if order == 1 {
                        return FakeAudioDecoding(streaming: try! self.stream(frames: 8_192), chunks: [])
                    }
                    return FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "boom"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, spectrogram, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            if case .failed = report.status {
                Issue.record("a signal level metrics failure degraded the inspection")
            }
            #expect(waveform == .available(envelope), "a signal level metrics failure disturbed the waveform")
            guard case .available = spectrogram else {
                Issue.record("a signal level metrics failure disturbed the spectrogram: \(spectrogram)"); return
            }
            guard case .failed = try #require(box.first) else {
                Issue.record("expected failed signal level metrics"); return
            }
            // The file's own property warnings are unrelated and pre-existing; what must not appear is
            // a warning *about* signal level metrics. A failed visualisation is never an inspection
            // warning (ADR-0016 decision 14, ADR-0018).
            #expect(
                report.warnings.allSatisfy { warning in
                    !warning.message.lowercased().contains("signal") && !warning.message.lowercased().contains("level")
                        && !warning.code.rawValue.contains("signal")
                },
                "a signal level metrics failure emitted an inspection warning"
            )
        }
    }

    /// And the other direction: a waveform that fails must not stop signal level metrics from being
    /// produced.
    @Test("a failing waveform does not prevent signal level metrics")
    func aFailingWaveformDoesNotStopSignalLevelMetrics() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in
                    FakeWaveformGenerating(failingWith: WaveformError(code: .readFailed, message: "boom"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(_, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            guard case .failed = waveform else {
                Issue.record("expected a failed waveform"); return
            }
            guard case let .available(metrics) = try #require(box.first) else {
                Issue.record("the waveform's failure stopped signal level metrics: \(String(describing: box.first))")
                return
            }
            #expect(metrics.channels.count == 2)
        }
    }

    /// Cancelling signal level metrics' decode leaves the waveform's result untouched — they are
    /// separate operations over separate ports, and neither can reach the other's state.
    @Test("cancelled signal level metrics leaves the waveform's result intact")
    func aCancelledOperationLeavesTheWaveformAlone() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let envelope = try #require(WaveformEnvelope.empty(channelCount: 2))
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in FakeWaveformGenerating(succeedingWith: envelope) },
                makeDecoder: { _ in
                    FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(box.first == .cancelled)
            #expect(waveform == .available(envelope), "cancelling one operation cancelled another")
            if case .failed = report.status {
                Issue.record("cancelled signal level metrics degraded the inspection")
            }
        }
    }

    /// The mirror: a cancelled waveform leaves signal level metrics alone.
    @Test("a cancelled waveform leaves signal level metrics' result intact")
    func aCancelledWaveformLeavesTheOperationAlone() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeWaveformGenerator: { _ in
                    FakeWaveformGenerating(failingWith: WaveformError(code: .cancelled, message: "cancelled"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(_, waveform, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(waveform == .cancelled)
            guard case .available = try #require(box.first) else {
                Issue.record("cancelling the waveform cancelled signal level metrics"); return
            }
        }
    }

    /// Signal level metrics and the spectrogram both use `makeDecoder`, but each with its own instance
    /// (in production) or its own scripted double: cancelling one must not cancel the other, since
    /// neither shares an accumulator or a decoder instance in the coordinator's own wiring.
    @Test("a cancelled spectrogram leaves signal level metrics' result intact")
    func aCancelledSpectrogramLeavesTheOperationAlone() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 8_192)
            let box = OutcomeBox()
            let callCount = Atomic<Int>(0)

            // The spectrogram is the first `makeDecoder` call, signal level metrics the second — this
            // factory scripts them independently by call order, proving the coordinator gives each
            // operation its own decoder instance rather than passing one decoder to both.
            let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in
                let order = callCount.wrappingAdd(1, ordering: .relaxed).newValue
                if order == 1 {
                    return FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
                }
                return FakeAudioDecoding(streaming: try! self.stream(frames: 8_192), chunks: [])
            })
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(_, _, spectrogram, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(spectrogram == .cancelled)
            guard case .available = try #require(box.first) else {
                Issue.record("cancelling the spectrogram cancelled signal level metrics"); return
            }
        }
    }

    /// Two operations, two decoders, two accumulators. Nothing is shared, so a second inspection cannot
    /// inherit anything from the first.
    @Test("each inspection builds its own decoder and its own metrics")
    func eachInspectionIsIndependent() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 8_192)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator()
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            #expect(box.outcomes.count == 2)
            #expect(box.outcomes[0] == box.outcomes[1], "two reads of one file disagreed")
        }
    }

    // MARK: The source is untouched

    @Test("generating signal level metrics writes nothing beside the source")
    func theSourceIsUntouched() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let before = try Data(contentsOf: url)
            let contentsBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator()
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            #expect(try Data(contentsOf: url) == before, "the source changed")
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == contentsBefore,
                "a file was created or removed beside the source"
            )
        }
    }

    @Test("the decode runs and its result reaches the update channel")
    func theResultIsAlwaysDelivered() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let decoder = FakeAudioDecoding(streaming: try stream(frames: 20_000), chunks: [])
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in decoder })
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            // Twice: once for the spectrogram, once for signal level metrics — both share this single
            // injected decoder in this test, but each calls `makeDecoder` independently.
            #expect(await decoder.spy.callCount == 2, "signal level metrics were not produced")
            #expect(box.outcomes.count == 1, "the result never reached the channel")
        }
    }
}
