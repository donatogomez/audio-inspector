import Foundation
import Testing

import AudioInspectorDomain

@testable import AudioInspectorAnalysis

/// Cross-checks the production reconstruction against **FFmpeg's `ebur128`** — an independent
/// implementation of the same standard, used strictly as a development/test reference oracle and never
/// shipped (ADR-0003 §3–4).
///
/// ## What this suite may and may not conclude
///
/// The oracle's limits were measured in `docs/spikes/2026-08-11-true-peak-methodology-validation.md`,
/// and each one bounds a test here:
///
/// - **It prints linear values to three decimals** (`lavfi.r128.true_peak`), which puts a hard floor of
///   ±0.0005 linear — about ±0.0048 dB near full scale — under any agreement claim.
/// - **It does not oversample at 192 kHz at all**: its true peak there equals its own sample peak. So
///   **192 kHz is never compared against it**; that rate is covered by analytic truth in
///   `TruePeakAccumulatorTests` instead.
/// - **On signals that are truncated at their boundaries** both meters overshoot, by amounts that depend
///   on their own filters. Those measure edge ringing rather than agreement, so every fixture here is
///   faded — smooth against the silence outside the file.
///
/// Within those bounds the agreement measured was 0.0236 dB worst case, and the tolerance pinned from it
/// is **0.05 dB** (spike §I).
///
/// The stronger check is the analytic one, and it lives in the suite that needs no tool at all. This one
/// is a confirmation against a second implementation — which is why a skip here costs coverage that is
/// nice to have rather than coverage the contract depends on.
@Suite(
    "Analysis — true peak against the FFmpeg oracle (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.isAvailable,
        """
        FFmpeg is not installed on this machine, so no oracle comparison can run. This suite is SKIPPED, \
        and a skipped run is NOT evidence of agreement with an independent R128 implementation. The \
        analytic checks in "Analysis — true peak reconstruction" are unaffected and still ran.
        """
    )
)
struct TruePeakOracleTests {
    /// The tolerance pinned in group 2 from the worst measured agreement plus the oracle's own printing
    /// quantisation. Not widened to make a test pass: 0.0236 dB observed, ±0.0048 dB of oracle
    /// resolution, 0.029 dB credible worst, 0.05 dB adopted.
    private static let toleranceDecibels = 0.05

    // MARK: - Fixtures, written as float WAV so a value beyond ±1 survives

