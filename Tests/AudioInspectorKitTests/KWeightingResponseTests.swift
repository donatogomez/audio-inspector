import Foundation
import Testing

@testable import AudioInspectorAnalysis

// Whether the derived coefficients reproduce the response BS.1770-5 publishes for 48 kHz.
//
// **The reference is evaluated here, not asked of production.** `magnitudeDB` below is this suite's own
// arithmetic over a section's coefficients; nothing calls into `KWeighting` to find out what `KWeighting`
// should do. What production supplies is the coefficients, which is the thing under test.
//
// The comparison is on **absolute analogue frequency** — 40 Hz against 40 Hz — never on a fraction of
// Nyquist. Comparing normalised frequencies would compare two different filters and call them equal.

@Suite("Analysis — K-weighting response across sample rates")
struct KWeightingResponseTests {

    /// Rates the derivation is claimed at.
    static let rates = [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]

    /// The band a loudness measurement is judged over. 20 kHz sits below Nyquist at every rate here, so
    /// one band serves them all.
    private let lowest = 20.0
    private let highest = 20_000.0
    private let points = 2_000

    /// **The tolerance, and where it comes from.** BS.1770-5 states none — it asks only for "the same
    /// frequency response" and notes that the algorithm is *not sensitive to small variations* in the
    /// coefficients. So this is chosen from measurement rather than quoted:
    ///
    /// - the published compliance tolerance is **±0.1 LUFS** (EBU Tech 3341, Report BS.2217-2), and a
    ///   response error of *E* dB can move a reading by at most *E*, so anything well under 0.1 cannot
    ///   change a compliance verdict;
    /// - FFmpeg's own reading drifts **0.03 LU** across these same rates, so a bound tighter than that
    ///   would be claiming more agreement than the reference implementation has with itself;
    /// - **0.02 dB** sits under both, and the worst error this derivation actually produces is
    ///   **0.0077 dB**, leaving a factor of 2.6.
    ///
    /// It is deliberately not set at the observed error: a tolerance fitted to today's measurement tests
    /// nothing but today's measurement.
    static let responseTolerance = 0.02

    // MARK: - The reference, computed here

    /// |H(e^{jω})| in dB for one section at absolute frequency `f`.
    private func magnitudeDB(_ section: KWeighting.Section, at frequency: Double, rate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / rate
        let (cosOne, sinOne) = (cos(omega), sin(omega))
        let (cosTwo, sinTwo) = (cos(2 * omega), sin(2 * omega))
        let realNumerator = section.b0 + section.b1 * cosOne + section.b2 * cosTwo
        let imagNumerator = -(section.b1 * sinOne + section.b2 * sinTwo)
        let realDenominator = 1 + section.a1 * cosOne + section.a2 * cosTwo
        let imagDenominator = -(section.a1 * sinOne + section.a2 * sinTwo)
        let numerator = realNumerator * realNumerator + imagNumerator * imagNumerator
        let denominator = realDenominator * realDenominator + imagDenominator * imagDenominator
        return 10 * log10(numerator / denominator)
    }

    private func cascadeDB(_ weighting: KWeighting, at frequency: Double, rate: Double) -> Double {
        magnitudeDB(weighting.stage1, at: frequency, rate: rate)
            + magnitudeDB(weighting.stage2, at: frequency, rate: rate)
    }

    /// Log-spaced sweep over the judged band.
    private var sweep: [Double] {
        (0 ... points).map { lowest * pow(highest / lowest, Double($0) / Double(points)) }
    }

    /// The published 48 kHz cascade's response — the thing every other rate must reproduce.
    private func reference(at frequency: Double) -> Double {
        magnitudeDB(KWeighting.publishedStage1, at: frequency, rate: KWeighting.publishedSampleRate)
            + magnitudeDB(KWeighting.publishedStage2, at: frequency, rate: KWeighting.publishedSampleRate)
    }

    private func worstError(_ weighting: KWeighting, rate: Double) -> (maximum: Double, frequency: Double) {
        var worst = 0.0
        var worstFrequency = 0.0
        for frequency in sweep {
            let error = abs(cascadeDB(weighting, at: frequency, rate: rate) - reference(at: frequency))
            if error > worst { worst = error; worstFrequency = frequency }
        }
        return (worst, worstFrequency)
    }

    // MARK: - The published rate is untouched

    /// 48 kHz uses the published coefficients **literally**, not the derivation's round-trip of them. The
    /// round-trip reproduces the response to 0.000000 dB but not the coefficients bit for bit (4.4 × 10⁻¹⁶
    /// on stage 1), and "the published numbers ran" should mean exactly that.
    @Test("at 48 kHz the published coefficients are used unchanged, bit for bit")
    func publishedRateUsesPublishedCoefficients() throws {
        let weighting = try #require(KWeighting(sampleRate: 48_000))
        #expect(weighting.stage1 == KWeighting.publishedStage1)
        #expect(weighting.stage2 == KWeighting.publishedStage2)
        #expect(weighting.isPublished)
    }

