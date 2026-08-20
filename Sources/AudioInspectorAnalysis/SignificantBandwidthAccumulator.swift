import Accelerate
import AudioInspectorDomain
import Foundation

/// Measures programme bandwidth over a file's decoded PCM, one chunk at a time.
///
/// The methodology is `docs/adr/0023-significant-bandwidth-as-a-measured-fact.md`, decided by
/// measurement before this type existed. Four layers, each answering a different question, and none
/// substituting for another:
///
/// 1. **Eligibility** — is this window an observation? A window carrying no energy is not, and needs no
///    constant to say so: it transforms to magnitude exactly zero.
/// 2. **Programme budget** — is this window part of the programme? Only if its own spectral peak sits
///    within 60 dB of the file's. A **declared product parameter**, whose cost is stated: content
///    further down is not measured, and a noise floor further down does not count as content.
/// 3. **Significance** — does this bin stand out *inside* its window? Only if it is within 50 dB of
///    that window's own peak.
/// 4. **Persistence** — does that repeat? Only if it holds in at least 10 % of eligible windows.
///
/// ## Not `Sendable`, deliberately
///
/// It owns a `vDSP.DiscreteFourierTransform`, which is not `Sendable`. `SpectrogramAccumulator`'s
/// precedent exactly: built inside one operation, never stored on a `Sendable` type, never shared. No
/// `@unchecked Sendable`.
public struct SignificantBandwidthAccumulator {

    // MARK: The method's constants

    /// 2048 frames at 48 kHz. The window is fixed in **time**: a sample-locked one makes the
    /// persistence criterion rate-dependent, classifying ten bursts totalling 5 % of a file as
    /// significant at 44.1 kHz and insignificant at 192 kHz.
    public static let targetWindowSeconds = 2_048.0 / 48_000.0
    /// A bin is significant when within this of **its own window's** peak.
    static let significanceRatio = Float(0.003_162_277_66) // 10^(-50/20)
    /// A window contributes only if within this of the **file's** peak.
    static let budgetRatio = Float(0.001) // 10^(-60/20)
    /// The same budget in decibels, for arithmetic that must not underflow.
    static let budgetDecibels = -60.0
    /// Reported when significant in at least this fraction of eligible windows, counted as the k-th
    /// largest with k = ceil(fraction × N).
    static let persistenceFraction = 0.10
    /// 75 % overlap: 25 % disagrees with the rest on the critical event duration; 50, 75 and 87.5 %
    /// agree, and more overlap rejects transients better.
    static let overlapDivisor = 4

    /// Transform lengths `vDSP` accepts — `f · 2^m` for f in {1, 3, 5, 15}. The non-powers of two are
    /// what make a time-locked window reachable: 1920 at 44.1 kHz and 3840 at 88.2 kHz hold the window
    /// to within 2.0 % of the target, where powers of two alone would force 8.8 %.
    static let supportedWindowFrames: [Int] = {
        var lengths: [Int] = []
        for factor in [1, 3, 5, 15] {
            for shift in 3 ... 20 {
                let length = factor << shift
                if length >= 256, length <= 65_536 { lengths.append(length) }
            }
        }
        return lengths.sorted()
    }()

    /// The transform length whose duration is closest to the target at this rate.
    public static func windowFrames(for sampleRate: Double) -> Int {
        let target = targetWindowSeconds * sampleRate
        return supportedWindowFrames.min { abs(Double($0) - target) < abs(Double($1) - target) } ?? 2_048
    }

    // MARK: Bounded memory