    /// A faded sine: smooth against the silence outside the file, so the comparison measures the two
    /// filters rather than the boundary discontinuity they each ring at.
    private func fadedTone(
        frequency: Double, sampleRate: Double, amplitude: Float, phase: Double, frames: Int
    ) -> [Float] {
        let fade = frames / 10
        return (0 ..< frames).map { n in
            let value = Double(amplitude) * sin(2 * .pi * frequency * Double(n) / sampleRate + phase)
            let envelope: Double
            if n < fade {
                envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fade))
            } else if n >= frames - fade {
                envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fade))
            } else {
                envelope = 1
            }
            return Float(value * envelope)
        }
    }

    /// A canonical RIFF/WAVE file with 32-bit IEEE float samples, written by hand.
    ///
    /// Float rather than 16-bit so a fixture carrying a value beyond `±1` keeps it, and hand-written so
    /// no framework's own conversion sits between the samples the accumulator measured and the bytes the
    /// oracle reads.
    private func writeWAV(_ channels: [[Float]], sampleRate: Int, to url: URL) throws {
        let channelCount = channels.count
        let frames = channels.first?.count ?? 0
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * channelCount)
        for frame in 0 ..< frames {
            for channel in 0 ..< channelCount { interleaved.append(channels[channel][frame]) }
        }
        let payload = interleaved.withUnsafeBufferPointer { Data(buffer: $0) }

        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + payload.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(3)                                   // IEEE float
        append16(UInt16(channelCount))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * channelCount * 4))
        append16(UInt16(channelCount * 4))
        append16(32)
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(payload.count))
        data.append(payload)
        try data.write(to: url)
    }

    /// What the oracle reports for a file: the running maxima it prints as metadata, in **linear**
    /// amplitude.
    private struct OracleReading {
        let truePeak: Double
        let samplePeak: Double
    }

    /// Runs `ebur128` with both peak modes and reads the metadata stream, which is per channel and far
    /// finer than the one-decimal summary block.
    private func oracle(for url: URL) throws -> OracleReading {
        let output = try FFmpegTool.run([
            "-hide_banner", "-nostdin", "-nostats", "-i", url.path,
            "-af", "ebur128=peak=true+sample:metadata=1,ametadata=mode=print:file=-",
            "-f", "null", "-",
        ])
        var truePeak: Double?
        var samplePeak: Double?
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Double(parts[1]) else { continue }
            switch String(parts[0]) {
            case "lavfi.r128.true_peak": truePeak = max(truePeak ?? 0, value)
            case "lavfi.r128.sample_peak": samplePeak = max(samplePeak ?? 0, value)
            default: continue
            }
        }
        guard let truePeak, let samplePeak else {
            throw FFmpegTool.Failure(arguments: ["ebur128"], status: 0, output: output)
        }
        return OracleReading(truePeak: truePeak, samplePeak: samplePeak)
    }

    private func measure(_ channels: [[Float]]) throws -> TruePeakMeasurement {
        var accumulator = try #require(TruePeakAccumulator(channelCount: channels.count))
        let frames = channels.first?.count ?? 0
        var start = 0
        while start < frames {
            let end = min(start + 4_096, frames)
            accumulator.accumulate(try PCMChunk(startFrame: start, channels: channels.map { Array($0[start ..< end]) }))
            start = end
        }
        let finished = accumulator.finish()
        return try #require(finished)
    }

    private func decibels(_ value: Double) -> Double { 20 * log10(value) }

    // MARK: - The comparison

    /// Every supported rate the oracle can actually answer for. **192 kHz is absent by decision**, not by
    /// omission: FFmpeg does not oversample there, so a comparison would measure the oracle's own
    /// limitation and would fail for a reason that says nothing about this code.
    @Test(
        "the reconstruction agrees with FFmpeg on smooth signals at every rate the oracle can judge",
        arguments: [44_100.0, 48_000.0, 96_000.0]
    )
    func agreesWithTheOracle(_ rate: Double) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("true-peak-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let frames = Int(rate / 2)
        // A crest that falls between samples: the case where a sample-peak meter and a true-peak meter
        // must disagree, so agreement here is meaningful rather than trivial.
        let samples = fadedTone(
            frequency: rate / 4, sampleRate: rate, amplitude: 0.9, phase: .pi / 4, frames: frames
        )
        let url = directory.appendingPathComponent("tone.wav")
        try writeWAV([samples], sampleRate: Int(rate), to: url)

        let reading = try oracle(for: url)
        let measured = try #require(try measure([samples]).overallTruePeak)

        let difference = abs(decibels(Double(measured)) - decibels(reading.truePeak))
        #expect(
            difference < Self.toleranceDecibels,
            "at \(Int(rate)) Hz: ours \(measured), oracle \(reading.truePeak), Δ \(difference) dB"
        )
    }

    @Test("the two meters agree on a complex programme, not only on tones")
    func agreesOnComplexProgramme() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("true-peak-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var samples = (0 ..< 44_100).map { n -> Float in
            let t = Double(n) / 44_100
            var value = 0.0
            for partial in 1 ... 12 {
                value += exp(-t * Double(partial) * 0.35) * sin(2 * .pi * 110 * Double(partial) * t) / Double(partial)
            }
            return Float(value)
        }
        let scale = 0.95 / samples.reduce(Float(0)) { max($0, abs($1)) }
        samples = samples.map { $0 * scale }
        // Fade the ends so the comparison stays in the class the tolerance was derived for.
        let fade = 4_410
        for n in 0 ..< fade {
            let envelope = Float(0.5 - 0.5 * cos(.pi * Double(n) / Double(fade)))
            samples[n] *= envelope
            samples[samples.count - 1 - n] *= envelope
        }

        let url = directory.appendingPathComponent("programme.wav")
        try writeWAV([samples], sampleRate: 44_100, to: url)

        let reading = try oracle(for: url)
        let measured = try #require(try measure([samples]).overallTruePeak)
        let difference = abs(decibels(Double(measured)) - decibels(reading.truePeak))
        #expect(difference < Self.toleranceDecibels, "ours \(measured), oracle \(reading.truePeak)")
    }

    @Test("the oracle's own sample peak stays below the true peak both meters report")
    func truePeakExceedsSamplePeakInBothMeters() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("true-peak-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let samples = fadedTone(
            frequency: 11_025, sampleRate: 44_100, amplitude: 0.9, phase: .pi / 4, frames: 44_100
        )
        let url = directory.appendingPathComponent("inter-sample.wav")
        try writeWAV([samples], sampleRate: 44_100, to: url)

        let reading = try oracle(for: url)
        let measured = try #require(try measure([samples]).overallTruePeak)

        // Both implementations see the same phenomenon: the waveform rises above the highest sample.
        #expect(reading.truePeak > reading.samplePeak)
        #expect(Double(measured) > reading.samplePeak)
        // And ours agrees with the oracle's own sample peak about what the samples contain.
        let ourSamplePeak = Double(samples.reduce(Float(0)) { max($0, abs($1)) })
        #expect(abs(ourSamplePeak - reading.samplePeak) < 0.001)
    }

    @Test("the FFmpeg build used is recorded with the evidence")
    func recordsTheOracleVersion() throws {
        let version = try FFmpegTool.versionLine()
        #expect(version.contains("ffmpeg version"))
    }
}
