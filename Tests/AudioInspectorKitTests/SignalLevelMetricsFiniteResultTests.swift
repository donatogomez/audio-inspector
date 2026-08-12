import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

/// **A finite input has a finite answer, and the code now guarantees it in both places it could fail.**
///
/// `PCMChunk` refuses `NaN` and infinity at the boundary but deliberately keeps finite samples of any
/// magnitude — a file may genuinely carry a sample beyond full scale, and that is a fact this project
/// reports rather than clamps. What it must never do is turn such a sample into a *measurement* that
/// cannot exist.
///
/// The defect these tests pin was real and reached the exported document: the accumulator formed each
/// chunk's partial sums in `Float32` before widening them, so the sum of squares went non-finite from
/// about `1e18` and the plain sum from about `1e37`, with alternating signs producing a `NaN`. It was
/// also chunk-dependent, which contradicted this type's own independence guarantee.
///
/// **The mathematics never justified any of it.** Both results are bounded by the largest magnitude in
/// the input — `|mean| ≤ max|x|` and `RMS = sqrt(mean(x²)) ≤ max|x|` — so the answer always fits where
/// the samples fit. The overflow was purely intermediate, which is why the fix preserves the
/// measurement instead of declaring a failure: nothing here clamps, substitutes or invents a value.
@Suite("Analysis — finite samples always produce a finite measurement")
struct SignalLevelMetricsFiniteResultTests {

    // MARK: - Fixtures

    private func reduce(_ channels: [[Float]], chunk: Int = 4_096) throws -> SignalLevelMetrics {
        var accumulator = try #require(SignalLevelMetricsAccumulator(channelCount: channels.count))
        let frames = channels.first?.count ?? 0
        var start = 0
        while start < frames {
            let end = min(start + chunk, frames)
            let piece = try PCMChunk(startFrame: start, channels: channels.map { Array($0[start ..< end]) })
            accumulator.accumulate(piece)
            start = end
        }
        return try #require(accumulator.finish(), "the accumulator refused a result it should have produced")
    }

    /// The magnitudes that used to break it, plus the largest a `Float` can hold.
    private static let extremeMagnitudes: [Float] = [
        1e18, 1e30, 1e37, 3.0e38, .greatestFiniteMagnitude,
    ]

    private func constant(_ value: Float, count: Int = 4_096) -> [Float] {
        [Float](repeating: value, count: count)
    }

    /// Alternating signs: the shape that produced `+inf + -inf == NaN` in the plain sum.
    private func alternating(_ value: Float, count: Int = 4_096) -> [Float] {
        (0 ..< count).map { $0.isMultiple(of: 2) ? value : -value }
    }

    // MARK: - Every field stays finite, at every magnitude a Float can hold

    @Test("no field is ever non-finite for finite samples", arguments: extremeMagnitudes)
    func everyFieldStaysFinite(_ magnitude: Float) throws {
        for samples in [constant(magnitude), alternating(magnitude)] {
            let metrics = try reduce([samples])
            let channel = try #require(metrics.channels.first)

            #expect(try #require(channel.peakSample).isFinite)
            #expect(try #require(channel.rms).isFinite)
            #expect(try #require(channel.dcOffset).isFinite)
            #expect(try #require(metrics.overallPeakSample).isFinite)
            #expect(try #require(metrics.overallRMS).isFinite)
            #expect(try #require(metrics.overallDCOffset).isFinite)
        }
    }

    /// **Not merely finite — correct.** A constant signal of magnitude `M` has peak `M`, RMS `M` and a
    /// mean of `±M`; alternating signs leave the mean at zero while the RMS is unchanged, because
    /// squaring discards the sign. Asserting the values rather than their finiteness is what
    /// distinguishes a fix from a clamp.
    @Test("the values are the mathematically correct ones, not merely finite", arguments: extremeMagnitudes)
    func theValuesAreCorrect(_ magnitude: Float) throws {
        let constantMetrics = try reduce([constant(magnitude)])
        let constantChannel = try #require(constantMetrics.channels.first)
        #expect(try #require(constantChannel.peakSample) == magnitude)
        #expect(relativeError(try #require(constantChannel.rms), magnitude) < 1e-6)
        #expect(relativeError(try #require(constantChannel.dcOffset), magnitude) < 1e-6)

        let alternatingMetrics = try reduce([alternating(magnitude)])
        let alternatingChannel = try #require(alternatingMetrics.channels.first)
        #expect(try #require(alternatingChannel.peakSample) == magnitude)
        #expect(relativeError(try #require(alternatingChannel.rms), magnitude) < 1e-6)
        // The mean of equally many `+M` and `-M` is exactly zero — where it used to be `NaN`.
        #expect(try #require(alternatingChannel.dcOffset) == 0)
    }

