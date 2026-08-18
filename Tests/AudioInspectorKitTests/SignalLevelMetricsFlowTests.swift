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


    /// Chunks covering only part of the stream they claim to come from — the one input that fails the
    /// **waveform alone**, because its reduction refuses to invent buckets the file never covered while
    /// the other three require no coverage at all.
    private func partialChunks(declaring declared: Int, covering covered: Int) throws -> [PCMChunk] {
        var built: [PCMChunk] = []
        var start = 0
        while start < covered {
            let count = min(1_024, covered - start)
            let samples = (0 ..< count).map { Float(0.5 * sin(2 * Double.pi * 997 * Double(start + $0) / 44_100)) }
            built.append(try PCMChunk(startFrame: start, channels: [samples, samples]))
            start += count
        }
        return built
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

            let decoder = FakeAudioDecoding(streaming: try stream(frames: 40_960), chunks: [])
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in decoder })
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, spectrogram, _, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            guard case .failed = report.status else {
                Issue.record("expected a globally failed report"); return
            }
            #expect(waveform == .unavailable)
            #expect(spectrogram == .unavailable)
            #expect(box.first == .unavailable, "signal level metrics are absent, not failed")
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
    /// **Rewritten for the shared read.** It used to script two decoders by call order so only the
    /// third operation failed. The spectrogram and the signal level metrics now share one read
    /// (ADR-0020), so a decoder failure is a *producer* failure and reaches both — which is the
    /// specified behaviour, not a regression. What this test was really protecting is unchanged and is
    /// what it still asserts: **a failed sample analysis never degrades the report, never disturbs the
    /// waveform, and never becomes an inspection warning.**
    @Test("a failed sample analysis leaves the report and the waveform intact")
    func aFailingOperationChangesNothingElse() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 8_192)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeDecoder: { _ in
                    FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "boom"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, spectrogram, _, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            if case .failed = report.status {
                Issue.record("a signal level metrics failure degraded the inspection")
            }
            // **Since the cutover this is a producer failure, so it ends every analysis.** The
            // waveform used to survive it only because it held a read of its own; sharing the read
            // means sharing its fate, which is exactly what ADR-0020 decision 2 says a producer
            // failure does. What must still hold — and is what this test now pins — is that each
            // reports its *own* outcome and the report is untouched.
            guard case let .failed(waveformMessage) = waveform else {
                Issue.record("expected the waveform to end with the read, got \(waveform)"); return
            }
            #expect(waveformMessage.contains("waveform"), "the waveform did not report its own failure")
            // A producer failure reaches every consumer of that read — and each still reports its own
            // outcome rather than deferring to another's.
            guard case .failed = spectrogram else {
                Issue.record("expected the spectrogram to report its own failure: \(spectrogram)"); return
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

            // **The waveform's one reachable solo failure.** The stream declares more frames than the
            // chunks cover, so its reduction refuses to invent the buckets nothing reached — while the
            // other analyses, which require no coverage, settle exactly as they would have.
            let declared = 16_384
            let partial = try partialChunks(declaring: declared, covering: 8_192)
            let declaredStream = try #require(
                PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: declared)
            )
            let coordinator = SourceInspectionCoordinator(
                makeDecoder: { _ in FakeAudioDecoding(streaming: declaredStream, chunks: partial) }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(_, waveform, _, _, _, _) = outcome else {
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

    /// **Cancellation is global now, and that is the guarantee.**
    ///
    /// This test used to assert that cancelling the signal level metrics left the waveform untouched — true while each
    /// held a read of its own. Since ADR-0021 there is one read, so cancelling it cancels every
    /// analysis. What must still hold is that each reports **cancellation as its own outcome** and that
    /// none of them is dressed up as an absence, which would tell the user their file lacks something
    /// it does not.
    @Test("cancelling the read cancels every analysis, and none becomes an absence")
    func cancellationEndsEveryAnalysis() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeDecoder: { _ in
                    FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, spectrogram, levels, truePeak, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(box.first == .cancelled)
            #expect(waveform == .cancelled)
            #expect(spectrogram == .cancelled)
            #expect(levels == .cancelled)
            #expect(truePeak == .cancelled)
            #expect(waveform != .unavailable, "cancellation must not be dressed up as an absence")
            if case .failed = report.status {
                Issue.record("a cancelled read degraded the inspection")
            }
        }
    }

    // **Removed: "a cancelled waveform leaves signal level metrics' result intact".**
    //
    // It asserted that cancelling the waveform left the signal level metrics alone. With a single read there is no
    // waveform-only cancellation to script — cancelling the read cancels every consumer — so the test
    // had no reachable input and would have been green for the wrong reason. The live half of what it
    // protected is the test above.

    /// **Rewritten for the shared read.** It used to cancel one of two decoders and assert the other
    /// survived — an assertion about the *arrangement*, which ADR-0020 replaced. With one read there is
    /// no such thing as cancelling the spectrogram alone: cancellation is the user replacing the whole
    /// inspection, and the property that matters is that **every analysis reports cancellation and none
    /// reports a value computed from what was read before it stopped.**
    @Test("a cancelled read cancels every analysis and leaks no partial model")
    func aCancelledReadCancelsEveryAnalysis() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 8_192)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in
                FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
            })
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(_, _, spectrogram, signalLevels, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(spectrogram == .cancelled)
            #expect(signalLevels == .cancelled)
            // Cancellation is not absence and not failure: a partial model presented as a result is
            // exactly what this asserts cannot happen.
            #expect(try #require(box.first) == .cancelled)
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

            // **One decode, not two.** This is the architectural assertion of ADR-0020: the spectrogram
            // and the signal level metrics are produced from a single read of the file. Before the
            // shared read this was 2, and a regression to separate decodes fails here first.
            #expect(await decoder.spy.callCount == 1, "the analyses did not share one read")
            #expect(box.outcomes.count == 1, "the result never reached the channel")
        }
    }
}
