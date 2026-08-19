import AudioInspectorAnalysis
import AudioInspectorDomain
import Foundation
import Testing

// Three faults the full suite found once the accumulator met every other suite's fixtures. All three
// are real, all three are fixed, and none would be caught by a test about bandwidth: they are about the
// arithmetic surviving inputs `PCMChunk` permits.
//
// `PCMChunk` bounds **samples** — finite, no NaN, no infinity — and says nothing about what a windowed
// transform of them can produce. That gap is where all three live, and the shape of the input decides
// which of them it reaches, because the magnitudes are computed by **two different routes**:
//
// - the **interior** bins go through `vDSP_zvmags` and `vvsqrtf`, so each component is squared. A
//   component below about 2.6 × 10⁻²³ squares to zero and a component above about 1.8 × 10¹⁹ squares to
//   infinity — the squaring narrows the representable range from both ends;
// - **DC and Nyquist** come back packed into element 0 and are taken linearly, `abs(…) · scale · 0.5`,
//   with no squaring at all. They therefore survive amplitudes at which every interior bin has already
//   collapsed to zero.
//
// That asymmetry is why a quiet **sine** cannot reach the budget arithmetic and a quiet **Nyquist-rate
// alternation** can, and it is the reason the first version of this suite did not pin its own fix.

@Suite("Analysis — significant bandwidth survives numeric extremes")
struct SignificantBandwidthNumericExtremeTests {

    private func measure(_ samples: [Float], rate: Double = 48_000) throws -> SignificantBandwidth? {
        var accumulator = try #require(SignificantBandwidthAccumulator(sampleRate: rate, channelCount: 1))
        var start = 0
        while start < samples.count {
            let count = min(4_096, samples.count - start)
            accumulator.accumulate(try PCMChunk(startFrame: start, channels: [Array(samples[start ..< start + count])]))
            start += count
        }
        return accumulator.finish()
    }

    /// A signal at exactly Nyquist — the **linear** route into the magnitudes, and the only one that
    /// carries a denormal amplitude through to a positive spectral peak.
    private func nyquistAlternation(amplitude: Float, frames: Int = 4_096) -> [Float] {
        (0 ..< frames).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
    }

    private func sine(amplitude: Double, frames: Int = 8_192) -> [Float] {
        (0 ..< frames).map { Float(amplitude * sin(2 * Double.pi * 5_000 * Double($0) / 48_000)) }
    }

    // MARK: Underflow — the budget must be subtracted in decibels

    /// A quiet **sine**: honest either way, and — recorded plainly — **it does not reach the fix.**
    ///
    /// Below about 10⁻³⁸ every interior magnitude squares to zero, so no window carries a positive peak,
    /// `filePeak` stays zero and `finish()` returns before the budget is computed at all. That is a
    /// correct absence, and it is also why this test passed with the underflowing multiplication in
    /// place. It is kept for the absence, not for the arithmetic — `quietProgrammeOnTheLinearBins` is
    /// what pins the arithmetic.
    @Test("an extremely quiet sine is measured or absent, never a trap", arguments: [1e-30, 1e-38, 1e-42, 1e-44])
    func extremelyQuietSine(amplitude: Double) throws {
        let measurement = try measure(sine(amplitude: amplitude))
        if let overall = measurement?.overall {
            #expect(overall.frequency.isFinite, "published a non-finite frequency at amplitude \(amplitude)")
            #expect(overall.resolution.isFinite && overall.resolution > 0)
            #expect(overall.frequency >= 0)
        }
    }

