import Accelerate
import AudioInspectorDomain
import AudioInspectorMedia
import Foundation

// The group 1 methodology, written once, in test code, so group 2's evidence has something to measure
// with **before** the production accumulator exists.
//
// This is deliberately NOT production. Nothing in `Sources/` references it, it uses `Accelerate`
// directly rather than through a port, and it keeps whatever it likes in memory. Its job is to turn a
// real file — through the real decoder, in real chunks — into the number group 1 decided, so that
// group 2 can ask whether containers, sample rates, codecs and chunk boundaries change that number.
// When `SignificantBandwidthAccumulator` exists, this becomes the thing it is checked against.
//
// The method is `docs/adr/0023-significant-bandwidth-as-a-measured-fact.md` and
// `docs/spikes/2026-08-19-significant-bandwidth-methodology.md`. Every constant below cites which.

// MARK: - The method's constants

enum ProgrammeBandwidthMethod {
    /// 2048 frames at 48 kHz. The window is fixed in **time**, not in samples: a sample-locked window
    /// makes the persistence criterion rate-dependent, classifying identical temporal evidence as
    /// significant at 44.1 kHz and insignificant at 192 kHz (spike §12.5).
    static let targetWindowSeconds = 2_048.0 / 48_000.0
    /// A bin is significant when it is within this of **its own window's** spectral peak (spike §4).
    static let thresholdDB = -50.0
    /// A window contributes only if it sits within this of the **file's** spectral peak. A declared
    /// product parameter, not a discovery: content further down is not measured, and a noise floor
    /// further down does not count as content (ADR-0023 §5).
    static let budgetDB = -60.0
    /// A bin is reported when it is significant in at least this fraction of eligible windows,
    /// counted as the k-th largest with k = ceil(fraction × N) — a nearest-rank-from-the-top p90, not
    /// an interpolated one and not p95 (spike §5.1).
    static let persistenceFraction = 0.10
    /// 75 % overlap. 25 % disagrees with the rest on the critical event duration; 50, 75 and 87.5 %
    /// agree, and more overlap rejects transients better (spike §12.7).
    static let overlapDivisor = 4

    /// Lengths `vDSP` accepts: `f · 2^m` for f in {1, 3, 5, 15}, through `vDSP_DFT_zrop` where the
    /// length is not a power of two. Probed at first use rather than assumed.
    static let supportedTransformLengths: [Int] = {
        var lengths: [Int] = []
        for factor in [1, 3, 5, 15] {
            for shift in 3 ... 20 {
                let length = factor << shift
                guard length >= 256, length <= 65_536 else { continue }
                if RealTransform(length) != nil { lengths.append(length) }
            }
        }
        return lengths.sorted()
    }()

    /// The transform length whose duration is closest to `targetWindowSeconds` at this rate.
    ///
    /// Non-power-of-two lengths are what make this possible: 1920 at 44.1 kHz and 3840 at 88.2 kHz
    /// hold the window to within 2.0 % of the target, where powers of two alone would force 8.8 %.
    static func fftSize(for sampleRate: Double) -> Int {
        let target = targetWindowSeconds * sampleRate
        return supportedTransformLengths.min {
            abs(Double($0) - target) < abs(Double($1) - target)
        } ?? 2_048
    }

    static func hop(for sampleRate: Double) -> Int {
        max(1, fftSize(for: sampleRate) / overlapDivisor)
    }
}

// MARK: - The reading

/// What the method produces for one channel.
struct ProgrammeBandwidthReading: Equatable {
    /// The **centre** of the highest qualifying bin. A bin edge would add half a bin of overstatement
    /// to a figure that already overstates, and an interval was derived and then falsified (spike
    /// §12.3), so the contract is a centre frequency plus the resolution below.
    let frequency: Double
    /// `sampleRate / fftSize`. The quantisation of the value above — **not** the uncertainty.
    let resolution: Double
    /// The bin index, kept because a test that asserts on frequencies alone cannot tell a one-bin
    /// difference from a rounding difference.
    let bin: Int
    let windowCount: Int
    let eligibleWindowCount: Int
}

// MARK: - The reference

/// Consumes `PCMChunk`s in file order and produces one reading per channel.
///
/// Chunk-independent by construction: samples are buffered per channel and a window is emitted every
/// `hop` frames from frame zero, so where a chunk happens to end changes nothing. Group 2 asserts that
/// rather than trusting it.
///
/// **Channel semantics are deliberately absent.** Whether the shipped measurement is per channel or
/// combined is task 3.4 and is not decided; this reports each channel separately so no test here
/// asserts a layout the pipeline does not read.
/// Every constant the method fixes, overridable **only** so the negative controls can show each one
/// is load-bearing. Nothing in the evidence suites passes anything but the defaults.
struct ProgrammeBandwidthOverrides {
    var thresholdDB = ProgrammeBandwidthMethod.thresholdDB
    var budgetDB: Double? = ProgrammeBandwidthMethod.budgetDB
    var persistenceFraction = ProgrammeBandwidthMethod.persistenceFraction
    /// A fixed transform length at every rate — the sample-locked window group 1 rejected.
    var fixedFFTSize: Int?
    /// A magnitude floor, as the spike's first harness had. It is what made a silent window look like
    /// a window with a reference, so reintroducing it must break silence and nothing else.
    var magnitudeClamp: Float?
}

