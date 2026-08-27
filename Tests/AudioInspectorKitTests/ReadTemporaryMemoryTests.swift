import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorTesting
@testable import AudioInspectorApp
@testable import FeatureImport

// Group 9's second subject: **C — the memory a read borrows, and gives back.**
//
// Task 9.2 asks for two facts about what is left when an inspection is over: **no PCM is retained**,
// and **no accumulator outlives its read**. Neither is answerable by looking at a type and not seeing
// a `[Float]` in it — a closure can capture one, a consumer can be kept alive by something that
// forgot to let go, and neither shows up in a declaration. So both are answered twice, by
// instruments with different blind spots (`RetainedCostSupport.swift`):
//
// - **Structurally**, by walking what the finished inspection really keeps alive and naming what is
//   reachable. Exact; blind to closure captures.
// - **By measurement**, by reading the process's footprint **at the last chunk of the read** and
//   again once everything has settled. It sees closure captures and allocator behaviour alike; it is
//   process-wide and noisy, so only a difference across the same run is quoted.
//
// The route is production: the real `SourceInspectionCoordinator`, the real
// `SharedPCMAnalysisGeneration`, the real six accumulators. Only the decoder is a double, and only so
// that a large stream can be produced without a large file — it **generates** each chunk on demand and
// retains none, which a scripted fake holding an array of chunks could not do without becoming the
// thing being measured.

@MainActor
@Suite("Cost — a read borrows its memory and gives it back", .serialized)
struct ReadTemporaryMemoryTests {

    // MARK: - A decoder that generates, and keeps nothing

    /// Hands over `chunkCount` chunks of `chunkFrames` frames each, built one at a time and released
    /// as soon as the consumer returns. Nothing is stored: what survives the call is what the code
    /// under test decided to keep.
    private struct GeneratingDecoder: AudioDecoding {
        let sampleRate: Double
        let channelCount: Int
        let chunkCount: Int
        let framesPerChunk: Int
        /// Called with the footprint reading taken while the **last** chunk is in flight — the
        /// high-water mark of a read, when every accumulator holds everything it will ever hold.
        let observeFootprintAtLastChunk: @Sendable (Int) -> Void

        var totalFrames: Int { chunkCount * framesPerChunk }

        /// Every sample the read will hand over, in bytes — the number the retained figure is
        /// compared against.
        var totalPCMBytes: Int { totalFrames * channelCount * MemoryLayout<Float>.stride }

        func decode(
            _ file: AudioFileReference,
            chunkFrames: Int,
            receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
        ) async throws(AudioDecodingError) -> PCMStreamDescription? {
            guard let stream = PCMStreamDescription(
                sampleRate: sampleRate, channelCount: channelCount, frameCount: totalFrames
            ) else { return nil }

            for index in 0 ..< chunkCount {
                // A different value per chunk, so nothing collapses to a shared constant buffer and
                // the accumulators do real work.
                let level = Float(index % 32) / 64 + 0.01
                let plane = [Float](repeating: level, count: framesPerChunk)
                guard let chunk = try? PCMChunk(
                    startFrame: index * framesPerChunk,
                    channels: Array(repeating: plane, count: channelCount)
                ) else { continue }

                if index == chunkCount - 1, let footprint = ProcessFootprint.current() {
                    observeFootprintAtLastChunk(footprint)
                }
                if receive(stream, chunk) == .stop { break }
            }
            return stream
        }
    }

