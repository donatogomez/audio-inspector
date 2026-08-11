import Foundation

/// A synthetic, fully reproducible fixture. Every sample comes from a formula in this file — no
/// external audio is used as evidence anywhere in this spike.
struct Fixture {
    let name: String
    let sampleRate: Int
    /// `channels[c]` — one channel's samples, in file order.
    let channels: [[Double]]
    /// The continuous waveform's true maximum where it is known **analytically**, not measured.
    /// This is stronger evidence than any oracle, and it exists for the pure-tone and impulse cases.
    let analyticTruePeak: Double?
    let note: String

    var frameCount: Int { channels.first?.count ?? 0 }
    var samplePeak: Double { channels.flatMap { $0 }.reduce(0) { max($0, abs($1)) } }
}

enum Fixtures {
    /// A sine of amplitude `a`: its continuous maximum is exactly `a`, whatever the phase — the
    /// analytic ground truth the whole measurement is checked against.
    static func tone(
        _ name: String, sampleRate: Int, frequency: Double, amplitude: Double, phase: Double,
        frames: Int, note: String
    ) -> Fixture {
        let samples = (0 ..< frames).map { n in
            amplitude * sin(2 * .pi * frequency * Double(n) / Double(sampleRate) + phase)
        }
        return Fixture(
            name: name, sampleRate: sampleRate, channels: [samples],
            analyticTruePeak: amplitude, note: note
        )
    }

    /// Deterministic value noise — a seeded LCG, so the same bytes every run on every machine.
    private struct Random {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    static func all() -> [Fixture] {
        var fixtures: [Fixture] = []

        // 1 — silence.
        fixtures.append(Fixture(
            name: "01-silence", sampleRate: 44_100,
            channels: [[Double](repeating: 0, count: 44_100)],
            analyticTruePeak: 0, note: "measured zero, not 'not computable'"
        ))

        // 2 — a crest that lands exactly on a sample: f = sr/4, phase π/2 → samples ±A, 0.
        fixtures.append(tone(
            "02-tone-crest-on-sample", sampleRate: 44_100, frequency: 11_025, amplitude: 0.9,
            phase: .pi / 2, frames: 44_100, note: "sample peak == true peak == 0.9"
        ))

        // 3 — the same tone shifted by an eighth of a cycle: every sample sits at A/√2.
        fixtures.append(tone(
            "03-tone-crest-between-samples", sampleRate: 44_100, frequency: 11_025, amplitude: 0.9,
            phase: .pi / 4, frames: 44_100, note: "sample peak = 0.9/√2 = 0.6364, true peak = 0.9 (+3.01 dB)"
        ))

        // 4 — near Nyquist: 0.45·sr, where any interpolator is under the most stress.
        fixtures.append(tone(
            "04-tone-near-nyquist", sampleRate: 44_100, frequency: 19_845, amplitude: 0.9,
            phase: .pi / 4, frames: 44_100, note: "0.45·sr — the hardest band for an interpolator"
        ))

        // 5 — sample peak below full scale, true peak above it.
        fixtures.append(tone(
            "05-sample-under-true-over", sampleRate: 44_100, frequency: 11_025, amplitude: 1.05,
            phase: .pi / 4, frames: 44_100, note: "sample peak 0.7425 < 1, true peak 1.05 > 1"
        ))

        // 6 — a stored sample beyond full scale, kept rather than clamped.
        var beyond = (0 ..< 4_410).map { n in 0.5 * sin(2 * .pi * 1_000 * Double(n) / 44_100) }
        beyond[2_205] = 1.5
        fixtures.append(Fixture(
            name: "06-sample-beyond-full-scale", sampleRate: 44_100, channels: [beyond],
            analyticTruePeak: nil, note: "a stored 1.5 — true peak must be >= 1.5"
        ))