    /// The peak and the clipped count were never affected — a maximum of magnitudes cannot overflow and
    /// a count is a count — and the fix must not have disturbed them.
    @Test func thePeakAndTheClipCountAreUnaffected() throws {
        let metrics = try reduce([constant(.greatestFiniteMagnitude, count: 1_000)])
        let channel = try #require(metrics.channels.first)
        #expect(channel.peakSample == .greatestFiniteMagnitude)
        #expect(channel.clippedSampleCount == 1_000, "every sample is beyond full scale")
        #expect(channel.sampleCount == 1_000)
    }

    // MARK: - Chunk independence, which the defect also broke

    /// The old implementation gave a **different answer at one frame per chunk than at 4 096**, because
    /// a single-sample partial cannot overflow where a batched one can. That is the independence
    /// guarantee this type documents, and it now holds at the extremes too.
    @Test(
        "an extreme signal measures the same however the file was cut",
        arguments: [1, 3, 127, 512, 4_096, 65_536]
    )
    func chunkIndependenceAtExtremeMagnitudes(_ chunk: Int) throws {
        let samples = alternating(1e30, count: 8_192)
        let reference = try reduce([samples], chunk: 8_192)
        let underTest = try reduce([samples], chunk: chunk)

        let referenceChannel = try #require(reference.channels.first)
        let channel = try #require(underTest.channels.first)
        #expect(channel.peakSample == referenceChannel.peakSample)
        #expect(channel.clippedSampleCount == referenceChannel.clippedSampleCount)
        // The pre-existing tolerance for these two, not a widened one: vDSP's own grouping still differs
        // between chunk sizes, and this fix neither needs nor claims more than that.
        #expect(relativeError(try #require(channel.rms), try #require(referenceChannel.rms)) < 1e-5)
        #expect(abs(try #require(channel.dcOffset)) < 1e-5 * 1e30)
    }

