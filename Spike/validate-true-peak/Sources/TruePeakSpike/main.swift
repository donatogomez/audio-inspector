import Foundation

// The spike's whole output is a printed transcript: tables that go into `docs/spikes/` and numbers that
// settle the open decisions in `add-true-peak-measurement` group 2. Nothing here is imported by
// anything; it is run, read, and deleted.

let arguments = CommandLine.arguments
let outputDirectory = arguments.count > 1 ? arguments[1] : NSTemporaryDirectory() + "true-peak-spike"
let runCost = arguments.contains("--cost")
let runCostQuick = arguments.contains("--cost-quick")
let runCostOnly = arguments.contains("--cost-only")

func heading(_ text: String) {
    print("\n" + String(repeating: "=", count: 96))
    print(text)
    print(String(repeating: "=", count: 96))
}

func decibels(_ linear: Double) -> Double { linear > 0 ? 20 * log10(linear) : -.infinity }

// MARK: - Environment

heading("ENVIRONMENT")
print("ffmpeg: \(Oracle.isAvailable ? Oracle.version() : "NOT AVAILABLE")")
print("output: \(outputDirectory)")

if runCostOnly {
    runCostPhase(quick: true)
    heading("DONE (cost only)")
    exit(0)
}

let fixtures = Fixtures.all()
try? FileManager.default.createDirectory(
    atPath: outputDirectory, withIntermediateDirectories: true
)
for fixture in fixtures {
    let path = "\(outputDirectory)/\(fixture.name).wav"
    try? WAVWriter.data(fixture).write(to: URL(fileURLWithPath: path))
}
print("fixtures written: \(fixtures.count)")
if let first = fixtures.first {
    print("oracle command (example): \(Oracle.command(for: "\(outputDirectory)/\(first.name).wav"))")
}

// MARK: - Phase A — the invariant, proven at its root

heading("PHASE A — phase 0 is the identity, so truePeak >= samplePeak by construction")
do {
    let method = Method.fir(factor: 4)
    let filter = PolyphaseFilter(method: method)
    print("filter: \(method.identifier)")
    print("phase 0 taps: \(filter.phases[0].map { String(format: "%.17g", $0) }.joined(separator: ", "))")

    // Every tap of phase 0 must be exactly 0 except the centre, which must be exactly 1.
    let centre = -filter.jMin
    var exact = true
    for (index, tap) in filter.phases[0].enumerated() {
        let expected = index == centre ? 1.0 : 0.0
        if tap != expected { exact = false }
    }
    print("phase 0 is the exact identity (bit-for-bit): \(exact)")

    // And therefore, over every fixture, the reconstruction is never below the stored samples.
    var worstShortfall = 0.0
    for fixture in fixtures {
        for channel in fixture.channels {
            let samplePeak = channel.reduce(0) { max($0, abs($1)) }
            let truePeak = Reconstruct.peakDouble(channel, filter: filter, edge: .zero)
            worstShortfall = min(worstShortfall, truePeak - samplePeak)
        }
    }
    print("worst (truePeak - samplePeak) over every fixture and channel: \(worstShortfall)")

    // The same filter designed with a cutoff below the original Nyquist: the invariant stops being
    // structural. Measured rather than asserted.
    let lowpass = PolyphaseFilter(method: .fir(factor: 4, cutoff: 0.9))
    print("phase 0 taps with cutoff 0.90: \(lowpass.phases[0].map { String(format: "%.4f", $0) }.joined(separator: ", "))")
    var worstLowpass = 0.0
    for fixture in fixtures {
        for channel in fixture.channels {
            let samplePeak = channel.reduce(0) { max($0, abs($1)) }
            let truePeak = Reconstruct.peakDouble(channel, filter: lowpass, edge: .zero)
            worstLowpass = min(worstLowpass, truePeak - samplePeak)
        }
    }
    print("worst (truePeak - samplePeak) with cutoff 0.90: \(worstLowpass)   <- negative = invariant broken")
}

// MARK: - Phase B — candidates against the analytic truth and the oracle

heading("PHASE B — candidates vs analytic truth vs FFmpeg (44.1 kHz fixtures)")
struct Candidate {
    let label: String
    let method: Method
}

