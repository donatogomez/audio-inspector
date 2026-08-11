import Accelerate
import Foundation

// MARK: - The filter, designed rather than quoted

/// A polyphase windowed-sinc interpolation filter.
///
/// ## Why the coefficients are generated here rather than copied from BS.1770
///
/// ITU-R BS.1770 Annex 2 tabulates a 4-phase, 12-tap-per-phase FIR for its own true-peak meter. **Those
/// coefficients are not reproduced here, because this spike had no access to the standard's text**, and
/// writing down remembered numbers would be exactly the fabricated evidence this project forbids. What
/// is done instead is stated openly: a filter of the *same family and shape* is **designed** from named
/// parameters, every one of which is recorded with the result, and it is then validated against an
/// independent implementation of the standard (FFmpeg's `ebur128`, itself an R128 meter) and against
/// signals whose true peak is known analytically.
///
/// ## The one design choice the invariant depends on
///
/// `sinc(u)` is **zero at every non-zero integer** and one at zero. That is a definition, not an
/// approximation, so it is evaluated as such (`sinc(_:)` below) rather than left to
/// `sin(πu)/(πu)`, which returns ~1e-16 instead of 0 at integer arguments. The consequence is exact and
/// is the whole reason `truePeak >= samplePeak` holds *by construction*: at phase 0 every tap argument
/// is an integer, so every tap but the centre one is exactly zero and the centre one is exactly one —
/// **phase 0 reproduces the input samples bit for bit**, which puts the stored samples inside the set
/// the maximum is taken over. No clamp, no `max(samplePeak, …)` afterwards.
///
/// This holds only while `cutoff == 1.0`. A filter that low-passes below the original Nyquist
/// (`cutoff < 1`) has a phase 0 that is *not* the identity, and the invariant stops being structural —
/// measured and reported rather than assumed (see the cutoff experiment).
struct PolyphaseFilter {
    let factor: Int
    let tapsPerPhase: Int
    /// `phases[p][t]` — phase `p`'s taps, `t` indexing `j = t + jMin`.
    let phases: [[Double]]
    /// The lowest tap offset `j`; `jMax = jMin + tapsPerPhase - 1`.
    let jMin: Int

    init(method: Method) {
        precondition(method.tapsPerPhase % 2 == 0, "an even tap count keeps the support symmetric")
        factor = method.oversamplingFactor
        tapsPerPhase = method.tapsPerPhase
        jMin = 1 - method.tapsPerPhase / 2
        let halfWidth = Double(method.tapsPerPhase) / 2
        let cutoff = method.cutoff

        phases = (0 ..< method.oversamplingFactor).map { phase in
            let delta = Double(phase) / Double(method.oversamplingFactor)
            var taps = (0 ..< method.tapsPerPhase).map { index -> Double in
                let j = index + 1 - method.tapsPerPhase / 2
                let u = delta - Double(j)
                return cutoff * Self.sinc(cutoff * u) * Self.kaiser(u / halfWidth, beta: method.kaiserBeta)
            }
            if method.normalisePhases {
                let sum = taps.reduce(0, +)
                if sum != 0 { taps = taps.map { $0 / sum } }
            }
            return taps
        }
    }

    /// `sin(πu)/(πu)`, with its **exact** values at integer arguments used as such.
    static func sinc(_ u: Double) -> Double {
        if u == u.rounded() { return u == 0 ? 1 : 0 }
        return sin(.pi * u) / (.pi * u)
    }

    /// Kaiser window on `r ∈ [-1, 1]`, zero outside.
    static func kaiser(_ r: Double, beta: Double) -> Double {
        guard abs(r) <= 1 else { return 0 }
        return besselI0(beta * (1 - r * r).squareRoot()) / besselI0(beta)
    }

    /// Zeroth-order modified Bessel function, by its series — converges quickly for the β used here.
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let half = x / 2
        for k in 1 ... 60 {
            term *= (half / Double(k)) * (half / Double(k))
            sum += term
            if term < sum * 1e-18 { break }
        }
        return sum
    }
}

// MARK: - Padding the ends

enum Padding {
    /// Extends `samples` by `count` on each side under `edge`, returning the extended buffer and how
    /// many samples were prepended.
    static func extend(_ samples: [Double], by count: Int, edge: EdgeHandling) -> (buffer: [Double], offset: Int) {
        guard !samples.isEmpty, count > 0 else { return (samples, 0) }
        var head = [Double](repeating: 0, count: count)
        var tail = [Double](repeating: 0, count: count)
        switch edge {
        case .zero, .interiorOnly, .periodic:
            break
        case .constant:
            head = [Double](repeating: samples[0], count: count)
            tail = [Double](repeating: samples[samples.count - 1], count: count)
        case .mirror:
            for index in 0 ..< count {
                // Mirrored about the first/last sample, which is not repeated.
                head[count - 1 - index] = samples[min(index + 1, samples.count - 1)]
                tail[index] = samples[max(samples.count - 2 - index, 0)]
            }
        }
        return (head + samples + tail, count)
    }
}

