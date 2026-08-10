import Foundation
import Testing

import AudioInspectorDomain

@testable import AudioInspectorAnalysis

/// The reduction's rules, over plain numbers and hand-built chunks — no real file, no framework beyond
/// what the accumulator itself needs. Mirrors `WaveformEnvelopeAccumulatorTests`' own shape: these are
/// the assertions that keep the four metrics honest, written so they cannot be weakened later by a
/// fixture that happens to agree.
@Suite("Analysis — signal level metrics reduction")
struct SignalLevelMetricsAccumulatorTests {
    /// Feeds one or more channels, cut into runs of `chunk` frames each, exactly as a chunked decoder
    /// would. `channels[c][f]` is channel `c`'s sample at frame `f`; every channel must be the same
    /// length.
    private func reduce(channels: [[Float]], chunk: Int) throws -> SignalLevelMetrics {
        var accumulator = try #require(SignalLevelMetricsAccumulator(channelCount: channels.count))
        let frameCount = channels.first?.count ?? 0
        var start = 0
        while start < frameCount {
            let end = min(start + chunk, frameCount)
            let piece = try PCMChunk(startFrame: start, channels: channels.map { Array($0[start ..< end]) })
            accumulator.accumulate(piece)
            start = end
        }
        return accumulator.finish()
    }

    // MARK: - Known signals, known answers

    @Test func silenceIsAllZerosNotAbsent() throws {
        let metrics = try reduce(channels: [[0, 0, 0, 0, 0]], chunk: 4096)
        let channel = try #require(metrics.channels.first)
        #expect(channel.sampleCount == 5)
        #expect(channel.peakSample == 0)
        #expect(channel.rms == 0)
        #expect(channel.dcOffset == 0)
        #expect(channel.clippedSampleCount == 0)
    }

    @Test func constantPositiveSignal() throws {
        let metrics = try reduce(channels: [[Float](repeating: 0.5, count: 1000)], chunk: 4096)
        let channel = try #require(metrics.channels.first)
        #expect(channel.peakSample == 0.5)
        #expect(channel.rms == 0.5) // RMS of a constant equals the constant's magnitude
        #expect(channel.dcOffset == 0.5)
        #expect(channel.clippedSampleCount == 0)
    }

    @Test func constantNegativeSignal() throws {
        let metrics = try reduce(channels: [[Float](repeating: -0.5, count: 1000)], chunk: 4096)
        let channel = try #require(metrics.channels.first)
        #expect(channel.peakSample == 0.5) // magnitude, not signed
        #expect(channel.rms == 0.5)        // RMS is never negative
        #expect(channel.dcOffset == -0.5)  // DC offset keeps the sign
        #expect(channel.clippedSampleCount == 0)
    }

    /// A full-period sine has RMS = amplitude/√2 and DC offset ≈ 0. Built at exactly 100 samples per
    /// period so the average is over whole periods, keeping the residual DC offset at floating-point
    /// noise rather than a partial-period artefact.
    @Test func sineWaveHasTheStandardRMSRatio() throws {
        let amplitude: Float = 0.8
        let periods = 50
        let samplesPerPeriod = 100
        var samples: [Float] = []
        for i in 0 ..< (periods * samplesPerPeriod) {
            samples.append(amplitude * sin(2 * Float.pi * Float(i) / Float(samplesPerPeriod)))
        }
        let metrics = try reduce(channels: [samples], chunk: 4096)
        let channel = try #require(metrics.channels.first)
        let expectedRMS = amplitude / Float(2.0).squareRoot()
        #expect(abs((channel.rms ?? -1) - expectedRMS) < 0.001)
        #expect(abs(channel.dcOffset ?? -1) < 0.0001)
        #expect(abs((channel.peakSample ?? -1) - amplitude) < 0.01)
    }