let candidates: [Candidate] = [
    Candidate(label: "FIR 4x 12tap b8.6", method: .fir(factor: 4, tapsPerPhase: 12, beta: 8.6)),
    Candidate(label: "FIR 4x 24tap b12.0", method: .fir(factor: 4, tapsPerPhase: 24, beta: 12.0)),
    Candidate(label: "FIR 4x 32tap b14.0", method: .fir(factor: 4, tapsPerPhase: 32, beta: 14.0)),
    Candidate(label: "FIR 8x 12tap b8.6", method: .fir(factor: 8, tapsPerPhase: 12, beta: 8.6)),
    Candidate(label: "FIR 8x 24tap b12.0", method: .fir(factor: 8, tapsPerPhase: 24, beta: 12.0)),
    Candidate(label: "FIR 16x 24tap b12.0", method: .fir(factor: 16, tapsPerPhase: 24, beta: 12.0)),
]

print("fixture | analytic | oracle | " + candidates.map(\.label).joined(separator: " | "))
for fixture in fixtures {
    let oracle = Oracle.isAvailable
        ? Oracle.measure(path: "\(outputDirectory)/\(fixture.name).wav")?.truePeak
        : nil
    var row = "\(fixture.name) | "
    row += fixture.analyticTruePeak.map { String(format: "%.6f", $0) } ?? "—"
    row += " | " + (oracle.map { String(format: "%.3f", $0) } ?? "—")
    for candidate in candidates {
        let filter = PolyphaseFilter(method: candidate.method)
        let peak = fixture.channels
            .map { Reconstruct.peakDouble($0, filter: filter, edge: .zero) }
            .max() ?? 0
        row += " | " + String(format: "%.6f", peak)
    }
    print(row)
}

heading("PHASE B2 — the same, expressed as dB error against the analytic truth")
print("fixture | " + candidates.map(\.label).joined(separator: " | "))
for fixture in fixtures where fixture.analyticTruePeak != nil && fixture.analyticTruePeak! > 0 {
    var row = "\(fixture.name)"
    for candidate in candidates {
        let filter = PolyphaseFilter(method: candidate.method)
        let peak = fixture.channels
            .map { Reconstruct.peakDouble($0, filter: filter, edge: .zero) }
            .max() ?? 0
        let error = decibels(peak) - decibels(fixture.analyticTruePeak!)
        row += " | " + String(format: "%+.4f", error)
    }
    print(row)
}

heading("PHASE B3 — frequency-domain candidate (power-of-two fixtures only)")
for fixture in fixtures where (fixture.frameCount & (fixture.frameCount - 1)) == 0 {
    let fft = FrequencyDomain.peak(fixture.channels[0], factor: 4)
    let fir = Reconstruct.peakDouble(
        fixture.channels[0], filter: PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: 24, beta: 12)),
        edge: .zero
    )
    print("\(fixture.name): fft-zero-pad 4x = \(fft.map { String(format: "%.6f", $0) } ?? "n/a")"
        + "   fir 4x/24tap = \(String(format: "%.6f", fir))"
        + "   analytic = \(fixture.analyticTruePeak.map { String(format: "%.6f", $0) } ?? "—")")
}

// MARK: - Phase C — the factor, per sample rate

heading("PHASE C — oversampling factor per sample rate (crest-between-samples tone, analytic = 0.9)")
print("rate | factor | true peak | dB error vs analytic | oracle | dB vs oracle")
for rate in [44_100, 48_000, 96_000, 192_000] {
    guard let fixture = fixtures.first(where: { $0.name.hasSuffix("rate-\(rate)") }) else { continue }
    let oracle = Oracle.isAvailable
        ? Oracle.measure(path: "\(outputDirectory)/\(fixture.name).wav")?.truePeak
        : nil
    for factor in [2, 4, 8, 16] {
        let filter = PolyphaseFilter(method: .fir(factor: factor, tapsPerPhase: 24, beta: 12))
        let peak = Reconstruct.peakDouble(fixture.channels[0], filter: filter, edge: .zero)
        let analyticError = decibels(peak) - decibels(fixture.analyticTruePeak ?? 1)
        let oracleError = oracle.map { decibels(peak) - decibels($0) }
        print("\(rate) | \(factor)x | \(String(format: "%.6f", peak)) | \(String(format: "%+.4f", analyticError))"
            + " | \(oracle.map { String(format: "%.3f", $0) } ?? "—")"
            + " | \(oracleError.map { String(format: "%+.4f", $0) } ?? "—")")
    }
}

// MARK: - Phase C2 — the factor's own limit: worst case over the signal's phase