        // 7 — a unit impulse. Its band-limited reconstruction is sinc, whose maximum is exactly 1.
        var impulse = [Double](repeating: 0, count: 4_096)
        impulse[2_048] = 1
        fixtures.append(Fixture(
            name: "07-impulse", sampleRate: 44_100, channels: [impulse],
            analyticTruePeak: 1, note: "reconstruction is sinc; max exactly 1.0 at the sample itself"
        ))

        // 8 — a square wave: not band-limited, so the reconstruction genuinely overshoots.
        let square = (0 ..< 44_100).map { n -> Double in
            let cycle = Double(n) * 1_000 / 44_100
            return cycle.truncatingRemainder(dividingBy: 1) < 0.5 ? 0.8 : -0.8
        }
        fixtures.append(Fixture(
            name: "08-square-hard-edges", sampleRate: 44_100, channels: [square],
            analyticTruePeak: nil, note: "hard edges — Gibbs overshoot is real, not an artefact"
        ))

        // 9, 10 — all the energy at the very first / very last frame.
        var firstFrame = [Double](repeating: 0, count: 4_096)
        firstFrame[0] = 1
        fixtures.append(Fixture(
            name: "09-energy-first-frame", sampleRate: 44_100, channels: [firstFrame],
            analyticTruePeak: 1, note: "edge handling must not invent a peak above 1"
        ))
        var lastFrame = [Double](repeating: 0, count: 4_096)
        lastFrame[4_095] = 1
        fixtures.append(Fixture(
            name: "10-energy-last-frame", sampleRate: 44_100, channels: [lastFrame],
            analyticTruePeak: 1, note: "same, at the other end"
        ))

        // 11 — mono is every fixture above; 12 — stereo with genuinely different channels.
        let left = (0 ..< 44_100).map { n in 0.9 * sin(2 * .pi * 11_025 * Double(n) / 44_100 + .pi / 4) }
        let right = (0 ..< 44_100).map { n in 0.3 * sin(2 * .pi * 1_000 * Double(n) / 44_100) }
        fixtures.append(Fixture(
            name: "12-stereo-different-channels", sampleRate: 44_100, channels: [left, right],
            analyticTruePeak: 0.9, note: "left true peak 0.9, right 0.3 — overall is the maximum"
        ))

        // 13–16 — one crest-between-samples tone per supported sample rate, at a fixed fraction of the
        // rate so the geometry is identical and only the rate changes.
        for rate in [44_100, 48_000, 96_000, 192_000] {
            fixtures.append(tone(
                "\(rate == 44_100 ? 13 : rate == 48_000 ? 14 : rate == 96_000 ? 15 : 16)-rate-\(rate)",
                sampleRate: rate, frequency: Double(rate) / 4, amplitude: 0.9, phase: .pi / 4,
                frames: rate, note: "sr/4 tone, crest between samples, true peak 0.9"
            ))
        }