    @Test func samplesExactlyAtFullScaleAreClipped() throws {
        let metrics = try reduce(channels: [[1.0, -1.0, 0.5, -0.5]], chunk: 4096)
        let channel = try #require(metrics.channels.first)
        #expect(channel.clippedSampleCount == 2) // exactly ±1.0 counts — the threshold is inclusive
        #expect(channel.peakSample == 1.0)
    }

    /// Kept exactly as read, never clamped — inherited from `PCMChunk`'s own contract. A sample beyond
    /// full scale is real, both as a peak above `1.0` and as a clipped sample.
    @Test func samplesBeyondFullScaleAreKeptNotClampedAndCountAsClipped() throws {
        let metrics = try reduce(channels: [[1.5, -1.3, 0.1]], chunk: 4096)
        let channel = try #require(metrics.channels.first)
        #expect(channel.peakSample == 1.5) // not clamped to 1.0
        #expect(channel.clippedSampleCount == 2)
    }

    @Test func stereoChannelsAreIndependent() throws {
        let metrics = try reduce(
            channels: [
                [Float](repeating: 0.2, count: 100),
                [Float](repeating: 0.9, count: 100),
            ],
            chunk: 4096
        )
        #expect(metrics.channels.count == 2)
        #expect(metrics.channels[0].peakSample == 0.2)
        #expect(metrics.channels[1].peakSample == 0.9)
        #expect(metrics.channels[0].clippedSampleCount == 0)
        #expect(metrics.channels[1].clippedSampleCount == 0)
    }

    /// Opposite polarity between channels must not cancel — each channel's own DC offset and peak stay
    /// its own, unlike a downmix that would average them toward zero.
    @Test func oppositePolarityChannelsDoNotCancel() throws {
        let metrics = try reduce(
            channels: [
                [Float](repeating: 0.6, count: 100),
                [Float](repeating: -0.6, count: 100),
            ],
            chunk: 4096
        )
        #expect(metrics.channels[0].dcOffset == 0.6)
        #expect(metrics.channels[1].dcOffset == -0.6)
        #expect(metrics.channels[0].peakSample == 0.6)
        #expect(metrics.channels[1].peakSample == 0.6)
    }

    // MARK: - Zero frames: not computable, not a computed zero

    @Test func zeroFramesIsNotComputableNotZero() throws {
        let accumulator = try #require(SignalLevelMetricsAccumulator(channelCount: 2))
        let metrics = accumulator.finish() // never fed a single chunk
        for channel in metrics.channels {
            #expect(channel.sampleCount == 0)
            #expect(channel.peakSample == nil)
            #expect(channel.rms == nil)
            #expect(channel.dcOffset == nil)
            #expect(channel.clippedSampleCount == 0) // counting is defined even over nothing
        }
        #expect(metrics.overallPeakSample == nil)
        #expect(metrics.overallRMS == nil)
        #expect(metrics.overallDCOffset == nil)
        #expect(metrics.overallClippedSampleCount == 0)
    }

    @Test func invalidChannelCountFailsConstruction() {
        #expect(SignalLevelMetricsAccumulator(channelCount: 0) == nil)
        #expect(SignalLevelMetricsAccumulator(channelCount: -1) == nil)
    }

    // MARK: - Chunk-size and order independence

