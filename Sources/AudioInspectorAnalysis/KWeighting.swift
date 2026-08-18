import Foundation

/// The two-stage K-weighting pre-filter of **ITU-R BS.1770-5, Annex 1**, at the rate a stream carries.
///
/// ## What the Recommendation publishes, and what it does not
///
/// Tables 1 and 2 give coefficients **for 48 kHz alone**, and both tables carry the same instruction for
/// every other rate: implementations will require different values, *chosen to provide the same frequency
/// response that the specified filter provides at 48 kHz*. Annex 1 publishes **no** analogue prototype,
/// **no** per-rate table and **no** discretisation method, so how that response is reached is the
/// implementation's own work and its own claim (ADR-0022 §3).
///
/// This type therefore does two different things, and never blurs them:
///
/// - **At 48 kHz it uses the published coefficients literally**, transcribed and untouched. Not passed
///   through the derivation below, even though that reproduces the response to 0.000000 dB: the
///   round-trip is not bit-identical (4.4 × 10⁻¹⁶ on stage 1), and "the published numbers ran" should
///   mean exactly that.
/// - **At every other rate it derives coefficients** by the construction in `derived(at:)`, which is
///   ours. The weighting identity the measurement carries says which of the two happened.
///
/// ## Transposed direct form II
///
/// Chosen over direct form I for its state: two values per section rather than four, and the state *is*
/// the filter's memory, so carrying it across a chunk boundary is carrying two `Double`s.
///
/// ## Written out rather than delegated to `vDSP_biquadD`, and the reason is measured
///
/// Accelerate's biquad was implemented first and rejected: its output changed in the last two or three
/// significant digits with the chunk size it was handed, because how it groups an IIR's work depends on
/// the length of the run. A scalar recurrence has no grouping to vary — each output depends on the two
/// before it, in index order, whatever the caller's buffering.
struct KWeighting {

    /// One second-order section in the Recommendation's own Fig. 3 form: *a*<sub>0</sub> implied as 1,
    /// and the *a* coefficients **subtracted** in the feedback path.
    struct Section: Equatable {
        let b0, b1, b2, a1, a2: Double

        /// Whether the section is stable — both poles strictly inside the unit circle. Checked for every
        /// derived section rather than assumed: a filter that rings forever would produce a number, and
        /// the number would be worthless.
        var isStable: Bool {
            let discriminant = a1 * a1 - 4 * a2
            guard discriminant >= 0 else { return a2.squareRoot() < 1 }
            let root = discriminant.squareRoot()
            return max(abs((-a1 + root) / 2), abs((-a1 - root) / 2)) < 1
        }
    }

    /// The rate BS.1770-5 publishes coefficients for.
    static let publishedSampleRate = 48_000.0

    /// Stage 1 — the shelving filter modelling the acoustic effect of a rigid-sphere head.
    /// BS.1770-5 Annex 1, **Table 1**. Transcribed, never re-derived or refitted.
    static let publishedStage1 = Section(
        b0: 1.53512485958697,
        b1: -2.69169618940638,
        b2: 1.19839281085285,
        a1: -1.69065929318241,
        a2: 0.73248077421585
    )

    /// Stage 2 — the RLB (revised low-frequency B-curve) high-pass.
    /// BS.1770-5 Annex 1, **Table 2**. Transcribed, never re-derived or refitted.
    static let publishedStage2 = Section(
        b0: 1.0,
        b1: -2.0,
        b2: 1.0,
        a1: -1.99004745483398,
        a2: 0.99007225036621
    )

    /// Two state values per section, two sections.
    static let stateCount = 4

    let stage1: Section
    let stage2: Section
    /// Whether the coefficients above are the published ones or this project's derivation.
    let isPublished: Bool

    /// Fails on a rate no stream can have, or on a derivation that came out unstable.
    init?(sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        if sampleRate == Self.publishedSampleRate {
            stage1 = Self.publishedStage1
            stage2 = Self.publishedStage2
            isPublished = true
        } else {
            stage1 = Self.derived(Self.publishedStage1, at: sampleRate)
            stage2 = Self.derived(Self.publishedStage2, at: sampleRate)
            isPublished = false
        }
        guard stage1.isStable, stage2.isStable else { return nil }
    }

    /// One sample through both stages, advancing `state` in place.
    ///
    /// `state[0...1]` belong to stage 1 and `state[2...3]` to stage 2. The recurrence is
    /// `y = b₀x + s₁`, `s₁ = b₁x − a₁y + s₂`, `s₂ = b₂x − a₂y`.
    ///
    /// The sections are passed in rather than read off `self`, so the caller can hoist them out of its
    /// loop and keep them in registers — the coefficients used to be compile-time constants, and this is
    /// what keeps the hot path costing what it did.
    @inline(__always)
    static func apply(
        _ sample: Double, _ stage1: Section, _ stage2: Section, state: UnsafeMutablePointer<Double>
    ) -> Double {
        let firstOut = stage1.b0 * sample + state[0]
        state[0] = stage1.b1 * sample - stage1.a1 * firstOut + state[1]
        state[1] = stage1.b2 * sample - stage1.a2 * firstOut

        let secondOut = stage2.b0 * firstOut + state[2]
        state[2] = stage2.b1 * firstOut - stage2.a1 * secondOut + state[3]
        state[3] = stage2.b2 * firstOut - stage2.a2 * secondOut

        return secondOut
    }
}