        // 18–21 — the fixtures that separate **edge ringing** from **passband error**, added after the
        // first run showed both the oracle and this spike reading above a tone's own amplitude.
        //
        // A tone that starts abruptly at a non-zero value is discontinuous against the silence outside
        // the file, and a band-limited reconstruction of a discontinuity genuinely overshoots. So the
        // same tone is provided twice: truncated (as above) and with a raised-cosine fade at both ends,
        // which removes the discontinuity while leaving the sustained middle — and its amplitude —
        // untouched. Any error left on the faded version is the filter's own.
        for (label, frequencyRatio) in [("19-faded-sr4", 0.25), ("20-faded-near-nyquist", 0.45)] {
            let frames = 44_100
            let fade = 4_410
            let samples = (0 ..< frames).map { n -> Double in
                let value = 0.9 * sin(2 * .pi * frequencyRatio * Double(n) + .pi / 4)
                let envelope: Double
                if n < fade { envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fade)) }
                else if n >= frames - fade {
                    envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fade))
                } else { envelope = 1 }
                return value * envelope
            }
            fixtures.append(Fixture(
                name: label, sampleRate: 44_100, channels: [samples], analyticTruePeak: 0.9,
                note: "same tone, raised-cosine fade — no truncation discontinuity, so error left is the filter's"
            ))
        }

        // 21–22 — exactly periodic in a power-of-two buffer, so the frequency-domain candidate performs
        // *exact* band-limited interpolation of the periodic extension and becomes a second ground truth
        // independent of both the oracle and the FIR.
        for (label, cycles) in [("21-periodic-sr4", 1_024), ("22-periodic-near-nyquist", 1_843)] {
            let frames = 4_096
            let samples = (0 ..< frames).map { n in
                0.9 * sin(2 * .pi * Double(cycles) * Double(n) / Double(frames) + .pi / 4)
            }
            fixtures.append(Fixture(
                name: label, sampleRate: 44_100, channels: [samples], analyticTruePeak: 0.9,
                note: "\(cycles) whole cycles in 4096 frames — periodic, power of two"
            ))
        }

        // 23 — realistic high-frequency content at a high rate: 15 kHz in a 192 kHz file, where the
        // samples are dense enough that the inter-sample gap is small. The sr/4 fixture at 192 kHz is
        // deliberately adversarial; this one is what real content at that rate looks like.
        fixtures.append(tone(
            "23-192k-realistic-hf", sampleRate: 192_000, frequency: 15_000, amplitude: 0.9,
            phase: .pi / 4, frames: 192_000, note: "15 kHz at 192 kHz — realistic, not adversarial"
        ))

        // 17 — a complex, music-like signal: partials with envelopes, plus seeded noise, normalised so
        // its sample peak sits just under full scale the way a mastered track does.
        var random = Random(state: 0x5EED_1770)
        var complex = [Double](repeating: 0, count: 44_100 * 4)
        for n in 0 ..< complex.count {
            let t = Double(n) / 44_100
            var value = 0.0
            for partial in 1 ... 12 {
                let frequency = 110.0 * Double(partial) * (1 + 0.002 * sin(2 * .pi * 0.7 * t))
                let envelope = exp(-t * Double(partial) * 0.35) * (0.5 + 0.5 * sin(2 * .pi * 1.3 * t))
                value += envelope * sin(2 * .pi * frequency * t) / Double(partial)
            }
            value += 0.02 * random.next()
            complex[n] = value
        }
        let scale = 0.98 / complex.reduce(0) { max($0, abs($1)) }
        complex = complex.map { $0 * scale }
        fixtures.append(Fixture(
            name: "17-complex-programme", sampleRate: 44_100, channels: [complex],
            analyticTruePeak: nil, note: "12 partials + seeded noise, normalised to 0.98 sample peak"
        ))

        return fixtures
    }
}

// MARK: - Writing the fixtures out, by hand

enum WAVWriter {
    /// A canonical RIFF/WAVE file with 32-bit IEEE float samples (format tag 3), interleaved.
    ///
    /// Written byte by byte rather than through a framework: float keeps samples beyond `±1` intact
    /// (a 16-bit file would silently clamp fixture 06), and hand-writing keeps the bytes a function of
    /// this source alone — no framework's own conversion sits between the formula and the oracle.
    static func data(_ fixture: Fixture) -> Data {
        let channelCount = fixture.channels.count
        let frames = fixture.frameCount
        var samples = [Float]()
        samples.reserveCapacity(frames * channelCount)
        for frame in 0 ..< frames {
            for channel in 0 ..< channelCount { samples.append(Float(fixture.channels[channel][frame])) }
        }
        let payload = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + payload.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(3)                                        // IEEE float
        append16(UInt16(channelCount))
        append32(UInt32(fixture.sampleRate))
        append32(UInt32(fixture.sampleRate * channelCount * 4))
        append16(UInt16(channelCount * 4))
        append16(32)
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(payload.count))
        data.append(payload)
        return data
    }
}