    /// The whole file in one chunk, which is the boundary the sizes above approach.
    @Test func theWholeFileInOneChunkAgrees() throws {
        let samples = constant(1e20, count: 4_096)
        let single = try reduce([samples], chunk: 4_096)
        let split = try reduce([samples], chunk: 97)
        #expect(try #require(single.channels.first?.peakSample) == (try #require(split.channels.first?.peakSample)))
        #expect(relativeError(
            try #require(single.channels.first?.rms), try #require(split.channels.first?.rms)
        ) < 1e-5)
    }

    // MARK: - The model refuses what cannot describe a measurement

    @Test func theModelRefusesNonFiniteChannelValues() {
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: .infinity, rms: 0.2, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: -.infinity, rms: 0.2, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: .infinity, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: 0.2, dcOffset: .infinity, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: .nan, rms: 0.2, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: .nan, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: 0.2, dcOffset: .nan, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: 0.2, dcOffset: .signalingNaN, clippedSampleCount: 0) == nil)
    }

    /// A maximum of absolute values cannot be negative, and neither can a square root.
    @Test func theModelRefusesNegativeMagnitudes() {
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: -0.5, rms: 0.2, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: -0.2, dcOffset: 0, clippedSampleCount: 0) == nil)
        // A DC offset is a signed mean: negative is not merely allowed, it is the normal case.
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: 0.2, dcOffset: -0.01, clippedSampleCount: 0) != nil)
    }

    /// **Values beyond full scale are still accepted**, and must stay that way: a file genuinely
    /// carrying one is the fact this type exists to report, and true peak reaffirmed the same policy.
    @Test func theModelStillAcceptsValuesBeyondFullScale() throws {
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 10, peakSample: 1.5, rms: 1.2, dcOffset: 0.9, clippedSampleCount: 10
        ))
        #expect(channel.peakSample == 1.5)
        #expect(try #require(SignalLevelMetrics(
            channels: [channel], overallPeakSample: 1.5, overallRMS: 1.2,
            overallDCOffset: 0.9, overallClippedSampleCount: 10
        )).overallPeakSample == 1.5)
    }

    /// The `nil`-iff-empty rule, in both directions — the invariant the type documented and did not
    /// enforce.
    @Test func theModelEnforcesTheNilIffEmptyRule() {
        // Measured but unreported.
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: nil, rms: 0.2, dcOffset: 0, clippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0.5, rms: nil, dcOffset: 0, clippedSampleCount: 0) == nil)
        // Unmeasured yet reported.
        #expect(SignalLevelMetrics.Channel(sampleCount: 0, peakSample: 0.5, rms: nil, dcOffset: nil, clippedSampleCount: 0) == nil)
        // Both legitimate shapes.
        #expect(SignalLevelMetrics.Channel(sampleCount: 0, peakSample: nil, rms: nil, dcOffset: nil, clippedSampleCount: 0) != nil)
        #expect(SignalLevelMetrics.Channel(sampleCount: 10, peakSample: 0, rms: 0, dcOffset: 0, clippedSampleCount: 0) != nil)
    }

    @Test func theAggregateRefusesAnEmptyChannelListAndNonFiniteOveralls() throws {
        let valid = try #require(SignalLevelMetrics.Channel(
            sampleCount: 10, peakSample: 0.5, rms: 0.2, dcOffset: 0, clippedSampleCount: 0
        ))
        #expect(SignalLevelMetrics(channels: [], overallPeakSample: nil, overallRMS: nil, overallDCOffset: nil, overallClippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics(channels: [valid], overallPeakSample: .nan, overallRMS: 0.2, overallDCOffset: 0, overallClippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics(channels: [valid], overallPeakSample: 0.5, overallRMS: .infinity, overallDCOffset: 0, overallClippedSampleCount: 0) == nil)
        #expect(SignalLevelMetrics(channels: [valid], overallPeakSample: 0.5, overallRMS: 0.2, overallDCOffset: .nan, overallClippedSampleCount: 0) == nil)
    }

    // MARK: - The whole production path, on the audio that used to break it

    /// **The end-to-end guarantee**: extreme audio through the real shared read produces a measurement
    /// that is available *and* finite — never an `.available` model carrying a value that cannot exist.
    @Test func theSharedReadNeverPublishesANonFiniteMeasurement() async throws {
        let frames = 8_192
        let extreme = alternating(.greatestFiniteMagnitude, count: frames)
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: frames))
        var chunks: [PCMChunk] = []
        var start = 0
        while start < frames {
            let end = min(start + 1_024, frames)
            chunks.append(try PCMChunk(startFrame: start, channels: [Array(extreme[start ..< end])]))
            start = end
        }

        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: chunks)
        ).run(for: AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        ))

        guard case let .available(metrics) = outcome.signalLevelMetrics else {
            Issue.record("extreme-but-finite audio produced \(outcome.signalLevelMetrics)"); return
        }
        for channel in metrics.channels {
            #expect(try #require(channel.peakSample).isFinite)
            #expect(try #require(channel.rms).isFinite)
            #expect(try #require(channel.dcOffset).isFinite)
        }
        #expect(try #require(metrics.overallRMS).isFinite)
        #expect(try #require(metrics.overallDCOffset) == 0)

        // The neighbours are untouched by this: true peak still answers for itself on the same audio.
        guard case .failed = outcome.truePeak else {
            Issue.record("true peak's own outcome changed: \(outcome.truePeak)"); return
        }
    }

    /// And the document it produces carries real numbers — the failure mode that made this defect
    /// visible in the first place.
    @Test func theExportedDocumentCarriesFiniteNumbers() async throws {
        let frames = 4_096
        let extreme = constant(1e30, count: frames)
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: frames))
        let chunks = [try PCMChunk(startFrame: 0, channels: [extreme])]

        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: chunks)
        ).run(for: AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        ))
        guard case let .available(metrics) = outcome.signalLevelMetrics else {
            Issue.record("expected available metrics, got \(outcome.signalLevelMetrics)"); return
        }

        // It encodes at all — a non-finite value would throw here rather than reach a consumer.
        let data = try exportData(report(status: .completed), signalLevelMetrics: metrics)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("inf"))
        #expect(!json.lowercased().contains("nan"))

        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let rms = try #require(value["measurements"]?["signalLevels"]?["overall"]?["rms"]?.double)
        #expect(rms.isFinite)
        #expect(relativeError(Float(rms), 1e30) < 1e-5)
    }

    private func relativeError(_ value: Float, _ expected: Float) -> Float {
        expected == 0 ? abs(value) : abs(value - expected) / abs(expected)
    }
}
