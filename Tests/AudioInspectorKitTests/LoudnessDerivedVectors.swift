import Foundation

// The loudness vectors this project derives, kept apart from the ones it transcribes.
//
// Everything here follows from ITU-R BS.1770-5's algorithm rather than from a published table of
// expected readings. They are useful targets and **not compliance evidence**, which is why they live in
// their own file and carry `.derived` authority: a reader who opens `LoudnessTestVectors.swift` sees
// only material the publishers stand behind.

extension LoudnessTestVector {

    // MARK: Derived — the block boundary

    /// A programme of exactly one gating block is measured; one frame less produces no block at all.
    ///
    /// Derived, not published: it follows from BS.1770-5 eq. (3)'s index set, whose upper bound is
    /// ⌊(T − 400 ms) / 100 ms⌋ — zero at exactly 400 ms and negative below it.
    private static func boundary(
        milliseconds: Double, expectation: LoudnessExpectation, discriminates: String
    ) -> LoudnessTestVector {
        LoudnessTestVector(
            name: "boundary-\(Int(milliseconds))ms",
            authority: .derived(rationale: "BS.1770-5 eq. (3) block index set at the 400 ms edge"),
            sampleRate: 48_000,
            channels: 2,
            frequency: 1_000,
            segments: [LoudnessSegmentSpec(dBFS: -20.0, seconds: milliseconds / 1_000)],
            expectation: expectation,
            discriminates: discriminates
        )
    }

    static let blockBoundaryVectors: [LoudnessTestVector] = [
        boundary(
            milliseconds: 399,
            expectation: .notComputable(oracleFloor: -70.0),
            discriminates: "one frame short of a block yields no block, so there is nothing to report"
        ),
        boundary(
            milliseconds: 400,
            expectation: .measured(lufs: -20.0, tolerance: publishedTolerance),
            discriminates: "exactly one block is a complete measurement — the edge is inclusive"
        ),
        boundary(
            milliseconds: 401,
            expectation: .measured(lufs: -20.0, tolerance: publishedTolerance),
            discriminates: "a partial second block is discarded without disturbing the first"
        ),
    ]

    // MARK: Derived — digital silence

    /// Silence long enough to form many blocks, none of which survives the absolute gate.
    ///
    /// A different cause from the 399 ms vector — blocks exist here and are all gated away — reaching
    /// the same outcome. The oracle shows its floor for both, which is precisely why the expectation
    /// records the floor as the *oracle's*, not as a reading.
    private static func silence(seconds: Double) -> LoudnessTestVector {
        LoudnessTestVector(
            name: "silence-\(Int(seconds))s",
            authority: .derived(rationale: "BS.1770-5 eq. (6): a silent block's loudness is −∞ and fails Γa"),
            sampleRate: 48_000,
            channels: 2,
            frequency: 1_000,
            segments: [LoudnessSegmentSpec(dBFS: nil, seconds: seconds)],
            expectation: .notComputable(oracleFloor: -70.0),
            discriminates: "every block gated away is an absence, and −70 is the gate rather than a reading"
        )
    }

    static let silenceVectors: [LoudnessTestVector] = [silence(seconds: 1), silence(seconds: 10)]

    // MARK: Derived — the sample-rate sweep

    /// Every rate the product supports, carrying §2.9's calibration signal.
    ///
    /// **Derived, and the reason matters**: Tech 3341's signals are published synthesised at 48 kHz, so
    /// only the 48 kHz row is normative. The rest state the acceptance target for the per-rate
    /// derivation ADR-0022 §3 commits to — they do **not** validate it, because nothing is implemented.
    ///
    /// Five seconds rather than twenty: the reading is level-determined, and 192 kHz is expensive.
    static let sampleRateVectors: [LoudnessTestVector] = [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]
        .map { rate in
            LoudnessTestVector(
                name: "rate-\(Int(rate))",
                authority: .derived(rationale: "Tech 3341's signals are published at 48 kHz only"),
                sampleRate: rate,
                channels: 2,
                frequency: 1_000,
                segments: steady(-18.0, seconds: 5),
                expectation: .measured(lufs: -18.0, tolerance: publishedTolerance),
                discriminates: "the weighting is adapted to the rate rather than assumed to be 48 kHz"
            )
        }

    // MARK: Derived — the channel pair

    /// The same tone in mono and in stereo. Their difference is 10·log₁₀2 = 3.0103 dB, which is what
    /// BS.1770-5 Table 3's equal weights plus energy summation predict — and the single measurement
    /// that shows the channels are summed rather than averaged.
    static let monoAgainstStereo: (mono: LoudnessTestVector, stereo: LoudnessTestVector) = (
        mono: LoudnessTestVector(
            name: "channels-mono-23",
            authority: .derived(rationale: "BS.1770-5 Table 3: a lone channel weighs 1.0, whichever of L/C/R it is"),
            sampleRate: 48_000,
            channels: 1,
            frequency: 1_000,
            segments: steady(-23.0, seconds: 20),
            expectation: .measured(lufs: -26.01, tolerance: publishedTolerance),
            discriminates: "one channel of weight 1.0, with no summation to raise it"
        ),
        stereo: table1Test1
    )

    /// 10·log₁₀2, the exact difference between the pair above.
    static let stereoOverMonoLU = 10 * log10(2.0)
}