heading("PHASE C2 — worst under-read over 64 signal phases (faded tone, interior-only, 48tap/b6)")
print("A factor L evaluates the reconstruction every 1/L of a sample, so a crest can fall between two")
print("evaluated points. This sweeps the tone's phase to find the worst case that geometry allows —")
print("the number that actually decides the factor, unlike a single lucky or unlucky phase.")
print("f/Nyquist | 2x | 4x | 8x | 16x")
for ratio in [0.10, 0.25, 0.50, 0.70, 0.85, 0.90] {
    var row = String(format: "%.2f", ratio)
    for factor in [2, 4, 8, 16] {
        let filter = PolyphaseFilter(method: .fir(factor: factor, tapsPerPhase: 48, beta: 6))
        var worst = 0.0
        for step in 0 ..< 64 {
            let phase = 2 * Double.pi * Double(step) / 64
            let frames = 8_000
            let fade = 1_000
            let samples = (0 ..< frames).map { n -> Double in
                let value = 0.9 * sin(2 * .pi * (ratio / 2) * Double(n) + phase)
                let envelope: Double
                if n < fade { envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fade)) }
                else if n >= frames - fade {
                    envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fade))
                } else { envelope = 1 }
                return value * envelope
            }
            let peak = Reconstruct.peakDouble(samples, filter: filter, edge: .interiorOnly)
            worst = min(worst, decibels(peak) - decibels(0.9))
        }
        row += " | " + String(format: "%+.4f", worst)
    }
    print(row)
}

// MARK: - Phase D — edge handling

heading("PHASE D — edge handling, every fixture (analytic where known)")
print("fixture | analytic | zero | mirror | constant | interior-only")
for fixture in fixtures {
    let filter = PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: 24, beta: 12))
    var row = fixture.name + " | " + (fixture.analyticTruePeak.map { String(format: "%.6f", $0) } ?? "—")
    for edge in [EdgeHandling.zero, .mirror, .constant, .interiorOnly] {
        let peak = fixture.channels.map { Reconstruct.peakDouble($0, filter: filter, edge: edge) }.max() ?? 0
        row += " | " + String(format: "%.6f", peak)
    }
    print(row)
}

// MARK: - Phase D2 — is the overshoot the edge, or the filter?

heading("PHASE D2 — truncated vs faded vs periodic: separating edge ringing from passband error")
print("fixture | taps | zero-pad | interior-only | fft-4x | analytic")
for name in ["03-tone-crest-between-samples", "19-faded-sr4", "21-periodic-sr4",
             "04-tone-near-nyquist", "20-faded-near-nyquist", "22-periodic-near-nyquist"] {
    guard let fixture = fixtures.first(where: { $0.name == name }) else { continue }
    for taps in [12, 24, 32] {
        let beta = taps == 12 ? 8.6 : taps == 24 ? 12.0 : 14.0
        let filter = PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: taps, beta: beta))
        let padded = Reconstruct.peakDouble(fixture.channels[0], filter: filter, edge: .zero)
        let interior = Reconstruct.peakDouble(fixture.channels[0], filter: filter, edge: .interiorOnly)
        let fft = FrequencyDomain.peak(fixture.channels[0], factor: 4)
        print("\(name) | \(taps) | \(String(format: "%.6f", padded)) | \(String(format: "%.6f", interior))"
            + " | \(fft.map { String(format: "%.6f", $0) } ?? "n/a")"
            + " | \(fixture.analyticTruePeak.map { String(format: "%.6f", $0) } ?? "—")")
    }
}

// MARK: - Phase D3 — the frequency sweep that separates filter droop from grid coarseness