    /// **Peak, the clip count and the sample count are bit-exact regardless of chunking** — a maximum
    /// and a count are exact, order-independent reductions, with no arithmetic combination for a
    /// grouping to change. **RMS and DC offset are independent only up to floating-point rounding**,
    /// documented honestly rather than assumed: `vDSP_sve`/`vDSP_svesq` compute each chunk's own partial
    /// sum in `Float32` internally, and *how* a chunk's elements are paired during that reduction is
    /// vDSP's own implementation detail, not this accumulator's — different chunk boundaries feed vDSP
    /// different groupings, which legitimately round differently in the last bit or two of each partial
    /// sum before it is widened to `Double` and added to the running total. `1e-5` is derived from that
    /// mechanism, not chosen to make the test pass: a `Float32` partial sum over up to 4096 elements has
    /// a relative rounding bound on the order of `sqrt(n) × 1.19×10⁻⁷ ≈ 8×10⁻⁶`, and the values compared
    /// here are of order `10⁻¹`, so an absolute tolerance one order above that bound is tight, not loose.
    @Test("the result is identical whatever the chunk size", arguments: [1, 3, 127, 512, 4096, 65536])
    func chunkSizeIndependence(chunk: Int) throws {
        var samples: [Float] = []
        for i in 0 ..< 10_000 {
            samples.append(0.4 * sin(Float(i) * 0.01) + 0.05)
        }
        let reference = try reduce(channels: [samples], chunk: 4096)
        let underTest = try reduce(channels: [samples], chunk: chunk)
        #expect(underTest.channels[0].peakSample == reference.channels[0].peakSample)
        #expect(abs((underTest.channels[0].rms ?? .nan) - (reference.channels[0].rms ?? .nan)) < 1e-5)
        #expect(abs((underTest.channels[0].dcOffset ?? .nan) - (reference.channels[0].dcOffset ?? .nan)) < 1e-5)
        #expect(underTest.channels[0].clippedSampleCount == reference.channels[0].clippedSampleCount)
        #expect(underTest.channels[0].sampleCount == reference.channels[0].sampleCount)
    }

    @Test func determinismAcrossTwoRuns() throws {
        var samples: [Float] = []
        for i in 0 ..< 5_000 { samples.append(sin(Float(i) * 0.03)) }
        let first = try reduce(channels: [samples], chunk: 777)
        let second = try reduce(channels: [samples], chunk: 777)
        #expect(first == second)
    }

    /// A chunk whose channel count disagrees with the accumulator's is ignored — the running totals
    /// stay exactly as they were, never partially updated by a mismatched chunk.
    @Test func mismatchedChannelCountChunkIsIgnoredNotPartiallyApplied() throws {
        var accumulator = try #require(SignalLevelMetricsAccumulator(channelCount: 2))
        let good = try PCMChunk(startFrame: 0, channels: [[0.3, 0.3], [0.3, 0.3]])
        accumulator.accumulate(good)
        let before = accumulator.finish()

        let mismatched = try PCMChunk(startFrame: 2, channels: [[0.9, 0.9, 0.9]]) // one channel, not two
        accumulator.accumulate(mismatched)
        let after = accumulator.finish()

        #expect(before == after) // the mismatched chunk changed nothing
    }

    // MARK: - Overall values: fixed formulas, not naive per-channel averages

    /// The whole point of `overallRMS`: two channels at very different RMS levels combine by treating
    /// every sample equally, which is **not** the same as averaging the two channel RMS values.
    @Test func overallRMSIsNotTheAverageOfPerChannelRMS() throws {
        let metrics = try reduce(
            channels: [
                [Float](repeating: 0.1, count: 100),
                [Float](repeating: 0.9, count: 100),
            ],
            chunk: 4096
        )
        let naiveAverage = ((metrics.channels[0].rms ?? 0) + (metrics.channels[1].rms ?? 0)) / 2
        let overall = try #require(metrics.overallRMS)
        // Closed form for two equal-length constant channels: sqrt((0.1² + 0.9²) / 2) ≈ 0.640.
        let expected = ((0.1 * 0.1 + 0.9 * 0.9) / 2.0).squareRoot()
        #expect(abs(overall - Float(expected)) < 0.0001)
        #expect(abs(overall - naiveAverage) > 0.05) // the naive average is a materially different number
    }

    @Test func overallDCOffsetIsTheCombinedMeanNotTheAverageOfChannelMeans() throws {
        // Unequal sample counts per channel would make a plain average of means wrong; here equal
        // counts still show the combined mean is not simply "the two DC offsets, averaged" once signs
        // and magnitudes differ.
        let metrics = try reduce(
            channels: [
                [Float](repeating: 0.2, count: 300),
                [Float](repeating: -0.8, count: 300),
            ],
            chunk: 4096
        )
        let expected: Float = (0.2 * 300 + (-0.8) * 300) / 600
        #expect(abs((metrics.overallDCOffset ?? 999) - expected) < 0.0001)
    }