// MARK: - Whole-buffer measurement

enum Reconstruct {
    /// The maximum of `|y|` over every reconstructed point, in `Double`.
    ///
    /// Evaluates every output phase of every input position, so the candidate set contains the original
    /// samples (phase 0) as well as everything between them.
    static func peakDouble(_ samples: [Double], filter: PolyphaseFilter, edge: EdgeHandling) -> Double {
        guard !samples.isEmpty else { return 0 }
        let pad = filter.tapsPerPhase + 1
        let (buffer, offset) = Padding.extend(samples, by: pad, edge: edge)
        let jMin = filter.jMin
        let taps = filter.tapsPerPhase

        // For `interiorOnly`, restrict to positions whose whole tap window lies inside the real signal.
        let first = edge == .interiorOnly ? -jMin : 0
        let last = edge == .interiorOnly ? samples.count - (jMin + taps - 1) : samples.count
        guard first < last else { return 0 }

        var peak = 0.0
        for n in first ..< last {
            let base = n + offset + jMin
            for phase in filter.phases {
                var accumulator = 0.0
                for t in 0 ..< taps { accumulator += phase[t] * buffer[base + t] }
                peak = max(peak, abs(accumulator))
            }
        }
        return peak
    }

    /// The same reconstruction with the convolution carried out in `Float`.
    static func peakFloat(_ samples: [Double], filter: PolyphaseFilter, edge: EdgeHandling) -> Double {
        guard !samples.isEmpty else { return 0 }
        let pad = filter.tapsPerPhase + 1
        let (extended, offset) = Padding.extend(samples, by: pad, edge: edge)
        let buffer = extended.map { Float($0) }
        let phases = filter.phases.map { $0.map { Float($0) } }
        let jMin = filter.jMin
        let taps = filter.tapsPerPhase
        let first = edge == .interiorOnly ? -jMin : 0
        let last = edge == .interiorOnly ? samples.count - (jMin + taps - 1) : samples.count
        guard first < last else { return 0 }

        var peak: Float = 0
        for n in first ..< last {
            let base = n + offset + jMin
            for phase in phases {
                var accumulator: Float = 0
                for t in 0 ..< taps { accumulator += phase[t] * buffer[base + t] }
                peak = max(peak, abs(accumulator))
            }
        }
        return Double(peak)
    }

    /// The same reconstruction, one `vDSP_conv` + `vDSP_maxmgv` per phase — the shape production would
    /// use. Never materialises the zero-stuffed oversampled signal.
    static func peakVDSP(_ samples: [Double], filter: PolyphaseFilter, edge: EdgeHandling) -> Double {
        guard !samples.isEmpty else { return 0 }
        let pad = filter.tapsPerPhase + 1
        let (extended, offset) = Padding.extend(samples, by: pad, edge: edge)
        let buffer = extended.map { Float($0) }
        let taps = filter.tapsPerPhase
        let jMin = filter.jMin
        let first = edge == .interiorOnly ? -jMin : 0
        let last = edge == .interiorOnly ? samples.count - (jMin + taps - 1) : samples.count
        guard first < last else { return 0 }
        let outputCount = last - first

        var peak: Float = 0
        var scratch = [Float](repeating: 0, count: outputCount)
        for phase in filter.phases {
            let coefficients = phase.map { Float($0) }
            buffer.withUnsafeBufferPointer { input in
                coefficients.withUnsafeBufferPointer { kernel in
                    scratch.withUnsafeMutableBufferPointer { output in
                        // `vDSP_conv` with a positive filter stride computes the correlation
                        // C[n] = Σ_p A[n+p]·F[p] — exactly `Σ_j h[j]·x[n+j]` with F in increasing j.
                        vDSP_conv(
                            input.baseAddress! + (first + offset + jMin), 1,
                            kernel.baseAddress!, 1,
                            output.baseAddress!, 1,
                            vDSP_Length(outputCount), vDSP_Length(taps)
                        )
                    }
                }
            }
            var phasePeak: Float = 0
            vDSP_maxmgv(scratch, 1, &phasePeak, vDSP_Length(outputCount))
            peak = max(peak, phasePeak)
        }
        return Double(peak)
    }
}