    @Test("every other rate is marked as derived rather than published")
    func otherRatesAreMarkedDerived() throws {
        for rate in Self.rates where rate != KWeighting.publishedSampleRate {
            let weighting = try #require(KWeighting(sampleRate: rate))
            #expect(!weighting.isPublished, "\(rate)")
        }
    }

    // MARK: - The round-trip gate

    /// A construction that claims to derive *from* the reference must be able to return to it. Asserted on
    /// the response rather than on the coefficients, because the transform is not required to be
    /// bit-exact — but it is exact here to well under a millionth of a decibel.
    @Test("deriving back to 48 kHz reproduces the published response exactly")
    func roundTripAtThePublishedRate() {
        let stage1 = KWeighting.derived(KWeighting.publishedStage1, at: 48_000)
        let stage2 = KWeighting.derived(KWeighting.publishedStage2, at: 48_000)
        for frequency in sweep {
            let derived = magnitudeDB(stage1, at: frequency, rate: 48_000)
                + magnitudeDB(stage2, at: frequency, rate: 48_000)
            #expect(abs(derived - reference(at: frequency)) < 1e-9, "at \(frequency) Hz")
        }
    }

    @Test("the round-trip recovers the published coefficients to floating-point noise")
    func roundTripRecoversCoefficients() {
        let stage1 = KWeighting.derived(KWeighting.publishedStage1, at: 48_000)
        let published = KWeighting.publishedStage1
        for (derived, original) in [
            (stage1.b0, published.b0), (stage1.b1, published.b1), (stage1.b2, published.b2),
            (stage1.a1, published.a1), (stage1.a2, published.a2),
        ] {
            #expect(abs(derived - original) < 1e-14)
        }
    }

    // MARK: - The claim itself

    @Test("every supported rate reproduces the published response within tolerance", arguments: rates)
    func responseMatchesAtEveryRate(_ rate: Double) throws {
        let weighting = try #require(KWeighting(sampleRate: rate))
        let (maximum, frequency) = worstError(weighting, rate: rate)
        #expect(
            maximum <= Self.responseTolerance,
            "\(rate) Hz: worst \(maximum) dB at \(frequency) Hz"
        )
    }

    @Test("every derived filter is stable", arguments: rates)
    func derivedFiltersAreStable(_ rate: Double) throws {
        let weighting = try #require(KWeighting(sampleRate: rate))
        #expect(weighting.stage1.isStable, "\(rate) stage 1")
        #expect(weighting.stage2.isStable, "\(rate) stage 2")
    }

    /// The tolerance has teeth: using the 48 kHz coefficients unadapted at another rate — the mistake the
    /// derivation exists to prevent — misses it by a wide margin.
    @Test("using the published coefficients unadapted at another rate misses the tolerance")
    func unadaptedCoefficientsFailTheBound() {
        var worst = 0.0
        for frequency in sweep {
            let unadapted = magnitudeDB(KWeighting.publishedStage1, at: frequency, rate: 44_100)
                + magnitudeDB(KWeighting.publishedStage2, at: frequency, rate: 44_100)
            worst = max(worst, abs(unadapted - reference(at: frequency)))
        }
        #expect(worst > Self.responseTolerance * 10, "unadapted worst error was only \(worst) dB")
    }

    /// Prewarping each section at its **own** natural frequency is not decoration. Prewarping both at one
    /// frequency is measurably worse, which is why the derivation takes the frequency from each section
    /// rather than from a constant.
    @Test("prewarping both sections at one frequency is worse than treating them separately")
    func perSectionPrewarpingEarnsItsPlace() throws {
        let proper = try #require(KWeighting(sampleRate: 192_000))
        let (properWorst, _) = worstError(proper, rate: 192_000)

        // Both sections forced through stage 1's characteristic frequency.
        let shared = KWeighting.prototype(
            of: KWeighting.publishedStage1, constant: 2 * KWeighting.publishedSampleRate
        ).naturalFrequency
        func forced(_ section: KWeighting.Section) -> KWeighting.Section {
            let atReference = KWeighting.bilinearConstant(sampleRate: 48_000, prewarping: shared)
            let atTarget = KWeighting.bilinearConstant(sampleRate: 192_000, prewarping: shared)
            return KWeighting.discretise(
                KWeighting.prototype(of: section, constant: atReference), constant: atTarget
            )
        }
        var forcedWorst = 0.0
        for frequency in sweep {
            let value = magnitudeDB(forced(KWeighting.publishedStage1), at: frequency, rate: 192_000)
                + magnitudeDB(forced(KWeighting.publishedStage2), at: frequency, rate: 192_000)
            forcedWorst = max(forcedWorst, abs(value - reference(at: frequency)))
        }
        #expect(forcedWorst > properWorst * 3, "forced \(forcedWorst) vs proper \(properWorst)")
    }
}