    /// The width of one stratification bucket, in decibels.
    ///
    /// **Why the counters are stratified at all.** The budget compares each window against the *file's*
    /// spectral peak, which is not known until the last chunk, so a plain per-bin counter cannot decide
    /// eligibility as it goes. Keeping one bit per bin per window instead would be exact but O(duration):
    /// measured, 499 MB for three hours at 192 kHz, and task 3.3 forbids retaining a spectrogram at any
    /// resolution. Counters stratified by the window's own peak are `bins × buckets` regardless of
    /// duration — **3.8 MB per channel at 192 kHz, for a file of any length**.
    ///
    /// **What it costs, and which way.** The stratum straddling `filePeak − 60 dB` cannot be split: its
    /// windows sit on both sides of the boundary and their exact peaks are gone. It is resolved
    /// **inclusively**, for two reasons measured rather than assumed. A window sitting *exactly* on the
    /// budget is eligible under the exact rule, and excluding the stratum drops it — a fixture at
    /// exactly −60 dB read 16 102 Hz where the exact rule reads 20 016 Hz. And the budget exists to
    /// exclude noise floors far below the programme, so erring 0.25 dB deep is harmless where erring
    /// 0.25 dB shallow loses real content.
    ///
    /// So the declared budget is **60 dB, resolved to whole 0.25 dB strata, admitting at most 0.25 dB
    /// below it**. That is the methodological tolerance this structure costs, and it is stated rather
    /// than hidden.
    static let bucketDecibels = 0.25
    /// 60 dB of range, plus the bucket the boundary falls in, plus one for the peak's own bucket.
    static let bucketCount = Int(60.0 / bucketDecibels) + 2

    // MARK: Immutable configuration

    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    /// `1 / windowSum`, so a tone on a bin centre reads its own amplitude.
    private let magnitudeScale: Float
    private let sampleRate: Double
    private let channelCount: Int
    private let fftSize: Int
    private let hop: Int
    private let binCount: Int

    // MARK: Mutable state, all confined to one operation

    /// Samples not yet consumed by a window, one buffer per channel.
    private var pending: [[Float]]
    private var consumedFromPending = 0

    /// `[channel][bucketSlot * binCount + bin]` — how many windows in that stratum had that bin
    /// significant. A ring over bucket indices: the base advances as the running peak grows, and
    /// vacated strata are zeroed rather than re-indexed, so nothing drifts.
    private var counters: [[UInt32]]
    /// `[channel][bucketSlot]` — how many windows landed in that stratum at all.
    private var windowsPerBucket: [[UInt32]]
    /// The highest absolute bucket index currently representable.
    private var topBucket = Int.min
    /// The file's spectral peak so far, across **every** channel, kept exactly rather than bucketed.
    private var filePeak: Float = 0

    private var windowed: [Float]
    private var evens: [Float]
    private var odds: [Float]
    private var outputReal: [Float]
    private var outputImaginary: [Float]
    private var magnitudes: [Float]

    /// Fails on a description no analysis can be sized against, or a rate whose window length `vDSP`
    /// will not transform.
    public init?(sampleRate: Double, channelCount: Int) {
        guard sampleRate.isFinite, sampleRate > 0, channelCount >= 1 else { return nil }
        let fftSize = Self.windowFrames(for: sampleRate)
        guard let dft = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: fftSize,
            direction: .forward,
            transformType: .complexReal,
            ofType: Float.self
        ) else { return nil }

        self.dft = dft
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fftSize = fftSize
        hop = fftSize / Self.overlapDivisor
        binCount = fftSize / 2 + 1

        // Periodic Hann, built here rather than taken from `vDSP_hann_window`, so the definition this
        // measurement depends on is never in question.
        window = (0 ..< fftSize).map {
            Float(0.5 * (1 - cos(2 * Double.pi * Double($0) / Double(fftSize))))
        }
        magnitudeScale = Float(1 / window.reduce(Float(0), +))

