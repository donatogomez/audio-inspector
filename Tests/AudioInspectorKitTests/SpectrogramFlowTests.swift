import AVFoundation
import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import FeatureImport
import Foundation
import Testing

// The spectrogram as an operation of the real coordinator: where it runs, when it does not run at all,
// and that it and the waveform cannot reach each other.
//
// Everything here is driven by scripted ports or by real files. No sleeps, no polling, no assumption
// about the order in which two tasks are scheduled.

@MainActor
@Suite("App — spectrogram generation flow")
struct SpectrogramFlowTests {
    /// Collects what the coordinator handed back, on the main actor where the handler runs.
    private final class OutcomeBox {
        var outcomes: [SpectrogramOutcome] = []
        var first: SpectrogramOutcome? { outcomes.first }

        /// Collects only the spectrogram updates; the rest of the channel is not this suite's subject.
        @MainActor func collect(_ update: InspectionUpdate) {
            if case let .spectrogram(outcome) = update { outcomes.append(outcome) }
        }
    }

    private func fixture(in directory: URL, frames: AVAudioFrameCount = 20_000) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "flow", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                channels: 2, frames: frames
            ),
            in: directory
        )
    }

    private func stream(frames: Int) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: frames))
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

    // MARK: The security-scoped window

    /// The decode must happen while the caller's access window is open. This proves it against the
    /// **real** decoder over a real file: the coordinator's `defer` releases the scope when `inspect`
    /// returns, and a spectrogram that came back with a model can only have been read before then.
    @Test("the real decoder reads the file inside the coordinator's access window")
    func theDecoderRunsInsideTheWindow() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory, frames: 20_000)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator()
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .available(model) = try #require(box.first) else {
                Issue.record("the real decoder produced \(String(describing: box.first))")
                return
            }
            #expect(model.frameCount == 20_000)
            #expect(model.columnCount > 0, "a real file was decoded and folded inside the window")
        }
    }

    /// The window is entered and left exactly once for the whole operation — report, waveform and
    /// spectrogram — rather than once per visualisation. Observed through the handler's ordering
    /// against the coordinator's return: the outcome arrives before `inspect` returns, so it cannot
    /// have been produced after the `defer`.
    @Test("the spectrogram settles before the coordinator returns, inside the one window")
    func theSpectrogramSettlesBeforeTheCoordinatorReturns() async throws {
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
    /// all produces no spectrogram operation and no handler call.
    @Test("a preparation failure starts no spectrogram operation")
    func aPreparationFailureStartsNothing() async {
        let box = OutcomeBox()
        let coordinator = SourceInspectionCoordinator()

        let outcome = await coordinator.inspect(URL(string: "https://example.com/x.wav")!, onUpdate: { box.collect($0) })

        #expect(outcome == .preparationFailed)
        #expect(box.outcomes.isEmpty, "a spectrogram was attempted for something that is not a file")
    }

    // MARK: A global failure reads no samples at all

    /// Nothing could be read, so nothing is read twice over. **Neither** the waveform nor the
    /// spectrogram touches the file: both ports are scripted spies and both must record zero calls.
    @Test("a global inspection failure skips both sample reads entirely")
    func aGlobalFailureSkipsBothReads() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("not-audio.wav")
            try Data("definitely not audio".utf8).write(to: url)

            let decoder = FakeAudioDecoding(streaming: try stream(frames: 40_960), chunks: [])
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in decoder })
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, _, _, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            guard case .failed = report.status else {
                Issue.record("expected a globally failed report"); return
            }
            #expect(waveform == .unavailable)
            #expect(box.first == .unavailable, "the spectrogram is absent, not failed")
            #expect(await decoder.spy.callCount == 0, "the spectrogram read samples after a global failure")
        }
    }

    // MARK: Independence

    /// A spectrogram that fails must not touch the report or the waveform. The two operations share no
    /// accumulator and no mutable state, and this asserts the consequence.
    @Test("a failing spectrogram leaves the report and the waveform intact")
    func aFailingSpectrogramChangesNothingElse() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(
                makeDecoder: { _ in
                    FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "boom"))
                }
            )
            let outcome = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            guard case let .inspected(report, waveform, _, _, _, _) = outcome else {
                Issue.record("expected an inspected outcome"); return
            }
            if case .failed = report.status {
                Issue.record("a spectrogram failure degraded the inspection")
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
            guard case .failed = try #require(box.first) else {
                Issue.record("expected a failed spectrogram"); return
            }
            // The file's own property warnings are unrelated and pre-existing; what must not appear
            // is a warning *about* the spectrogram. A failed visualisation is never an inspection
            // warning (ADR-0016 decision 14).
            #expect(
                report.warnings.allSatisfy { warning in
                    !warning.message.lowercased().contains("spectrogram")
                        && !warning.code.rawValue.contains("spectrogram")
                },
                "a spectrogram failure emitted an inspection warning"
            )
        }
    }

    /// And the other direction: a waveform that fails must not stop the spectrogram from being
    /// produced.
    @Test("a failing waveform does not prevent the spectrogram")
    func aFailingWaveformDoesNotStopTheSpectrogram() async throws {
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
            guard case let .available(model) = try #require(box.first) else {
                Issue.record("the waveform's failure stopped the spectrogram: \(String(describing: box.first))")
                return
            }
            #expect(model.columnCount > 0)
        }
    }

    /// **Cancellation is global now, and that is the guarantee.**
    ///
    /// This test used to assert that cancelling the spectrogram left the waveform untouched — true while each
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

    // **Removed: "a cancelled waveform leaves the spectrogram's result intact".**
    //
    // It asserted that cancelling the waveform left the spectrogram alone. With a single read there is no
    // waveform-only cancellation to script — cancelling the read cancels every consumer — so the test
    // had no reachable input and would have been green for the wrong reason. The live half of what it
    // protected is the test above.

    /// Two operations, two decoders, two accumulators. Nothing is shared, so a second inspection cannot
    /// inherit anything from the first.
    @Test("each inspection builds its own decoder and its own model")
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

    @Test("generating a spectrogram writes nothing beside the source")
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

    /// Group 5 gated the generation on a handler, because nothing consumed the result. Group 6 gives it
    /// a consumer, so the decode now always happens and its result always reaches the channel.
    @Test("the decode runs and its result reaches the update channel")
    func theResultIsAlwaysDelivered() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let decoder = FakeAudioDecoding(streaming: try stream(frames: 20_000), chunks: [])
            let box = OutcomeBox()

            let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in decoder })
            _ = await coordinator.inspect(url, onUpdate: { box.collect($0) })

            // **One decode, not two.** The spectrogram and the signal level metrics are produced from a
            // single read of the file (ADR-0020). Before the shared read this was 2, and a regression
            // to separate decodes fails here first.
            #expect(await decoder.spy.callCount == 1, "the analyses did not share one read")
            #expect(box.outcomes.count == 1, "its result never reached the channel")
        }
    }
}
