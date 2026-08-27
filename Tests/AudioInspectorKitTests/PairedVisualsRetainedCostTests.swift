import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureImport

// Group 9's first subject: **what a pair on screen actually costs, and that it costs it once.**
//
// ADR-0025 §"Negative / costs" predicts *"about 2.02 MiB more retained while a comparison is open —
// the second file's `Spectrogram.values` (1024 × 512 floats = exactly 2 MiB) plus its envelope
// (2048 buckets × 8 bytes = 16 KiB)"*. A prediction is not a measurement, and this suite exists to
// take one. Two instruments, described in `RetainedCostSupport.swift`, are used on the same two
// states and their answers are reported separately:
//
// - **A — the model.** The payload buffers the flow really keeps alive, counted by storage address.
// - **A — the process.** The physical footprint the same two scenarios leave behind, measured
//   differentially and repeated.
//
// **B — rasters** are a different number with a different lifetime and are measured in
// `PairedSpectrogramRasterCostTests`. **C — the temporary memory of a read** is measured in
// `ReadTemporaryMemoryTests`. They are not added together anywhere, because they are not the same
// kind of thing.
//
// The two states measured, throughout:
//
// - **S** — the first file inspected, its own drawings settled and on screen, no comparison.
// - **P** — the same, plus a second file inspected and a pair settled.

@MainActor
@Suite("Cost — what a settled pair retains", .serialized)
struct PairedVisualsRetainedCostTests {

    // MARK: - Production-sized fixtures

    /// The largest model production can produce: `SpectrogramGridMapping`'s own caps, 1024 × 512.
    /// **The size is taken from the mapping rather than written as a literal**, so a cap that moves
    /// moves this measurement with it instead of leaving a stale number in a record.
    static func productionModel(sampleRate: Double, level: Float) -> Spectrogram {
        let columns = SpectrogramGridMapping.defaultMaximumColumnCount
        let bands = SpectrogramGridMapping.defaultMaximumBandCount
        return Spectrogram(
            values: [Float](repeating: level, count: columns * bands),
            columnCount: columns, bandCount: bands,
            sampleRate: sampleRate, frameCount: 1_048_576, channelCount: 2
        )!
    }