        pending = Array(repeating: [], count: channelCount)
        counters = Array(
            repeating: [UInt32](repeating: 0, count: Self.bucketCount * binCount),
            count: channelCount
        )
        windowsPerBucket = Array(
            repeating: [UInt32](repeating: 0, count: Self.bucketCount),
            count: channelCount
        )
        windowed = [Float](repeating: 0, count: fftSize)
        evens = [Float](repeating: 0, count: fftSize / 2)
        odds = [Float](repeating: 0, count: fftSize / 2)
        outputReal = [Float](repeating: 0, count: fftSize / 2)
        outputImaginary = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: binCount)
    }

    public mutating func accumulate(_ chunk: PCMChunk) {
        guard chunk.channelCount == channelCount else { return }
        for channel in 0 ..< channelCount {
            pending[channel].append(contentsOf: chunk.channels[channel])
        }
        drainCompleteWindows()
    }

    /// The measurement, or `nil` when the file carried no window the method could use.
    public func finish() -> SignificantBandwidth? {
        guard let method = SignificantBandwidthMethod(
            windowFrames: fftSize, hopFrames: hop, sampleRate: sampleRate
        ) else { return nil }
        guard filePeak > 0, topBucket > Int.min else { return nil }

        // The budget's boundary, resolved to whole strata. The stratum the boundary falls inside is
        // **included**: a window sitting exactly on the budget is eligible under the exact rule, and
        // excluding its stratum would drop it.
        // **Subtracted in decibels, never multiplied first.** `filePeak * budgetRatio` underflows to
        // zero for a peak near the bottom of `Float`, and `log10(0)` is −infinity, which traps on the
        // conversion below. A very quiet file is not an error, and the arithmetic must not make it one.
        let thresholdDecibels = Self.decibels(filePeak) + Self.budgetDecibels
        let firstIncluded = Int(floor(thresholdDecibels / Self.bucketDecibels))
        let lowestRepresentable = topBucket - Self.bucketCount + 1
        let lowerBound = max(firstIncluded, lowestRepresentable)
        guard lowerBound <= topBucket else { return nil }

        var readings: [SignificantBandwidth.Channel?] = []
        let resolution = sampleRate / Double(fftSize)
        for channel in 0 ..< channelCount {
            var eligibleWindows = 0
            for bucket in lowerBound ... topBucket {
                eligibleWindows += Int(windowsPerBucket[channel][slot(for: bucket)])
            }
            guard eligibleWindows > 0 else { readings.append(nil); continue }
            let needed = max(1, Int(ceil(Self.persistenceFraction * Double(eligibleWindows))))

            var found: SignificantBandwidth.Channel?
            var bin = binCount - 1
            while bin >= 0 {
                var count = 0
                for bucket in lowerBound ... topBucket {
                    count += Int(counters[channel][slot(for: bucket) * binCount + bin])
                }
                if count >= needed {
                    found = SignificantBandwidth.Channel(
                        frequency: Double(bin) * resolution, resolution: resolution
                    )
                    break
                }
                bin -= 1
            }
            readings.append(found)
        }
        return SignificantBandwidth(channels: readings, method: method)
    }

    /// A window peak in decibels, kept finite.
    ///
    /// Two ways this can leave the real line, and neither is an error the file committed. A peak near
    /// the bottom of `Float` would underflow if the budget were applied by multiplication, so the
    /// budget is subtracted in decibels instead. And a signal extreme enough to overflow a magnitude to
    /// infinity — which `PCMChunk`'s finiteness rule permits, since it bounds samples and not their
    /// transform — would otherwise trap on the conversion to a stratum index. Both are clamped to the
    /// widest finite value rather than dropped: a window that carries energy is an observation.
    static func decibels(_ magnitude: Float) -> Double {
        guard magnitude.isFinite else { return 20 * log10(Double(Float.greatestFiniteMagnitude)) }
        return 20 * log10(Double(magnitude))
    }

    private func slot(for bucket: Int) -> Int {
        let raw = bucket % Self.bucketCount
        return raw < 0 ? raw + Self.bucketCount : raw
    }
}

// MARK: - The transform

private extension SignificantBandwidthAccumulator {

    /// Transforms every window `pending` now holds in full, advancing by `hop` after each.
    ///
    /// **The final incomplete window is discarded, never zero-padded**, on `SpectrogramAccumulator`'s
    /// own precedent: padding invents samples the file does not contain. A file shorter than one window
    /// therefore yields no windows and no value.
    mutating func drainCompleteWindows() {
        while pending[0].count - consumedFromPending >= fftSize {
            transformOneWindow()
            consumedFromPending += hop
        }
        compactPending()
    }

    mutating func compactPending() {
        guard consumedFromPending >= fftSize else { return }
        for channel in 0 ..< channelCount {
            pending[channel].removeFirst(consumedFromPending)
        }
        consumedFromPending = 0
    }

    /// One STFT frame across every channel. Channels are transformed **separately and never combined**:
    /// mixing before the threshold lets opposite-polarity content cancel, which would destroy evidence
    /// the file genuinely carries.
    mutating func transformOneWindow() {
        // The file's peak governs the budget for every channel, because the programme is the file: a
        // channel sitting 70 dB under the rest is below the programme, not a programme of its own.
        //
        // Each channel is transformed and filed before the next is touched, so `magnitudes` is read in
        // place and never copied. Filing a channel before a later one raises the running peak is safe:
        // the ring drops strata that fall more than 60 dB below it, which is exactly the rule.
        for channel in 0 ..< channelCount {
            transformChannel(channel)
            record(intoChannel: channel)
        }
    }