    @Test func overallPeakIsTheMaximumOfPerChannelPeaks() throws {
        let metrics = try reduce(
            channels: [
                [Float](repeating: 0.3, count: 10),
                [Float](repeating: 0.95, count: 10),
                [Float](repeating: 0.6, count: 10),
            ],
            chunk: 4096
        )
        #expect(metrics.overallPeakSample == 0.95)
    }

    @Test func overallClippedCountIsTheSumOfPerChannelCounts() throws {
        let metrics = try reduce(
            channels: [
                [1.0, 0.0, 1.0],
                [0.0, 1.0, 0.0],
            ],
            chunk: 4096
        )
        #expect(metrics.channels[0].clippedSampleCount == 2)
        #expect(metrics.channels[1].clippedSampleCount == 1)
        #expect(metrics.overallClippedSampleCount == 3)
    }

    // MARK: - Precision: Double accumulation over a long, realistic file

    /// **Not an arbitrary tolerance, and derived from the actual mechanism, not an idealised one.** The
    /// running total this accumulator keeps is `Double`, which if it summed sample-by-sample would bound
    /// the error at roughly `n × u × |sum|` (`u` = `Double`'s ~2.22 × 10⁻¹⁶) — utterly negligible at
    /// `n` = 10 000 000. The real, measured bound is looser than that, because `vDSP_sve` computes each
    /// **chunk's own partial sum in `Float32`** before it is widened to `Double`: with a 65 536-sample
    /// chunk, that partial sum's own relative rounding is on the order of `sqrt(65536) × 1.19×10⁻⁷ ≈
    /// 3×10⁻⁵`, and roughly 153 such chunks combine (partially cancelling, per a random-walk bound of
    /// `sqrt(153)` rather than summing worst-case) to a relative error on the total of a few × 10⁻⁶ —
    /// which is what running this test actually shows, at odds with the smaller bound `Double`-only
    /// accumulation would have promised. **This is `Float32` reduction error inside vDSP, not `Double`
    /// accumulation error**, and it is still six orders of magnitude tighter than the ~8.8 % divergence
    /// measured for accumulating the same ten million samples in `Float` throughout (checked separately
    /// during design, not implemented here) — the failure mode `Double` accumulation exists to avoid.
    @Test func longFileSmallAmplitudeDCOffsetStaysAccurateInDouble() throws {
        let sampleCount = 10_000_000
        let value: Float = 0.1
        var accumulator = try #require(SignalLevelMetricsAccumulator(channelCount: 1))
        let chunkSize = 65_536
        var start = 0
        while start < sampleCount {
            let end = min(start + chunkSize, sampleCount)
            let chunk = try PCMChunk(startFrame: start, channels: [[Float](repeating: value, count: end - start)])
            accumulator.accumulate(chunk)
            start = end
        }
        let metrics = accumulator.finish()
        let dcOffset = try #require(metrics.channels.first?.dcOffset)
        #expect(abs(dcOffset - value) < 5e-6)
    }

    /// Positive and negative samples of equal magnitude must cancel in the DC offset without leaving a
    /// residual from summation order — this is exactly the case a naive running total handles correctly
    /// only if additions are not silently dropped or reordered.
    @Test func dcOffsetCancelsExactlyBalancedPositiveAndNegativeSamples() throws {
        var samples: [Float] = []
        for _ in 0 ..< 500_000 {
            samples.append(0.37)
            samples.append(-0.37)
        }
        let metrics = try reduce(channels: [samples], chunk: 65536)
        #expect(abs(metrics.channels[0].dcOffset ?? 999) < 1e-6)
    }
}