final class ProgrammeBandwidthReference {
    private let overrides: ProgrammeBandwidthOverrides
    private let sampleRate: Double
    private let fftSize: Int
    private let hopSize: Int
    private let bins: Int
    private let window: [Float]
    private let transform: RealTransform
    private let significanceRatio: Float
    private let budgetRatio: Float

    /// Per channel: the samples not yet consumed by a window.
    private var pending: [[Float]]
    /// Per channel, per emitted window: that window's spectral peak, and which bins were significant
    /// within it. Significance is decided inside a window, so it needs no knowledge of the file.
    private var windowPeaks: [[Float]]
    private var significantBins: [[[UInt64]]]

    init(sampleRate: Double, channelCount: Int, overrides: ProgrammeBandwidthOverrides = .init()) {
        self.overrides = overrides
        self.sampleRate = sampleRate
        let size = overrides.fixedFFTSize ?? ProgrammeBandwidthMethod.fftSize(for: sampleRate)
        fftSize = size
        hopSize = max(1, size / ProgrammeBandwidthMethod.overlapDivisor)
        bins = size / 2 + 1
        // Periodic Hann, built here rather than taken from `vDSP_hann_window`, so the definition is
        // never in question. `vDSP_HANN_DENORM` is the same window; this does not depend on that.
        window = (0 ..< size).map {
            Float(0.5 * (1 - cos(2 * Double.pi * Double($0) / Double(size))))
        }
        transform = RealTransform(size)!
        significanceRatio = Float(pow(10.0, overrides.thresholdDB / 20))
        budgetRatio = overrides.budgetDB.map { Float(pow(10.0, $0 / 20)) } ?? 0
        pending = Array(repeating: [], count: channelCount)
        windowPeaks = Array(repeating: [], count: channelCount)
        significantBins = Array(repeating: [], count: channelCount)
    }

    func receive(_ chunk: PCMChunk) {
        for channel in 0 ..< min(chunk.channelCount, pending.count) {
            pending[channel].append(contentsOf: chunk.channels[channel])
            drain(channel)
        }
    }

    private func drain(_ channel: Int) {
        var magnitudes = [Float](repeating: 0, count: bins)
        var windowed = [Float](repeating: 0, count: fftSize)
        while pending[channel].count >= fftSize {
            pending[channel].withUnsafeBufferPointer { source in
                vDSP_vmul(source.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
            }
            // No clamp. A window of zeros must transform to magnitude exactly zero, because that is
            // what makes "this window carries energy" decidable without an epsilon — and a magnitude
            // floor is exactly what made silence look like a window with a reference (spike §13c.1).
            transform.magnitudes(windowed, into: &magnitudes)
            if let clamp = overrides.magnitudeClamp {
                for bin in 0 ..< bins where magnitudes[bin] < clamp { magnitudes[bin] = clamp }
            }
            var peak: Float = 0
            for value in magnitudes where value > peak { peak = value }
            windowPeaks[channel].append(peak)
            var mask = [UInt64](repeating: 0, count: (bins + 63) / 64)
            if peak > 0 {
                let limit = peak * significanceRatio
                for bin in 0 ..< bins where magnitudes[bin] >= limit {
                    mask[bin >> 6] |= 1 << UInt64(bin & 63)
                }
            }
            significantBins[channel].append(mask)
            pending[channel].removeFirst(hopSize)
        }
    }

    /// One reading per channel; `nil` where the channel carries no eligible window at all.
    func finish() -> [ProgrammeBandwidthReading?] {
        (0 ..< windowPeaks.count).map { reading(for: $0) }
    }

    private func reading(for channel: Int) -> ProgrammeBandwidthReading? {
        let peaks = windowPeaks[channel]
        // Eligibility, part one: a window that carries no energy is not an observation. A file of
        // silence yields no eligible window and therefore no reading, with nothing added.
        var filePeak: Float = 0
        for peak in peaks where peak > filePeak { filePeak = peak }
        guard filePeak > 0 else { return nil }
        // Eligibility, part two: the declared 60 dB programme budget.
        let floor = filePeak * budgetRatio
        let eligible = (0 ..< peaks.count).filter { peaks[$0] > 0 && peaks[$0] >= floor }
        guard !eligible.isEmpty else { return nil }

        let needed = max(1, Int(ceil(overrides.persistenceFraction * Double(eligible.count))))
        var bin = bins - 1
        while bin >= 0 {
            var count = 0
            let word = bin >> 6, mask = UInt64(1) << UInt64(bin & 63)
            for index in eligible where significantBins[channel][index][word] & mask != 0 {
                count += 1
                if count >= needed { break }
            }
            if count >= needed {
                return ProgrammeBandwidthReading(
                    frequency: Double(bin) * sampleRate / Double(fftSize),
                    resolution: sampleRate / Double(fftSize),
                    bin: bin,
                    windowCount: peaks.count,
                    eligibleWindowCount: eligible.count
                )
            }
            bin -= 1
        }
        return nil
    }
}

// MARK: - The transform

/// A forward real transform for any length `vDSP` accepts. Powers of two use `vDSP_fft_zrip`;
/// everything else uses `vDSP_DFT_zrop`, which is what makes a time-locked window reachable at 44.1
/// and 88.2 kHz.
final class RealTransform {
    let n: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup?
    private let dftSetup: vDSP_DFT_Setup?
    private let scale: Float