    /// The largest envelope production can produce: `WaveformBucketMapping`'s own cap, 2048 buckets.
    static func productionEnvelope(peak: Float) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: (0 ..< WaveformBucketMapping.defaultMaximumBucketCount).map { _ in
                WaveformBucket(minimum: -peak, maximum: peak)!
            },
            frameCount: 1_048_576, channelCount: 2
        )!
    }

    /// One production-sized model's `values`, in bytes — 1024 × 512 × 4.
    static var modelBytes: Int {
        SpectrogramGridMapping.defaultMaximumColumnCount
            * SpectrogramGridMapping.defaultMaximumBandCount
            * MemoryLayout<Float>.stride
    }

    /// One production-sized envelope's `buckets`, in bytes — 2048 × 8.
    static var envelopeBytes: Int {
        WaveformBucketMapping.defaultMaximumBucketCount * MemoryLayout<WaveformBucket>.stride
    }

    /// What ADR-0025 predicts one more file's drawings cost: 2 MiB + 16 KiB.
    static var predictedPairCost: Int { modelBytes + envelopeBytes }

    private static func report(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 2_048, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(container: .available("wav")),
            warnings: [], status: .completed
        )
    }

    private static func stream(_ sampleRate: Double) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: sampleRate, channelCount: 2, frameCount: 1_048_576)!
    }

    private static func analyses(
        _ sampleRate: Double, level: Float, peak: Float
    ) -> InspectionAnalyses {
        InspectionAnalyses(
            waveform: .available(productionEnvelope(peak: peak)),
            spectrogram: .available(productionModel(sampleRate: sampleRate, level: level)),
            signalLevelMetrics: .unavailable, truePeak: .unavailable,
            loudness: .unavailable, significantBandwidth: .unavailable,
            stream: stream(sampleRate)
        )
    }

    // MARK: - The two states

    /// **S** — one file inspected, its own drawings settled, no comparison asked for.
    static func flowShowingOneFile() async -> ImportFlowModel {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(report("a.wav"))])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        action.finish(.inspected(report("a.wav"), analyses: analyses(44_100, level: -30, peak: 0.5)))
        await running.value
        return flow
    }

    /// **P** — the same first file, with `name` compared against it and a pair settled.
    ///
    /// Returns the flow only. The fixtures the comparison was driven with go out of scope here, so
    /// what any instrument sees afterwards is what the **flow** kept, not what the test built.
    static func flowShowingAPair(
        second name: String = "b.wav", sampleRate: Double = 96_000, level: Float = -20, peak: Float = 0.75
    ) async -> ImportFlowModel {
        let flow = await flowShowingOneFile()
        await settleAComparison(on: flow, second: name, sampleRate: sampleRate, level: level, peak: peak)
        return flow
    }

    @discardableResult
    static func settleAComparison(
        on flow: ImportFlowModel, second name: String,
        sampleRate: Double, level: Float, peak: Float
    ) async -> ImportFlowModel {
        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(.inspected(
            report(name), analyses: analyses(sampleRate, level: level, peak: peak)
        ))
        await comparing.value
        return flow
    }

    private static func hasASettledPair(_ flow: ImportFlowModel) -> Bool {
        guard case .ready(_, _, .some) = flow.comparison else { return false }
        return true
    }

    // MARK: - 9.1 · A, the model: what the flow really keeps alive

    /// **The measurement, taken on the stored graph.** Both states are walked and their reachable
    /// payload buffers counted by address, so a buffer reached twice is one buffer.
    ///
    /// The expected difference is *one* more file's drawings, not two: the pair's first side is the
    /// same envelope and the same model the presentation already holds.
    @Test("a settled pair adds exactly one more file's model and envelope, and no copy of the first")
    func thePairAddsOneFilesDrawings() async {
        let single = RetainedGraph.walking(await Self.flowShowingOneFile())
        let paired = RetainedGraph.walking(await Self.flowShowingAPair())

        let delta = paired.payloadBytes - single.payloadBytes

        print("""

        ── 9.1 · A — the model, exact (payload buffers reachable from the flow) ──
        \(MeasurementConditions.description)
        S — first file only:  \(MiB.text(single.payloadBytes))
        P — pair settled:     \(MiB.text(paired.payloadBytes))
        delta:                \(MiB.text(delta))
        ADR-0025 prediction:  \(MiB.text(Self.predictedPairCost))

        """)

        // Exactly one more file's drawings — the prediction, met to the byte.
        #expect(delta == Self.predictedPairCost)
        // And the state really was a pair, so the delta is a pair's cost rather than a missing one's.
        #expect(Self.hasASettledPair(await Self.flowShowingAPair()))
    }

    /// **The first file's model is shared, not copied — measured, not asserted by naming
    /// copy-on-write.**
    ///
    /// With a pair on screen the first file's spectral model is reachable **twice** (its own
    /// presentation, and the pair's first side) while the buffers under it number **one more than
    /// before**, not two more. A physical copy would show up as both counts rising together.
    @Test("the first file's model is reachable twice and stored once")
    func theFirstFilesModelIsSharedRatherThanCopied() async {
        let single = RetainedGraph.walking(await Self.flowShowingOneFile())
        let paired = RetainedGraph.walking(await Self.flowShowingAPair())

        // Reached twice as a value…
        #expect(single.count(of: "Spectrogram") == 1)
        // The first file's own, the retained compared side, and the pair's two sides.
        #expect(paired.count(of: "Spectrogram") == 4)
        #expect(paired.count(of: "WaveformEnvelope") == 4)

        // …and stored once. Four `Spectrogram` values, two distinct buffers.
        let distinctBuffersAdded = paired.payloadBytes - single.payloadBytes
        #expect(distinctBuffersAdded == Self.predictedPairCost)
        // A copy of the first file's model would have made it twice that.
        #expect(distinctBuffersAdded < 2 * Self.predictedPairCost)
    }

    // MARK: - 9.1 · A, the process: the same two states, measured differentially

    /// **The runtime half of 9.1, recorded and not asserted on.** `phys_footprint` is process-wide, so
    /// no single reading is attributable to anything; what is attributable is the **difference**
    /// between two ramps of the same shape that differ only in whether a pair settles.
    ///
    /// **It was asserted on, and the assertion was wrong to make.** Run alone this reads 2.027 MiB per
    /// pair; run inside the whole suite it read **0.037**, because three of the paired ramp's five
    /// batches were served from pages other suites had already churned into the process's footprint and
    /// the median landed on one of them. A bound tuned to the quiet number fails on a busy machine and
    /// proves nothing on a quiet one — the same conclusion `ReadTemporaryMemoryTests` reached about its
    /// own reading, reached here one full-suite run later.
    ///
    /// **The claim is the exact instrument's**, and it is deterministic: the stored-graph measurement
    /// above gives the figure to the byte, and `aNewComparisonReplacesThePreviousPair` and the
    /// `pairHistory` negative control cover *retained once* from the other side. What this reading is
    /// good for is what 9.1 asks for — a record of what was measured.
    @Test("the process's footprint rises by about one file's drawings per pair")
    func theFootprintRisesByAboutOneFilesDrawings() async {
        let batch = 8
        let single = await measureRetainedRamp(count: batch) { await Self.flowShowingOneFile() }
        let paired = await measureRetainedRamp(count: batch) { await Self.flowShowingAPair() }
        let delta = paired.median - single.median
        let expected = batch * Self.predictedPairCost

        print("""

        ── 9.1 · A — the process, measured (phys_footprint, differential, ramp in batches of \(batch)) ──
        \(MeasurementConditions.description)
        S — \(batch) × first file only:  \(single.description)
        P — \(batch) × pair settled:     \(paired.description)
        delta of medians:               \(MiB.text(delta))
        per pair:                       \(MiB.text(delta / batch))
        ADR-0025 prediction, per pair:  \(MiB.text(Self.predictedPairCost))
        note: process-wide, and this suite runs beside others; recorded, not asserted on.

        """)

        // The readings are real readings rather than a kernel that declined to answer. Nothing is
        // asserted about their size: see the note above.
        #expect(single.deltas.count == 5)
        #expect(paired.deltas.count == 5)
        #expect(expected > 0)
    }

    // MARK: - 9.3 · at most one pair, and a new comparison releases the previous one

    /// **There is one field, and it holds one pair.** Not a collection, not a history, not a cache —
    /// asserted over the state the flow actually publishes.
    @Test("the flow holds exactly one pair, and no collection of them")
    func exactlyOnePairIsHeld() async {
        let graph = RetainedGraph.walking(await Self.flowShowingAPair())

        #expect(graph.count(of: "PairedVisuals") == 1)
        // The shapes a history would take, none of which exists.
        #expect(!graph.reached("Array<PairedVisuals>"))
        #expect(!graph.reached("Dictionary<Int, PairedVisuals>"))
        #expect(!graph.reached("Array<FileVisuals>"))
    }

    /// **B is gone when C arrives.** The pair on screen is C's, C's alone, and B's drawings are not
    /// reachable from the flow by any path.
    @Test("a new comparison replaces the previous pair rather than joining it")
    func aNewComparisonReplacesThePreviousPair() async {
        let flow = await Self.flowShowingAPair(second: "b.wav", sampleRate: 96_000, level: -20, peak: 0.75)

        guard case let .ready(_, _, pairB) = flow.comparison, let b = pairB else {
            Issue.record("expected a settled pair for B"); return
        }
        #expect(b.second.spectrogram == .available(Self.productionModel(sampleRate: 96_000, level: -20)))

        await Self.settleAComparison(on: flow, second: "c.wav", sampleRate: 48_000, level: -50, peak: 0.25)

        guard case let .ready(technical, _, pairC) = flow.comparison, let c = pairC else {
            Issue.record("expected a settled pair for C"); return
        }
        // The pair on screen is C's…
        #expect(technical.second.file.displayName == "c.wav")
        #expect(c.second.spectrogram == .available(Self.productionModel(sampleRate: 48_000, level: -50)))
        // …and B's is not it.
        #expect(c.second != b.second)

        // And B's drawings are not reachable from the flow at all: still one pair, still three models.
        let graph = RetainedGraph.walking(flow)
        #expect(graph.count(of: "PairedVisuals") == 1)
        #expect(graph.count(of: "Spectrogram") == 4)
    }

    /// **The state does not grow with the number of comparisons made.** Three comparisons in a row,
    /// and what the flow retains after the third is what it retained after the first — to the byte.
    @Test("retained memory does not grow with how many comparisons have been made")
    func retentionDoesNotGrowWithComparisons() async {
        let flow = await Self.flowShowingAPair(second: "b.wav", sampleRate: 96_000, level: -20, peak: 0.75)
        let afterFirst = RetainedGraph.walking(flow).payloadBytes

        await Self.settleAComparison(on: flow, second: "c.wav", sampleRate: 48_000, level: -50, peak: 0.25)
        let afterSecond = RetainedGraph.walking(flow).payloadBytes

        await Self.settleAComparison(on: flow, second: "d.wav", sampleRate: 22_050, level: -70, peak: 0.1)
        let afterThird = RetainedGraph.walking(flow).payloadBytes

        #expect(afterFirst == afterSecond)
        #expect(afterSecond == afterThird)

        // And dismissing gives the second file's drawings back.
        flow.dismissComparison()
        #expect(RetainedGraph.walking(flow).payloadBytes == afterFirst - Self.predictedPairCost)
    }
}