    /// A place for the reading taken inside the decoder to land. A class because the decoder is
    /// `Sendable` and the callback is not the place to own state.
    private final class FootprintProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int?
        var atLastChunk: Int? { lock.withLock { value } }
        func record(_ footprint: Int) { lock.withLock { value = footprint } }
    }

    // MARK: - One real inspection over a large stream

    /// Runs the real coordinator over a generated stream and returns what it produced, together with
    /// the two footprint readings the claim is made from.
    private func inspectALargeStream(
        seconds: Double = 30
    ) async -> (
        analyses: InspectionAnalyses?, pcmBytes: Int,
        before: Int, atLastChunk: Int, afterSettling: Int
    ) {
        let sampleRate: Double = 44_100
        let framesPerChunk = 4_096
        let chunkCount = Int((sampleRate * seconds) / Double(framesPerChunk))
        let probe = FootprintProbe()

        let decoder = GeneratingDecoder(
            sampleRate: sampleRate, channelCount: 2,
            chunkCount: chunkCount, framesPerChunk: framesPerChunk,
            observeFootprintAtLastChunk: { probe.record($0) }
        )
        let coordinator = SourceInspectionCoordinator(
            makeReader: { _ in FakeAudioFilePropertyReading(succeedingWith: allAvailableProperties()) },
            makeDecoder: { _ in decoder }
        )

        let before = ProcessFootprint.current() ?? 0
        let outcome = await coordinator.inspect(
            URL(fileURLWithPath: "/tmp/audio-inspector-group-9-generated.wav")
        ) { _ in }

        let afterSettling = ProcessFootprint.current() ?? 0
        guard case let .inspected(_, analyses) = outcome else {
            return (nil, decoder.totalPCMBytes, before, probe.atLastChunk ?? 0, afterSettling)
        }
        return (analyses, decoder.totalPCMBytes, before, probe.atLastChunk ?? 0, afterSettling)
    }

    // MARK: - 9.2 · structurally: what a finished inspection keeps alive

    /// **Nothing that belongs to the read survives it.** The finished bundle is walked and the types
    /// a retained read would show up as are asked for by name.
    ///
    /// The blind spot is stated rather than left implicit: this walk follows stored properties and
    /// cannot see inside a closure's captures. The footprint measurement below is what covers that,
    /// and the two are not treated as one instrument.
    @Test("no chunk, no accumulator and no decoder is reachable from a finished inspection")
    func nothingFromTheReadSurvivesIt() async {
        let run = await inspectALargeStream(seconds: 5)
        guard let analyses = run.analyses else {
            Issue.record("expected a finished inspection"); return
        }

        let graph = RetainedGraph.walking(analyses)

        // The samples themselves.
        #expect(!graph.reached("PCMChunk"))
        #expect(!graph.reached("Array<Array<Float>>"))
        // Every accumulator the shared read builds, by name.
        for accumulator in [
            "WaveformEnvelopeAccumulator", "SpectrogramAccumulator", "LoudnessAccumulator",
            "TruePeakAccumulator", "SignalLevelMetricsAccumulator", "SignificantBandwidthAccumulator",
        ] {
            #expect(!graph.reached(accumulator), "\(accumulator) outlived the read")
        }
        // And the producer itself.
        #expect(!graph.reached("GeneratingDecoder"))
        #expect(!graph.reached("SharedPCMAnalysisGeneration"))
        #expect(!graph.reached("SharedPCMAnalysisOutcome"))

        // The walk really did reach the drawings, so the absences above are absences rather than a
        // walk that stopped early.
        #expect(graph.reached("Spectrogram"))
        #expect(graph.reached("WaveformEnvelope"))
    }

    // MARK: - 9.2 · by measurement: the read's high-water mark is given back

    /// **The record, and what it can and cannot carry.** The process's footprint is read three times
    /// across one inspection — before it starts, while the **last chunk** is in flight, and once
    /// everything has settled — and printed beside the whole stream's worth of PCM.
    ///
    /// **The readings are recorded, not asserted on**, and that is a decision rather than an
    /// omission. This instrument is process-wide, the suite runs in parallel, and a run of the whole
    /// suite showed the same window reading 6.5 MiB where a quiet run read 2.1 — other suites'
    /// allocations, landing inside the window and indistinguishable from this one's. A threshold
    /// tuned to the quiet number would fail on a busy machine and prove nothing on a quiet one. What
    /// this reading is good for is the record: it is the only instrument that can see a buffer
    /// captured by a closure, and what it shows is a read of ten megabytes leaving about two behind.
    ///
    /// **The claim itself is asserted on the exact instrument**, here and in the two tests around it:
    /// the payload really reachable from the finished inspection, which is deterministic and owes
    /// nothing to what else the machine is doing.
    ///
    /// One thing worth reading rather than assuming, while the numbers are here: **the peak is not at
    /// the last chunk.** The spectral model is built by `finish()`, *after* the samples stop, so the
    /// footprint is higher when the inspection returns than it was mid-read. That is the drawing
    /// being made, not the read being held.
    @Test("a read of ten megabytes of samples leaves about two megabytes behind")
    func theReadDoesNotCostWhatItReads() async {
        let run = await inspectALargeStream(seconds: 30)
        guard let analyses = run.analyses else {
            Issue.record("expected a finished inspection"); return
        }

        let retained = RetainedGraph.walking(analyses).payloadBytes

        print("""

        ── 9.2 · C — the read's temporary memory (phys_footprint, one run, recorded) ──
        \(MeasurementConditions.description)
        stream read:                 \(MiB.text(run.pcmBytes)) of PCM, 30 s of 44.1 kHz stereo
        rise at the last chunk:      \(MiB.text(run.atLastChunk - run.before))
        rise once settled:           \(MiB.text(run.afterSettling - run.before))
        retained payload (exact):    \(MiB.text(retained))
        note: the footprint is process-wide and this suite runs beside others; the rises above are a
              record, and the assertions below are the exact instrument's.

        """)

        // What is kept is a drawing's worth, not a file's worth — on the instrument that can say so.
        #expect(retained < run.pcmBytes / 4)
        // And the recorded readings are real readings rather than a kernel that declined to answer.
        #expect(run.before > 0)
        #expect(run.atLastChunk > 0)
        #expect(run.afterSettling > 0)

        withExtendedLifetime(analyses) {}
    }

    /// **The read's cost does not scale with the file.** Two streams, one twice the length of the
    /// other, both long enough for the spectral grid to reach its cap: twice the samples, and the
    /// same retention **to the byte**.
    ///
    /// This is the sharpest form of *no PCM is retained*: anything held in proportion to the input
    /// would show here as a difference, and there is none. What is kept is a function of the model's
    /// own grid — `SpectrogramGridMapping`'s caps — and of nothing else.
    @Test("twice the samples, and the same retention to the byte")
    func retentionIsCappedByTheGridRatherThanTheFile() async {
        let shorter = await inspectALargeStream(seconds: 15)
        let longer = await inspectALargeStream(seconds: 30)

        guard let shorterAnalyses = shorter.analyses, let longerAnalyses = longer.analyses else {
            Issue.record("expected two finished inspections"); return
        }

        let shorterRetained = RetainedGraph.walking(shorterAnalyses).payloadBytes
        let longerRetained = RetainedGraph.walking(longerAnalyses).payloadBytes

        print("""

        ── 9.2 · C — retention against stream length ──
        15 s → PCM \(MiB.text(shorter.pcmBytes))  retained \(MiB.text(shorterRetained))
        30 s → PCM \(MiB.text(longer.pcmBytes))  retained \(MiB.text(longerRetained))

        """)

        // The fixtures really do differ in length…
        #expect(longer.pcmBytes == 2 * shorter.pcmBytes)
        // …and not in what is left behind.
        #expect(longerRetained == shorterRetained)
    }
}