    /// **The budget must be subtracted in decibels, never applied by multiplication** — and this is the
    /// input that proves it.
    ///
    /// `Float` arithmetic underflows `x · 0.001` to exactly zero for every `x` at or below
    /// 6.99 × 10⁻⁴³, measured by bisection rather than assumed. `log10(0)` is −infinity, and the
    /// conversion to a stratum index is `Int(floor(…))`, which traps on an infinity. A programme this
    /// quiet is not an error and the arithmetic must not make it one.
    ///
    /// Reaching that region needs the linear route: an amplitude of 5 × 10⁻⁴³ puts the Nyquist bin's
    /// magnitude at roughly half of it, inside the underflow region, while every interior bin is
    /// already zero. Restoring the multiplication makes this **trap** rather than fail, which is the
    /// loudest failure available — verified, at this amplitude, by applying it.
    ///
    /// The answer is a real one rather than an absence: the signal genuinely is at Nyquist, and the
    /// method reports that bin at the rate's own resolution. Nothing here is a floor or a substitute.
    @Test("a quiet programme on the linear bins reaches the budget arithmetic and is measured",
          arguments: [Float(5e-43), Float(1e-43), Float(1e-44), Float.leastNonzeroMagnitude])
    func quietProgrammeOnTheLinearBins(amplitude: Float) throws {
        let measurement = try #require(
            try measure(nyquistAlternation(amplitude: amplitude)),
            "a positive spectral peak produced no measurement at amplitude \(amplitude)"
        )
        let overall = try #require(measurement.overall, "no reading at amplitude \(amplitude)")
        #expect(overall.frequency == 24_000, "the Nyquist bin was not reported at amplitude \(amplitude)")
        #expect(overall.resolution == 48_000.0 / 2_048.0)
        #expect(overall.frequency.isFinite && overall.resolution.isFinite)
    }

    // MARK: Overflow — two different ways, and two different protections

    /// **A finite input can produce a transform that is not a number.**
    ///
    /// A Hann-windowed transform of enormous-but-finite samples overflows `Float`, and the butterflies
    /// then subtract infinities: the magnitudes come back `NaN`. `NaN > peak` is false, so no window
    /// carries a positive peak, and the accumulator's **eligibility rule** — a window with no energy is
    /// not an observation — already dictates the answer. A file the transform cannot represent produces
    /// an **absence**, which is the semantics this type already had rather than a new one invented for
    /// the case.
    ///
    /// The absence is asserted at the accumulator, not merely at `overall`: `finish()` itself returns
    /// nothing, so there is no measurement carrying an empty reading and no method identity published
    /// for a file that was never measured. Removing the eligibility guard makes this trap.
    @Test("an input the transform cannot represent is an absence, not a trap")
    func transformOverflowToNaN() throws {
        let frames = 16_384
        let samples = (0 ..< frames).map { $0.isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude }
        let measurement = try measure(samples)
        #expect(measurement == nil, "a file the transform cannot represent produced \(String(describing: measurement))")
    }

    /// **The other overflow, and the one the finiteness clamp actually exists for.**
    ///
    /// Between roughly 3 × 10¹⁶ and the top of `Float`, the components stay finite but their *squares*
    /// do not: `vDSP_zvmags` returns infinity, `vvsqrtf` keeps it, and the bin's magnitude is `+∞`.
    /// Unlike a `NaN`, that **is** greater than zero, so the window passes the eligibility rule and
    /// reaches the conversion to a stratum index — where `20 · log10(∞)` would be infinite and
    /// `Int(floor(…))` would trap. Clamping to the widest finite value keeps the window as what it is:
    /// an observation carrying energy, filed at the top stratum rather than discarded.
    ///
    /// This is why `transformOverflowToNaN` cannot stand in for it. Removing the clamp leaves that test
    /// passing and makes this one trap, which is the distinction the previous version of this suite was
    /// missing.
    @Test("a magnitude that overflows to infinity is filed, not trapped", arguments: [1e18, 1e25, 1e35])
    func magnitudeOverflowToInfinity(amplitude: Double) throws {
        let measurement = try #require(try measure(sine(amplitude: amplitude)))
        let overall = try #require(measurement.overall, "an infinite magnitude was discarded at \(amplitude)")
        #expect(overall.frequency.isFinite, "published a non-finite frequency at amplitude \(amplitude)")
        #expect(overall.frequency >= 0 && overall.frequency <= 24_000, "published a frequency above Nyquist")
        #expect(overall.resolution == 48_000.0 / 2_048.0)
    }

    /// The extremes in one file, because a file can hold them — and because this is the case that
    /// separates "absent" from "trapped". The overflowing half yields nothing; the quiet half is
    /// ordinary audio, and whatever the method makes of it must be finite.
    @Test("a file holding both extremes still finishes, with a finite answer or none")
    func bothExtremesTogether() throws {
        let half = 8_192
        var samples = (0 ..< half).map { $0.isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude }
        samples += (0 ..< half).map { Float(1e-40 * sin(2 * Double.pi * 5_000 * Double($0) / 48_000)) }
        let measurement = try measure(samples)
        if let overall = measurement?.overall {
            #expect(overall.frequency.isFinite)
            #expect(overall.resolution.isFinite && overall.resolution > 0)
        }
    }
}