    /// Files one window's evidence into the stratum its own peak falls in.
    ///
    /// A window with no energy is not an observation and is filed nowhere — which is the whole of the
    /// eligibility rule, and needs no epsilon because `magnitudes` is never clamped.
    mutating func record(intoChannel channel: Int) {
        var peak: Float = 0
        for value in magnitudes where value > peak { peak = value }
        guard peak > 0 else { return }
        if peak > filePeak { filePeak = peak }
        let bucket = Int(floor(Self.decibels(peak) / Self.bucketDecibels))

        // A window more than 60 dB below the running peak can never become eligible, because the final
        // peak is at least the running one. Dropping it is exact, not an approximation.
        if topBucket == Int.min {
            topBucket = bucket
        } else if bucket > topBucket {
            // Advance the ring, zeroing what the new top displaces.
            let advance = min(bucket - topBucket, Self.bucketCount)
            for step in 1 ... advance {
                let vacated = slot(for: topBucket + step)
                let base = vacated * binCount
                for index in 0 ..< channelCount {
                    windowsPerBucket[index][vacated] = 0
                    for offset in 0 ..< binCount { counters[index][base + offset] = 0 }
                }
            }
            topBucket = bucket
        } else if bucket <= topBucket - Self.bucketCount {
            return
        }

        let target = slot(for: bucket)
        windowsPerBucket[channel][target] += 1
        let limit = peak * Self.significanceRatio
        let base = target * binCount
        for bin in 0 ..< binCount where magnitudes[bin] >= limit {
            counters[channel][base + bin] += 1
        }
    }

    mutating func transformChannel(_ channel: Int) {
        let start = consumedFromPending
        pending[channel].withUnsafeBufferPointer { source in
            let frame = UnsafeBufferPointer(rebasing: source[start ..< start + fftSize])
            vDSP.multiply(frame, window, result: &windowed)
        }
        splitWindowIntoHalves()
        dft.transform(
            inputReal: evens,
            inputImaginary: odds,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )

        // **Nothing is clamped anywhere in this path.** A magnitude floor turns a window of zeros into a
        // window at the floor — one with a spectral peak, and therefore a reference — which is exactly
        // what made silence look measurable in the spike's first harness and made an absolute silence
        // rule seem necessary. `SignificantBandwidthSilenceTests` pins this.
        let interior = binCount - 2
        var interiorCount = Int32(interior)
        outputReal.withUnsafeMutableBufferPointer { realBuffer in
            outputImaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress, let imaginaryBase = imaginaryBuffer.baseAddress
                else { return }
                var split = DSPSplitComplex(realp: realBase + 1, imagp: imaginaryBase + 1)
                magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                    guard let magnitudeBase = magnitudeBuffer.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magnitudeBase + 1, 1, vDSP_Length(interior))
                    vvsqrtf(magnitudeBase + 1, magnitudeBase + 1, &interiorCount)
                    var scale = magnitudeScale
                    vDSP_vsmul(magnitudeBase + 1, 1, &scale, magnitudeBase + 1, 1, vDSP_Length(interior))
                }
            }
        }
        // DC and Nyquist come back packed into element 0, so they are unpacked into the first and last
        // bins rather than summed into one — energy at Nyquist appearing in the bass is precisely the
        // wrong failure for a measurement of where high-frequency energy stops.
        magnitudes[0] = abs(outputReal[0]) * magnitudeScale * 0.5
        magnitudes[binCount - 1] = abs(outputImaginary[0]) * magnitudeScale * 0.5
    }

    mutating func splitWindowIntoHalves() {
        let half = fftSize / 2
        windowed.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            evens.withUnsafeMutableBufferPointer { evenBuffer in
                odds.withUnsafeMutableBufferPointer { oddBuffer in
                    guard let evenBase = evenBuffer.baseAddress, let oddBase = oddBuffer.baseAddress
                    else { return }
                    var split = DSPSplitComplex(realp: evenBase, imagp: oddBase)
                    base.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
            }
        }
    }
}