    init?(_ n: Int) {
        guard n >= 8, n.isMultiple(of: 2) else { return nil }
        self.n = n
        // `1 / Σw` so a full-scale sine on a bin centre reads its own amplitude.
        let windowSum = (0 ..< n).reduce(0.0) { $0 + 0.5 * (1 - cos(2 * Double.pi * Double($1) / Double(n))) }
        scale = Float(1 / windowSum)
        let power = Int(log2(Double(n)).rounded())
        if 1 << power == n, let setup = vDSP_create_fftsetup(vDSP_Length(power), FFTRadix(kFFTRadix2)) {
            log2n = vDSP_Length(power); fftSetup = setup; dftSetup = nil
        } else if let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD) {
            log2n = 0; fftSetup = nil; dftSetup = setup
        } else {
            return nil
        }
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
        if let dftSetup { vDSP_DFT_DestroySetup(dftSetup) }
    }

    /// Magnitudes for bins `0 ... n/2`, scaled so a sine reads its amplitude. Never clamped.
    func magnitudes(_ windowed: [Float], into output: inout [Float]) {
        let half = n / 2
        var real = [Float](repeating: 0, count: half), imaginary = real
        windowed.withUnsafeBufferPointer { source in
            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                    if let fftSetup {
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    } else if let dftSetup {
                        var outReal = [Float](repeating: 0, count: half), outImaginary = outReal
                        outReal.withUnsafeMutableBufferPointer { or in
                            outImaginary.withUnsafeMutableBufferPointer { oi in
                                vDSP_DFT_Execute(dftSetup, realBuffer.baseAddress!, imaginaryBuffer.baseAddress!,
                                                 or.baseAddress!, oi.baseAddress!)
                            }
                        }
                        for index in 0 ..< half { realBuffer[index] = outReal[index]; imaginaryBuffer[index] = outImaginary[index] }
                    }
                    // vDSP packs DC in real[0] and Nyquist in imag[0]; split them apart before the
                    // interior magnitudes are taken.
                    output[0] = abs(realBuffer[0]) * 0.5 * scale
                    output[half] = abs(imaginaryBuffer[0]) * 0.5 * scale
                    realBuffer[0] = 0; imaginaryBuffer[0] = 0
                    var interior = [Float](repeating: 0, count: half)
                    vDSP_zvabs(&split, 1, &interior, 1, vDSP_Length(half))
                    for bin in 1 ..< half { output[bin] = interior[bin] * 0.5 * scale }
                }
            }
        }
    }
}

// MARK: - Driving it from a real file

/// Decodes `url` with the production decoder and measures every channel.
///
/// This is the point of group 2: the subject stops being an array in memory and becomes a file, read
/// by the same `AVFoundationAudioDecoder` the app uses, in chunks of the caller's choosing.
func measureProgrammeBandwidth(
    of url: URL,
    chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames,
    overrides: ProgrammeBandwidthOverrides = .init()
) async throws -> (readings: [ProgrammeBandwidthReading?], description: PCMStreamDescription?) {
    let decoder = AVFoundationAudioDecoder(resolveURL: { _ in url })
    let file = AudioFileReference(
        displayName: url.lastPathComponent,
        fileExtension: url.pathExtension,
        sizeBytes: nil,
        modifiedAt: nil,
        source: .userSelectedLocalFile(displayName: url.lastPathComponent, locationDisclosure: .omitted)
    )
    var reference: ProgrammeBandwidthReference?
    let description = try await decoder.decode(file, chunkFrames: chunkFrames) { stream, chunk in
        if reference == nil {
            reference = ProgrammeBandwidthReference(
                sampleRate: stream.sampleRate, channelCount: stream.channelCount, overrides: overrides
            )
        }
        reference?.receive(chunk)
        return .continue
    }
    return (reference?.finish() ?? [], description)
}