heading("PHASE D3 — dB error vs a faded tone's own amplitude, by frequency (interior-only, no edges)")
print("A tone's true peak IS its amplitude. Under-reading has two possible causes and this separates")
print("them: raising the factor fixes only a grid too coarse to land near the crest; error that")
print("survives every factor is the filter's own passband droop.")
print("f/Nyquist | 12t/4x | 24t/4x | 32t/4x | 48t/4x | 48t/8x | 64t/4x | 96t/4x | 48t/16x")
for ratio in [0.05, 0.10, 0.25, 0.50, 0.70, 0.80, 0.85, 0.90, 0.95, 0.98] {
    let frames = 40_000
    let fade = 4_000
    let amplitude = 0.9
    let samples = (0 ..< frames).map { n -> Double in
        let value = amplitude * sin(2 * .pi * (ratio / 2) * Double(n) + .pi / 4)
        let envelope: Double
        if n < fade { envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fade)) }
        else if n >= frames - fade {
            envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fade))
        } else { envelope = 1 }
        return value * envelope
    }
    var row = String(format: "%.2f", ratio)
    let designs: [(Int, Double, Int)] = [
        (12, 6.0, 4), (24, 6.0, 4), (32, 6.0, 4), (48, 6.0, 4),
        (48, 6.0, 8), (64, 6.0, 4), (96, 6.0, 4), (48, 6.0, 16),
    ]
    for (taps, beta, factor) in designs {
        let filter = PolyphaseFilter(method: .fir(factor: factor, tapsPerPhase: taps, beta: beta))
        let peak = Reconstruct.peakDouble(samples, filter: filter, edge: .interiorOnly)
        row += " | " + String(format: "%+.4f", decibels(peak) - decibels(amplitude))
    }
    print(row)
}

// MARK: - Phase D4 — the filter's own response, computed from its coefficients

heading("PHASE D4 — diagnosis: is the shortfall the filter's gain, or the grid?")
do {
    // The polyphase interpolator's effective prototype, read at the oversampled rate.
    func response(_ filter: PolyphaseFilter, atInputFrequency f: Double) -> Double {
        // Phase p, tap j contributes at oversampled time (j - p/L) relative to the output point.
        var real = 0.0
        var imaginary = 0.0
        for (phase, taps) in filter.phases.enumerated() {
            let delta = Double(phase) / Double(filter.factor)
            for (index, tap) in taps.enumerated() {
                let j = Double(index + filter.jMin)
                let angle = 2 * .pi * f * (j - delta)
                real += tap * cos(angle)
                imaginary += tap * sin(angle)
            }
        }
        // Averaged over the L phases: each output point uses one phase, so the per-phase gain is what
        // matters. Report the worst phase instead of the sum.
        var worst = 0.0
        var best = 0.0
        for (phase, taps) in filter.phases.enumerated() {
            let delta = Double(phase) / Double(filter.factor)
            var r = 0.0
            var i = 0.0
            for (index, tap) in taps.enumerated() {
                let j = Double(index + filter.jMin)
                let angle = 2 * .pi * f * (j - delta)
                r += tap * cos(angle)
                i += tap * sin(angle)
            }
            let magnitude = (r * r + i * i).squareRoot()
            worst = phase == 0 ? magnitude : min(worst, magnitude)
            best = max(best, magnitude)
        }
        _ = (real, imaginary)
        return best == 0 ? 0 : worst / 1.0
    }

    print("f/Nyquist | 12tap gain (dB) | 24tap gain (dB) | 48tap gain (dB)")
    for ratio in [0.05, 0.25, 0.50, 0.70, 0.80, 0.90, 0.95, 0.98, 1.00] {
        let f = ratio / 2   // cycles per input sample
        var row = String(format: "%.2f", ratio)
        for (taps, beta) in [(12, 8.6), (24, 12.0), (48, 16.0)] {
            let filter = PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: taps, beta: beta))
            row += " | " + String(format: "%+.5f", 20 * log10(max(response(filter, atInputFrequency: f), 1e-12)))
        }
        print(row)
    }

    // And the per-phase maxima on one hard case, to see whether any phase beats phase 0.
    let frames = 40_000
    let fade = 4_000
    let ratio = 0.90
    let samples = (0 ..< frames).map { n -> Double in
        let value = 0.9 * sin(2 * .pi * (ratio / 2) * Double(n) + .pi / 4)
        let envelope: Double
        if n < fade { envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fade)) }
        else if n >= frames - fade { envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fade)) }
        else { envelope = 1 }
        return value * envelope
    }
    for factor in [4, 8, 16, 32] {
        let filter = PolyphaseFilter(method: .fir(factor: factor, tapsPerPhase: 24, beta: 12))
        var perPhase = [Double](repeating: 0, count: factor)
        let taps = filter.tapsPerPhase
        for n in (-filter.jMin) ..< (samples.count - (filter.jMin + taps - 1)) {
            for (phase, coefficients) in filter.phases.enumerated() {
                var accumulator = 0.0
                for t in 0 ..< taps { accumulator += coefficients[t] * samples[n + t + filter.jMin] }
                perPhase[phase] = max(perPhase[phase], abs(accumulator))
            }
        }
        let best = perPhase.max() ?? 0
        print("factor \(factor)x at 0.90·Nyquist: phase0=\(String(format: "%.6f", perPhase[0]))"
            + " best=\(String(format: "%.6f", best)) (\(String(format: "%+.4f", decibels(best) - decibels(0.9))) dB vs analytic)")
    }
}