// MARK: - The derivation, which is ours and not the Recommendation's

extension KWeighting {
    /// An analogue second-order section, `(n2·s² + n1·s + n0) / (d2·s² + d1·s + d0)`.
    ///
    /// **BS.1770-5 publishes no such prototype.** This is a construction of this project: the analogue
    /// filter that the published 48 kHz section is the bilinear transform *of*. Nothing here may be
    /// described as normative.
    struct Prototype {
        let n2, n1, n0, d2, d1, d0: Double

        /// The denominator's natural frequency in Hz — the section's own characteristic frequency,
        /// derived from the section rather than quoted from anywhere.
        var naturalFrequency: Double { (d0 / d2).squareRoot() / (2 * .pi) }
    }

    /// The bilinear transform's constant at `sampleRate`, prewarped so that `frequency` maps exactly
    /// between the analogue and digital axes: `K = ω₀ / tan(ω₀ / 2f_s)`.
    static func bilinearConstant(sampleRate: Double, prewarping frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency
        return omega / tan(Double.pi * frequency / sampleRate)
    }

    /// Recovers the analogue section a digital one is the bilinear transform of, by substituting
    /// `z⁻¹ = (K − s)/(K + s)` and clearing denominators.
    static func prototype(of section: Section, constant K: Double) -> Prototype {
        Prototype(
            n2: section.b0 - section.b1 + section.b2,
            n1: 2 * K * (section.b0 - section.b2),
            n0: K * K * (section.b0 + section.b1 + section.b2),
            d2: 1 - section.a1 + section.a2,
            d1: 2 * K * (1 - section.a2),
            d0: K * K * (1 + section.a1 + section.a2)
        )
    }

    /// Discretises an analogue section by the bilinear transform, `s = K(1 − z⁻¹)/(1 + z⁻¹)`.
    static func discretise(_ prototype: Prototype, constant K: Double) -> Section {
        let squared = K * K
        let b0 = prototype.n2 * squared + prototype.n1 * K + prototype.n0
        let b1 = -2 * prototype.n2 * squared + 2 * prototype.n0
        let b2 = prototype.n2 * squared - prototype.n1 * K + prototype.n0
        let a0 = prototype.d2 * squared + prototype.d1 * K + prototype.d0
        let a1 = -2 * prototype.d2 * squared + 2 * prototype.d0
        let a2 = prototype.d2 * squared - prototype.d1 * K + prototype.d0
        return Section(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// The published section re-expressed at `sampleRate`, to reproduce its 48 kHz frequency response.
    ///
    /// **Recover, then re-discretise, prewarped at the section's own natural frequency.** Three
    /// properties earn that choice, all measured in
    /// `docs/spikes/2026-08-18-loudness-measurement-validation.md` Part D:
    ///
    /// 1. **The 48 kHz round-trip is exact in the response** — 0.000000 dB — for *any* prewarp
    ///    frequency, because the recovery and the re-discretisation then use the same constant. So the
    ///    choice below cannot compromise the one rate the Recommendation actually specifies.
    /// 2. **Prewarping each section at its own characteristic frequency is derived, not chosen.** The
    ///    frequency comes from the recovered denominator, so nothing here is a tuned constant a reader
    ///    would have to take on trust. Prewarping both sections at one frequency is measurably worse
    ///    (0.052 dB against 0.008 dB), and the plain unprewarped transform is worse again (0.016 dB).
    /// 3. **A numerical optimiser buys 4.6 %** — 0.00736 dB against 0.00771 dB — while replacing a
    ///    one-line definition with two fitted numbers that would need re-deriving whenever anything
    ///    changed. Not worth it.
    ///
    /// The bilinear transform warps the frequency axis, so a common analogue prototype cannot reproduce
    /// the 48 kHz response *everywhere*; what it does is agree closely where the weighting has slope and
    /// diverge where it is flat. The worst residual across 44.1–192 kHz is **0.0077 dB at ~2.7 kHz**.
    static func derived(_ section: Section, at sampleRate: Double) -> Section {
        let reference = 2 * publishedSampleRate
        let characteristic = prototype(of: section, constant: reference).naturalFrequency
        let atReference = bilinearConstant(
            sampleRate: publishedSampleRate, prewarping: characteristic
        )
        let atTarget = bilinearConstant(sampleRate: sampleRate, prewarping: characteristic)
        return discretise(prototype(of: section, constant: atReference), constant: atTarget)
    }
}