// MARK: - Streaming, to test chunk independence

/// Reconstructs in chunks, carrying the filter's own history across the boundary. The result must equal
/// the whole-buffer one, or the dependence has to be reported rather than hidden.
///
/// **The coordinate system that makes this simple.** With `pad = -jMin` samples prepended, output
/// position `n` reads exactly `extended[n ..< n + tapsPerPhase]`. So the streaming form is: build the
/// left padding once, append chunks, and emit every position whose whole tap window has arrived. The
/// left padding needs the signal's first `pad` samples for `mirror`/`constant`, so the first `pad`
/// samples are held before anything is emitted — which is what production would have to do too.
///
/// No compaction: this is a spike, the signals are short, and dropping the consumed prefix is an
/// optimisation that could only change performance, never the answer.
struct StreamingReconstructor {
    private let filter: PolyphaseFilter
    private let edge: EdgeHandling
    private var extended: [Double] = []
    private var raw: [Double] = []
    private var emitted = 0
    private var leftPadded = false
    private(set) var peak = 0.0

    init(filter: PolyphaseFilter, edge: EdgeHandling) {
        self.filter = filter
        self.edge = edge
    }

    private var pad: Int { -filter.jMin }

    mutating func accumulate(_ chunk: [Double]) {
        raw.append(contentsOf: chunk)
        if !leftPadded {
            guard raw.count >= pad else { return }
            let (padded, _) = Padding.extend(raw, by: pad, edge: edge)
            extended = Array(padded.prefix(pad)) + raw
            leftPadded = true
        } else {
            extended.append(contentsOf: chunk)
        }
        drain(limit: raw.count)
    }

    mutating func finish() -> Double {
        if !leftPadded {
            let (padded, _) = Padding.extend(raw, by: pad, edge: edge)
            extended = Array(padded.prefix(pad)) + raw
            leftPadded = true
        }
        let right = filter.jMin + filter.tapsPerPhase - 1
        let (padded, _) = Padding.extend(raw, by: right, edge: edge)
        extended.append(contentsOf: padded.suffix(right))
        drain(limit: raw.count)
        return peak
    }

    /// Emits every position `< limit` whose tap window has fully arrived.
    private mutating func drain(limit: Int) {
        let taps = filter.tapsPerPhase
        while emitted < limit, emitted + taps <= extended.count {
            for phase in filter.phases {
                var accumulator = 0.0
                for t in 0 ..< taps { accumulator += phase[t] * extended[emitted + t] }
                peak = max(peak, abs(accumulator))
            }
            emitted += 1
        }
    }
}

// MARK: - Frequency-domain candidate

enum FrequencyDomain {
    /// Band-limited interpolation by zero-padding the spectrum. Exact for a signal periodic in the
    /// buffer; **inherently whole-buffer and circular**, which is the finding, not a bug.
    ///
    /// Requires a power-of-two length. Returns `nil` when the length is not one.
    static func peak(_ samples: [Double], factor: Int) -> Double? {
        let n = samples.count
        guard n > 0, (n & (n - 1)) == 0 else { return nil }
        let padded = n * factor
        guard let forward = try? vDSP.DiscreteFourierTransform(
            previous: nil, count: n, direction: .forward, transformType: .complexComplex, ofType: Double.self
        ), let inverse = try? vDSP.DiscreteFourierTransform(
            previous: nil, count: padded, direction: .inverse, transformType: .complexComplex, ofType: Double.self
        ) else { return nil }

        let (spectrumReal, spectrumImaginary) = forward.transform(
            real: samples, imaginary: [Double](repeating: 0, count: n)
        )

        var real = [Double](repeating: 0, count: padded)
        var imaginary = [Double](repeating: 0, count: padded)
        let half = n / 2
        for k in 0 ..< half {
            real[k] = spectrumReal[k]
            imaginary[k] = spectrumImaginary[k]
        }
        for k in (half + 1) ..< n {
            real[padded - n + k] = spectrumReal[k]
            imaginary[padded - n + k] = spectrumImaginary[k]
        }
        // Nyquist carries no partner: split it evenly so the reconstruction stays real.
        real[half] = spectrumReal[half] / 2
        imaginary[half] = spectrumImaginary[half] / 2
        real[padded - half] = spectrumReal[half] / 2
        imaginary[padded - half] = spectrumImaginary[half] / 2

        let (outputReal, _) = inverse.transform(real: real, imaginary: imaginary)
        let scale = 1.0 / Double(n)
        return outputReal.reduce(0) { max($0, abs($1 * scale)) }
    }
}