// MARK: - Phase D5 — the design sweep, chosen from measurement

heading("PHASE D5 — filter design sweep: worst per-phase gain deviation across the band")
do {
    func gain(_ filter: PolyphaseFilter, _ f: Double) -> Double {
        var worst = 1.0
        var loudest = 0.0
        for (phase, taps) in filter.phases.enumerated() {
            let delta = Double(phase) / Double(filter.factor)
            var r = 0.0
            var i = 0.0
            for (index, tap) in taps.enumerated() {
                let angle = 2 * .pi * f * (Double(index + filter.jMin) - delta)
                r += tap * cos(angle)
                i += tap * sin(angle)
            }
            let magnitude = (r * r + i * i).squareRoot()
            worst = min(worst, magnitude)
            loudest = max(loudest, magnitude)
        }
        return worst < 1 ? worst : loudest
    }

    /// The highest fraction of Nyquist at which every phase is still within `limit` dB of unity.
    func flatTo(_ filter: PolyphaseFilter, limit: Double) -> Double {
        var highest = 0.0
        for step in 1 ... 200 {
            let ratio = Double(step) / 200
            let deviation = abs(20 * log10(max(gain(filter, ratio / 2), 1e-12)))
            if deviation <= limit { highest = ratio } else { break }
        }
        return highest
    }

    /// Worst gain applied to an **image** — the copies zero-stuffing puts at `k ± f` for `k >= 1`.
    /// Leakage here is an over-read: energy that is not in the signal arriving in the reconstruction.
    func worstImageLeakage(_ filter: PolyphaseFilter) -> Double {
        var worst = 0.0
        for step in 1 ... 100 {
            let f = Double(step) / 200   // input frequency, cycles/sample, up to Nyquist
            for k in 1 ..< filter.factor {
                for image in [Double(k) - f, Double(k) + f] {
                    var loudest = 0.0
                    for (phase, taps) in filter.phases.enumerated() {
                        let delta = Double(phase) / Double(filter.factor)
                        var r = 0.0
                        var i = 0.0
                        for (index, tap) in taps.enumerated() {
                            let angle = 2 * .pi * image * (Double(index + filter.jMin) - delta)
                            r += tap * cos(angle)
                            i += tap * sin(angle)
                        }
                        loudest = max(loudest, (r * r + i * i).squareRoot())
                    }
                    worst = max(worst, loudest)
                }
            }
        }
        return worst
    }

    print("taps | beta | flat±0.05dB to | flat±0.1dB to | gain@0.8N | gain@0.9N | gain@0.95N | worst image (dB)")
    for taps in [12, 24, 32, 48, 64, 96] {
        for beta in [6.0, 8.6, 12.0, 16.0] {
            let filter = PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: taps, beta: beta))
            let at = { (r: Double) in String(format: "%+.4f", 20 * log10(max(gain(filter, r / 2), 1e-12))) }
            let leakage = 20 * log10(max(worstImageLeakage(filter), 1e-12))
            print("\(taps) | \(beta) | \(String(format: "%.2f", flatTo(filter, limit: 0.05)))"
                + " | \(String(format: "%.2f", flatTo(filter, limit: 0.1)))"
                + " | \(at(0.80)) | \(at(0.90)) | \(at(0.95)) | \(String(format: "%+.2f", leakage))")
        }
    }
}

// MARK: - Phase E — chunk independence

heading("PHASE E — chunk independence (max |streamed - whole buffer|)")
let chunkSizes = [1, 3, 127, 512, 2_048, 4_096, 65_536]
for name in ["03-tone-crest-between-samples", "09-energy-first-frame", "10-energy-last-frame", "17-complex-programme"] {
    guard let fixture = fixtures.first(where: { $0.name == name }) else { continue }
    let filter = PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: 24, beta: 12))
    let whole = Reconstruct.peakDouble(fixture.channels[0], filter: filter, edge: .zero)
    var worst = 0.0
    var detail = ""
    for size in chunkSizes {
        var streaming = StreamingReconstructor(filter: filter, edge: .zero)
        var index = 0
        while index < fixture.channels[0].count {
            let end = min(index + size, fixture.channels[0].count)
            streaming.accumulate(Array(fixture.channels[0][index ..< end]))
            index = end
        }
        let streamed = streaming.finish()
        worst = max(worst, abs(streamed - whole))
        detail += " \(size):\(streamed == whole ? "exact" : String(format: "%.3g", abs(streamed - whole)))"
    }
    print("\(name) whole=\(String(format: "%.9f", whole)) worst=\(worst)  [\(detail) ]")
}

