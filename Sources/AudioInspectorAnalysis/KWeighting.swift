import Foundation

/// The two-stage K-weighting pre-filter of **ITU-R BS.1770-5, Annex 1, Tables 1 and 2, at 48 kHz**.
///
/// ## The coefficients are transcribed, never derived
///
/// They are the *only* coefficients BS.1770-5 publishes: no analogue prototype, no per-rate table and no
/// discretisation method appears anywhere in Annex 1. Nothing here was refitted, re-derived, or taken
/// from another implementation — which is why the cascade exists for one sample rate and refuses to
/// pretend otherwise. The Recommendation notes that the algorithm is insensitive to *small variations*
/// in these values; that licenses a numeric format, not different numbers.
///
/// Both stages are second-order sections in the Recommendation's own Fig. 3 form, with *a*<sub>0</sub>
/// implied as 1 and the *a* coefficients **subtracted** in the feedback path — which is why they appear
/// negated in the recurrence below rather than re-signed in the tables.
///
/// ## Written out rather than delegated to `vDSP_biquadD`, and the reason is measured
///
/// Accelerate's biquad was implemented first and rejected: its output changed in the last two or three
/// significant digits with the chunk size it was handed, because how it groups an IIR's work depends on
/// the length of the run. Every other analysis in this package is chunk-independent *exactly*, and a
/// loudness value that moved with the decoder's buffer size would be a reproducibility defect at any
/// magnitude. A scalar recurrence has no grouping to vary: each output depends on the two before it, in
/// index order, whatever the caller's buffering.
///
/// ## Transposed direct form II
///
/// Chosen over direct form I for its state: two values per section rather than four, and the state *is*
/// the filter's memory, so carrying it across a chunk boundary is carrying two `Double`s.
enum KWeighting {
    /// Stage 1 — the shelving filter modelling the acoustic effect of a rigid-sphere head.
    /// BS.1770-5 Annex 1, **Table 1**.
    static let stage1B0 = 1.53512485958697
    static let stage1B1 = -2.69169618940638
    static let stage1B2 = 1.19839281085285
    static let stage1A1 = -1.69065929318241
    static let stage1A2 = 0.73248077421585

    /// Stage 2 — the RLB (revised low-frequency B-curve) high-pass.
    /// BS.1770-5 Annex 1, **Table 2**.
    static let stage2B0 = 1.0
    static let stage2B1 = -2.0
    static let stage2B2 = 1.0
    static let stage2A1 = -1.99004745483398
    static let stage2A2 = 0.99007225036621

    /// Two state values per section, two sections.
    static let stateCount = 4

    /// One sample through both stages, advancing `state` in place.
    ///
    /// `state[0...1]` belong to stage 1 and `state[2...3]` to stage 2. The recurrence is
    /// `y = b₀x + s₁`, `s₁ = b₁x − a₁y + s₂`, `s₂ = b₂x − a₂y`.
    @inline(__always)
    static func apply(_ sample: Double, state: UnsafeMutablePointer<Double>) -> Double {
        let firstOut = stage1B0 * sample + state[0]
        state[0] = stage1B1 * sample - stage1A1 * firstOut + state[1]
        state[1] = stage1B2 * sample - stage1A2 * firstOut

        let secondOut = stage2B0 * firstOut + state[2]
        state[2] = stage2B1 * firstOut - stage2A1 * secondOut + state[3]
        state[3] = stage2B2 * firstOut - stage2A2 * secondOut

        return secondOut
    }
}
