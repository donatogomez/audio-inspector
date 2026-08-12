import Foundation
import Testing

import AudioInspectorDomain

@testable import AudioInspectorAnalysis

/// The reconstruction's rules, over signals whose answer is known **analytically** — no file, no
/// external tool. A tone's true peak *is* its amplitude, and an impulse's reconstruction is a sinc whose
/// maximum is exactly one, so these are checks against arithmetic rather than against a fixture that
/// happens to agree. The FFmpeg cross-check lives in its own gated suite; this one must hold with no
/// tool installed at all.
@Suite("Analysis — true peak reconstruction")
struct TruePeakAccumulatorTests {
    // MARK: - Fixtures, generated in memory

    /// A sine of amplitude `a`. Its continuous maximum is exactly `a`, whatever the phase — which is the
    /// ground truth every tone case below is measured against.
    private func tone(
        frequency: Double, sampleRate: Double, amplitude: Float, phase: Double, frames: Int,
        fadeFrames: Int = 0
    ) -> [Float] {
        (0 ..< frames).map { n in
            let value = Double(amplitude) * sin(2 * .pi * frequency * Double(n) / sampleRate + phase)
            guard fadeFrames > 0 else { return Float(value) }
            let envelope: Double
            if n < fadeFrames {
                envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fadeFrames))
            } else if n >= frames - fadeFrames {
                envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fadeFrames))
            } else {
                envelope = 1
            }
            return Float(value * envelope)
        }
    }

    /// Feeds channels cut into runs of `chunk` frames, exactly as a chunked decoder would.
    private func measure(channels: [[Float]], chunk: Int = 4_096) throws -> TruePeakMeasurement {
        var accumulator = try #require(TruePeakAccumulator(channelCount: channels.count))
        let frameCount = channels.first?.count ?? 0
        var start = 0
        while start < frameCount {
            let end = min(start + chunk, frameCount)
            let piece = try PCMChunk(startFrame: start, channels: channels.map { Array($0[start ..< end]) })
            accumulator.accumulate(piece)
            start = end
        }
        let finished = accumulator.finish()
        return try #require(finished)
    }

    private func decibels(_ value: Float) -> Double { 20 * log10(Double(value)) }

    // MARK: - The filter itself

    @Test("phase 0 is the exact identity, bit for bit")
    func phaseZeroIsTheIdentity() {
        let filter = PolyphaseInterpolationFilter(
            factor: TruePeakAccumulator.oversamplingFactor,
            tapsPerPhase: TruePeakAccumulator.tapsPerPhase,
            beta: TruePeakAccumulator.kaiserBeta,
            cutoff: TruePeakAccumulator.cutoff
        )
        let taps = filter.phase(0)
        let centre = -filter.jMin
        #expect(taps.count == TruePeakAccumulator.tapsPerPhase)
        for (index, tap) in taps.enumerated() {
            // Exact equality on purpose: `0, …, 1, …, 0` is what makes the stored samples members of the
            // set the maximum is taken over, and "close to zero" would not.
            #expect(tap == (index == centre ? Float(1) : Float(0)))
        }
    }

    @Test("sinc uses its exact integer zeros rather than approximating them")
    func sincIsExactAtIntegers() {
        #expect(PolyphaseInterpolationFilter.sinc(0) == 1)
        for k in 1 ... 30 {
            #expect(PolyphaseInterpolationFilter.sinc(Double(k)) == 0)
            #expect(PolyphaseInterpolationFilter.sinc(-Double(k)) == 0)
        }
        // Non-integers still go through the real function.
        #expect(abs(PolyphaseInterpolationFilter.sinc(0.5) - 2 / Double.pi) < 1e-12)
    }

    @Test("every phase is normalised to unit sum")
    func phasesAreNormalised() {
        let filter = PolyphaseInterpolationFilter(
            factor: 8, tapsPerPhase: 48, beta: 6.0, cutoff: 1.0
        )
        for phase in 0 ..< 8 {
            let sum = filter.phase(phase).reduce(Float(0), +)
            #expect(abs(sum - 1) < 1e-6)
        }
    }

    @Test("the filter has one tap set per phase and no more")
    func coefficientCount() {
        let filter = PolyphaseInterpolationFilter(factor: 8, tapsPerPhase: 48, beta: 6.0, cutoff: 1.0)
        #expect(filter.coefficients.count == TruePeakAccumulator.coefficientCount)
        #expect(filter.coefficients.count == 384)
    }

    // MARK: - Known signals, known answers

    @Test("silence is a measured zero, not an absence")
    func silence() throws {
        let measured = try measure(channels: [[Float](repeating: 0, count: 4_410)])
        #expect(measured.channels[0].sampleCount == 4_410)
        #expect(measured.channels[0].truePeak == 0)
        #expect(measured.overallTruePeak == 0)
    }

    @Test("a crest that lands on a sample reads the amplitude exactly")
    func crestOnSample() throws {
        // f = sr/4 with phase π/2 puts a sample exactly on every crest.
        let samples = tone(
            frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 2,
            frames: 44_100, fadeFrames: 4_410
        )
        let measured = try measure(channels: [samples])
        let peak = try #require(measured.overallTruePeak)
        #expect(abs(decibels(peak) - decibels(0.9)) < 0.05)
    }

    @Test("a crest hidden between samples is recovered, and the stored samples never show it")
    func crestBetweenSamples() throws {
        // The same tone shifted an eighth of a cycle: every stored sample sits at 0.9/√2.
        let samples = tone(
            frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4,
            frames: 44_100, fadeFrames: 4_410
        )
        let samplePeak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let measured = try measure(channels: [samples])
        let truePeak = try #require(measured.overallTruePeak)

        // The stored samples top out ~3 dB below the real waveform, which is the entire reason this
        // measurement exists.
        #expect(abs(decibels(samplePeak) - decibels(Float(0.9 / 2.0.squareRoot()))) < 0.05)
        #expect(abs(decibels(truePeak) - decibels(0.9)) < 0.05)
        #expect(truePeak > samplePeak)
    }

    @Test("a file whose samples stay below full scale can still exceed it")
    func sampleUnderTrueOver() throws {
        let samples = tone(
            frequency: 11_025, sampleRate: 44_100, amplitude: 1.05, phase: .pi / 4,
            frames: 44_100, fadeFrames: 4_410
        )
        let samplePeak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let measured = try measure(channels: [samples])
        let truePeak = try #require(measured.overallTruePeak)
        #expect(samplePeak < 1)
        #expect(truePeak > 1)
        #expect(abs(decibels(truePeak) - decibels(1.05)) < 0.05)
    }

    @Test("an impulse reconstructs to exactly its own height")
    func impulse() throws {
        var samples = [Float](repeating: 0, count: 4_096)
        samples[2_048] = 1
        let measured = try measure(channels: [samples])
        // The band-limited reconstruction of a unit impulse is a sinc, whose maximum is 1 at the sample
        // itself — so an interpolator that invented energy here would be visible immediately.
        #expect(abs(decibels(try #require(measured.overallTruePeak))) < 0.05)
    }

    @Test("a stored sample beyond full scale is measured, never clamped")
    func sampleBeyondFullScale() throws {
        var samples = [Float](repeating: 0, count: 4_410)
        samples[2_205] = 1.5
        let measured = try measure(channels: [samples])
        let peak = try #require(measured.overallTruePeak)
        #expect(peak >= 1.5)
        #expect(peak != 1.0)
    }

    // MARK: - Zero-extension at the file's own edges

    @Test("a full-scale sample at the very first frame is measured, not missed")
    func energyAtFirstFrame() throws {
        var samples = [Float](repeating: 0, count: 4_096)
        samples[0] = 1
        let measured = try measure(channels: [samples])
        let peak = try #require(measured.overallTruePeak)
        // Zero-extension neither loses the sample nor fabricates a peak above it.
        #expect(peak >= 1)
        #expect(abs(decibels(peak)) < 0.05)
    }

    @Test("a full-scale sample at the very last frame is measured, not missed")
    func energyAtLastFrame() throws {
        var samples = [Float](repeating: 0, count: 4_096)
        samples[4_095] = 1
        let measured = try measure(channels: [samples])
        let peak = try #require(measured.overallTruePeak)
        #expect(peak >= 1)
        #expect(abs(decibels(peak)) < 0.05)
    }

    @Test("a truncated tone keeps the overshoot its own boundary produces")
    func truncatedToneKeepsItsBoundaryOvershoot() throws {
        // No fade: the tone starts at 0.636 against the silence outside the file, which is a real
        // discontinuity. A band-limited reconstruction of one genuinely overshoots, and this measurement
        // reports it rather than smoothing it away.
        let samples = tone(
            frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4, frames: 44_100
        )
        let truncated = try #require(try measure(channels: [samples]).overallTruePeak)
        let faded = try #require(try measure(channels: [tone(
            frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4,
            frames: 44_100, fadeFrames: 4_410
        )]).overallTruePeak)
        #expect(truncated > faded)
        // Bounded, though: the overshoot is a fraction of a dB, not a different signal.
        #expect(decibels(truncated) - decibels(0.9) < 0.5)
    }

    // MARK: - truePeak >= samplePeak, by construction

    @Test("the reconstruction is never below the stored samples", arguments: [
        "silence", "on-sample", "between-samples", "impulse", "beyond-full-scale", "first-frame",
        "last-frame", "near-nyquist", "complex",
    ])
    func neverBelowSamplePeak(_ name: String) throws {
        let samples = try signal(named: name)
        let samplePeak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let measured = try measure(channels: [samples])
        let truePeak = try #require(measured.overallTruePeak)
        // Not `>= samplePeak - tolerance`: the identity phase puts the stored samples inside the set the
        // maximum is taken over, so this is exact.
        #expect(truePeak >= samplePeak)
    }

    private func signal(named name: String) throws -> [Float] {
        switch name {
        case "silence": [Float](repeating: 0, count: 4_410)
        case "on-sample": tone(frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 2, frames: 8_820)
        case "between-samples": tone(frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4, frames: 8_820)
        case "impulse": { var s = [Float](repeating: 0, count: 4_096); s[2_048] = 1; return s }()
        case "beyond-full-scale": { var s = [Float](repeating: 0, count: 4_410); s[2_205] = 1.5; return s }()
        case "first-frame": { var s = [Float](repeating: 0, count: 4_096); s[0] = 1; return s }()
        case "last-frame": { var s = [Float](repeating: 0, count: 4_096); s[4_095] = 1; return s }()
        case "near-nyquist": tone(frequency: 19_845, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4, frames: 8_820)
        default: (0 ..< 8_820).map { n in
                let t = Double(n) / 44_100
                var value = 0.0
                for partial in 1 ... 8 { value += sin(2 * .pi * 220 * Double(partial) * t) / Double(partial) }
                return Float(value * 0.4)
            }
        }
    }

    // MARK: - Chunk independence, bit for bit

    @Test("the result is identical at every chunk size, bit for bit")
    func chunkIndependence() throws {
        for name in ["between-samples", "first-frame", "last-frame", "impulse", "complex"] {
            let samples = try signal(named: name)
            let whole = try measure(channels: [samples], chunk: samples.count)
            for chunk in [1, 3, 127, 512, 2_048, 4_096, 65_536] {
                let streamed = try measure(channels: [samples], chunk: chunk)
                // Equality, not a tolerance: each output point sees the same 48 taps and the same 48
                // samples however the file was cut, and a maximum accumulates nothing for a different
                // grouping to round differently.
                #expect(streamed == whole, "\(name) at chunk \(chunk)")
            }
        }
    }

    @Test("chunk independence holds for a stereo signal too")
    func chunkIndependenceStereo() throws {
        let left = try signal(named: "between-samples")
        let right = try signal(named: "near-nyquist")
        let whole = try measure(channels: [left, right], chunk: left.count)
        for chunk in [1, 127, 4_096] {
            #expect(try measure(channels: [left, right], chunk: chunk) == whole)
        }
    }

    @Test("two runs over the same input give the same answer")
    func determinism() throws {
        let samples = try signal(named: "complex")
        #expect(try measure(channels: [samples]) == (try measure(channels: [samples])))
    }

    // MARK: - Channels

    @Test("channels are measured independently and keep their order")
    func perChannelIndependence() throws {
        let loud = tone(frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4, frames: 8_820, fadeFrames: 882)
        let quiet = tone(frequency: 1_000, sampleRate: 44_100, amplitude: 0.2, phase: 0, frames: 8_820, fadeFrames: 882)
        let measured = try measure(channels: [loud, quiet])
        let first = try #require(measured.channels[0].truePeak)
        let second = try #require(measured.channels[1].truePeak)
        #expect(abs(decibels(first) - decibels(0.9)) < 0.05)
        #expect(abs(decibels(second) - decibels(0.2)) < 0.05)
        #expect(measured.overallTruePeak == first)
    }

    @Test("a channel measured alone gives the same value as when measured beside another")
    func channelsDoNotInfluenceEachOther() throws {
        let loud = try signal(named: "between-samples")
        let other = try signal(named: "near-nyquist")
        let alone = try measure(channels: [loud])
        let together = try measure(channels: [loud, other])
        // No mixdown, and no maximum taken across channels before interpolating: channel 0's own value
        // is untouched by what channel 1 contained.
        #expect(together.channels[0].truePeak == alone.channels[0].truePeak)
    }

    @Test("six channels are each measured on their own")
    func multichannel() throws {
        let amplitudes: [Float] = [0.1, 0.9, 0.2, 0.44, 0.3, 0.05]
        let channels = amplitudes.map {
            tone(frequency: 5_000, sampleRate: 44_100, amplitude: $0, phase: .pi / 4, frames: 8_820, fadeFrames: 882)
        }
        let measured = try measure(channels: channels)
        #expect(measured.channels.count == 6)
        for (index, amplitude) in amplitudes.enumerated() {
            let value = try #require(measured.channels[index].truePeak)
            #expect(abs(decibels(value) - decibels(amplitude)) < 0.05)
        }
        #expect(measured.overallTruePeak == measured.channels[1].truePeak)
    }

    // MARK: - Sample rates

    @Test("the same geometry reads the same at every supported rate", arguments: [
        44_100.0, 48_000.0, 96_000.0, 192_000.0,
    ])
    func everySampleRate(_ rate: Double) throws {
        // A tone at sr/4 with a crest between samples: identical geometry at every rate, so the answer
        // must be identical too. **192 kHz is checked here against analytic truth only** — FFmpeg does
        // not oversample at that rate and cannot serve as an oracle for it (spike §E).
        let frames = Int(rate / 10)
        let samples = tone(
            frequency: rate / 4, sampleRate: rate, amplitude: 0.9, phase: .pi / 4,
            frames: frames, fadeFrames: frames / 10
        )
        let measured = try measure(channels: [samples])
        let peak = try #require(measured.overallTruePeak)
        #expect(abs(decibels(peak) - decibels(0.9)) < 0.05)
    }

    // MARK: - Zero frames

    @Test("a stream that delivered no audio reports no value, not a zero")
    func zeroFrames() throws {
        var accumulator = try #require(TruePeakAccumulator(channelCount: 2))
        let finished = accumulator.finish()
        let measured = try #require(finished)
        #expect(measured.channels.count == 2)
        #expect(measured.channels.allSatisfy { $0.sampleCount == 0 })
        #expect(measured.channels.allSatisfy { $0.truePeak == nil })
        #expect(measured.overallTruePeak == nil)
    }

    @Test("empty chunks do not turn an unmeasured stream into a measured one")
    func emptyChunksChangeNothing() throws {
        var accumulator = try #require(TruePeakAccumulator(channelCount: 1))
        accumulator.accumulate(try PCMChunk(startFrame: 0, channels: [[]]))
        let finished = accumulator.finish()
        let measured = try #require(finished)
        #expect(measured.channels[0].sampleCount == 0)
        #expect(measured.channels[0].truePeak == nil)
    }

    @Test("a file shorter than the filter is still measured")
    func fileShorterThanTheFilter() throws {
        // Fewer frames than the 48-tap window: the whole signal lives inside the zero-extension, and it
        // must still produce a value rather than falling through the streaming logic.
        let measured = try measure(channels: [[0.5, -0.75, 0.25]])
        #expect(measured.channels[0].sampleCount == 3)
        let peak = try #require(measured.channels[0].truePeak)
        #expect(peak >= 0.75)
    }

    // MARK: - Guards

    @Test("a chunk whose channel count disagrees is ignored rather than folded into the wrong channel")
    func mismatchedChunkIsIgnored() throws {
        var accumulator = try #require(TruePeakAccumulator(channelCount: 2))
        accumulator.accumulate(try PCMChunk(startFrame: 0, channels: [[1, 1, 1, 1]]))
        let finished = accumulator.finish()
        let measured = try #require(finished)
        #expect(measured.channels.allSatisfy { $0.sampleCount == 0 })
    }

    @Test("a channel count no stream can have is refused")
    func invalidChannelCount() {
        #expect(TruePeakAccumulator(channelCount: 0) == nil)
        #expect(TruePeakAccumulator(channelCount: -1) == nil)
    }

    // MARK: - The method travels with the result

    @Test("the measurement records the factor and filter that produced it")
    func methodIsRecorded() throws {
        let measured = try measure(channels: [try signal(named: "complex")])
        #expect(measured.method.oversamplingFactor == 8)
        #expect(measured.method.filter == .polyphaseFIRv1)
        #expect(measured.method.filter.rawValue == "polyphase_fir_v1")
    }

    // MARK: - Float is enough

    @Test("the Float convolution matches a Double reference to the difference the spike measured")
    func floatMatchesDoubleReference() throws {
        let samples = try signal(named: "between-samples")
        let measured = try #require(try measure(channels: [samples]).overallTruePeak)
        let reference = doubleReferencePeak(samples)
        // The spike measured at most 1.9e-7 linear across 21 fixtures; this keeps that bound honest
        // against the production path rather than restating it.
        #expect(abs(Double(measured) - reference) < 1e-6)
    }

    /// A deliberately slow, obvious `Double` reconstruction — no vDSP, no streaming, no reuse. It exists
    /// only to be disagreed with, so it is written the least clever way possible.
    private func doubleReferencePeak(_ samples: [Float]) -> Double {
        let filter = PolyphaseInterpolationFilter(factor: 8, tapsPerPhase: 48, beta: 6.0, cutoff: 1.0)
        let taps = 48
        let jMin = filter.jMin
        var peak = 0.0
        for n in 0 ..< samples.count {
            for phase in 0 ..< 8 {
                let coefficients = filter.phase(phase)
                var accumulator = 0.0
                for t in 0 ..< taps {
                    let index = n + jMin + t
                    guard index >= 0, index < samples.count else { continue }
                    accumulator += Double(coefficients[t]) * Double(samples[index])
                }
                peak = max(peak, abs(accumulator))
            }
        }
        return peak
    }
}