// MARK: - Phase F — Float vs Double

heading("PHASE F — Float vs Double in the convolution")
print("fixture | double | float | |Δ| linear | Δ dB | vDSP | |vDSP-double|")
for fixture in fixtures {
    let filter = PolyphaseFilter(method: .fir(factor: 4, tapsPerPhase: 24, beta: 12))
    let asDouble = fixture.channels.map { Reconstruct.peakDouble($0, filter: filter, edge: .zero) }.max() ?? 0
    let asFloat = fixture.channels.map { Reconstruct.peakFloat($0, filter: filter, edge: .zero) }.max() ?? 0
    let asVDSP = fixture.channels.map { Reconstruct.peakVDSP($0, filter: filter, edge: .zero) }.max() ?? 0
    let deltaDecibels = asFloat > 0 && asDouble > 0 ? decibels(asFloat) - decibels(asDouble) : 0
    print("\(fixture.name) | \(String(format: "%.9f", asDouble)) | \(String(format: "%.9f", asFloat))"
        + " | \(String(format: "%.3g", abs(asFloat - asDouble))) | \(String(format: "%+.6f", deltaDecibels))"
        + " | \(String(format: "%.9f", asVDSP)) | \(String(format: "%.3g", abs(asVDSP - asDouble)))")
}

// MARK: - Phase G — oracle agreement summary

let chosen = Method.fir(factor: 8, tapsPerPhase: 48, beta: 6, cutoff: 1, normalise: true, edge: .zero, precision: .float)
heading("PHASE G — agreement with FFmpeg, per fixture (candidate: \(chosen.identifier))")
if Oracle.isAvailable {
    var worstLinear = 0.0
    var worstDecibels = 0.0
    print("fixture | analytic | ours | oracle | Δ vs oracle (dB) | Δ vs analytic (dB) | oracle sample peak")
    for fixture in fixtures {
        guard let reading = Oracle.measure(path: "\(outputDirectory)/\(fixture.name).wav") else { continue }
        let filter = PolyphaseFilter(method: chosen)
        let ours = fixture.channels.map { Reconstruct.peakDouble($0, filter: filter, edge: .zero) }.max() ?? 0
        let deltaLinear = abs(ours - reading.truePeak)
        let deltaDecibels = ours > 0 && reading.truePeak > 0 ? abs(decibels(ours) - decibels(reading.truePeak)) : 0
        // 192 kHz is excluded from the worst-case: the oracle does not oversample there at all (its
        // true peak equals its own sample peak), so the disagreement measures the oracle, not us.
        if fixture.sampleRate <= 96_000 {
            worstLinear = max(worstLinear, deltaLinear)
            worstDecibels = max(worstDecibels, deltaDecibels)
        }
        let analyticError = fixture.analyticTruePeak.flatMap { truth -> String? in
            truth > 0 ? String(format: "%+.4f", decibels(ours) - decibels(truth)) : nil
        }
        print("\(fixture.name) | \(fixture.analyticTruePeak.map { String(format: "%.6f", $0) } ?? "—")"
            + " | \(String(format: "%.6f", ours)) | \(String(format: "%.3f", reading.truePeak))"
            + " | \(String(format: "%.4f", deltaDecibels)) | \(analyticError ?? "—")"
            + " | \(String(format: "%.3f", reading.samplePeak))")
    }
    print("worst Δ linear (<= 96 kHz) = \(worstLinear)   worst Δ dB = \(worstDecibels)")
    print("oracle quantisation floor: ±0.0005 linear (metadata is printed to 3 decimals)")
} else {
    print("ffmpeg not available — oracle phase skipped loudly rather than silently passed")
}

// MARK: - Phase H — cost

if runCost || runCostQuick {
    runCostPhase(quick: runCostQuick)
}

heading("DONE")
