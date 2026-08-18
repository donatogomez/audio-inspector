import AVFoundation
import Foundation
import Testing

// The official loudness test vectors, as data.
//
// This file is a **transcription of published material**, not an implementation of anything. It
// describes signals and the readings the publishers say a compliant meter must produce; it computes no
// loudness, filters nothing, and contains no part of ITU-R BS.1770. When `LoudnessAccumulator` exists it
// will be measured against this table — the table does not move to meet it.
//
// Sources, read in full and recorded in `docs/spikes/2026-08-18-loudness-measurement-validation.md`:
//
// - **EBU Tech 3341 v4 (11/2023)** — §2.9 calibration signal, and Table 1 tests 1–5 with their
//   expected responses and the tolerance that accompanies them.
// - **ITU-R BS.1770-5 (11/2023)** — Annex 1's own calibration statement.
// - **Report ITU-R BS.2217-2 (10/2016)** — the ±0.1 LKFS compliance tolerance.
//
// Two kinds of vector live here and they are **never mixed**: see `LoudnessVectorAuthority`. A vector
// whose signal *or* whose expected value is ours is `derived`, and a derived vector may never be cited
// as compliance evidence.
//
// No audio binary enters the repository. Every vector is generated on demand into a temporary
// directory through the existing `AudioFixtureSupport` writer and removed with it.

// MARK: - Authority

/// Where a vector's expected value comes from. The distinction is the point of this file.
enum LoudnessVectorAuthority: Equatable {
    /// Both the signal and its expected reading are published, and the tolerance is the publisher's.
    case normative(document: String, section: String)
    /// Ours: either the signal, the expectation, or both follow from the algorithm rather than from a
    /// published table. Useful, and **not** compliance evidence.
    case derived(rationale: String)

    var isNormative: Bool {
        if case .normative = self { return true }
        return false
    }

    /// How the vector should be cited in a report or a spike table.
    var citation: String {
        switch self {
        case let .normative(document, section): "\(document), \(section)"
        case let .derived(rationale): "derived — \(rationale)"
        }
    }
}

// MARK: - Signal description

/// One region of a vector's signal, described the way the publishers describe it: a level in dBFS and
/// a duration in seconds.
struct LoudnessSegmentSpec: Equatable {
    /// Peak level of the tone in this region, or `nil` for digital silence.
    var dBFS: Double?
    var seconds: Double

    /// Linear peak amplitude. Computed in `Double` and narrowed once, so the value written into the
    /// fixture is the nearest `Float` to the published level rather than the result of a chain of
    /// single-precision steps.
    var amplitude: Float {
        guard let dBFS else { return 0 }
        return Float(pow(10.0, dBFS / 20.0))
    }
}

/// What the publishers say a compliant meter reports for a vector.
enum LoudnessExpectation: Equatable {
    /// A published or derived reading, with the tolerance that belongs to it.
    case measured(lufs: Double, tolerance: Double)
    /// The standard defines **no value** for this signal. A meter will show something — FFmpeg shows
    /// exactly `-70.000` — and that something is its floor, not a measurement.
    ///
    /// The associated value is what the *oracle* is expected to display, recorded so a test can assert
    /// the floor was seen **and** assert that it is not treated as a reading. It must never become the
    /// value this product publishes.
    case notComputable(oracleFloor: Double)
}

// MARK: - A vector

struct LoudnessTestVector {
    var name: String
    var authority: LoudnessVectorAuthority
    var sampleRate: Double
    var channels: AVAudioChannelCount
    /// Tone frequency. Tech 3341 specifies 1000 Hz; BS.1770-5 specifies 997 Hz, which IEC 61606 makes
    /// the exact reference frequency that "1 kHz" names loosely.
    var frequency: Double
    var segments: [LoudnessSegmentSpec]
    var expectation: LoudnessExpectation
    /// The one property this vector protects. Two vectors must not carry the same sentence.
    var discriminates: String

    /// Frames in each segment, rounded once from seconds. Every published duration in Tech 3341 lands
    /// on a whole number of frames at 48 kHz, so no rounding actually occurs there.
    var segmentFrames: [Int] {
        segments.map { Int(($0.seconds * sampleRate).rounded()) }
    }

    var totalFrames: Int { segmentFrames.reduce(0, +) }

    var totalSeconds: Double { Double(totalFrames) / sampleRate }

    var signal: AudioFixtureSignal {
        .segmentedSine(
            frequency: frequency,
            segments: zip(segments, segmentFrames).map {
                AudioFixtureSegment(amplitude: $0.amplitude, frames: $1)
            }
        )
    }

    /// The fixture specification. Always **32-bit float**: the levels here span 0 dBFS down to
    /// −72 dBFS, and a 16-bit container would quantise the quiet end into something the published
    /// expectation no longer describes.
    var fixtureSpec: AudioFixtureSpec {
        AudioFixtureSpec(
            name: name,
            format: .wavFloat,
            signal: signal,
            sampleRate: sampleRate,
            channels: channels,
            frames: AVAudioFrameCount(totalFrames)
        )
    }
}

/// A parameterised case is identified by its name and where it came from, so a failure names the
/// vector rather than printing its whole description.
extension LoudnessTestVector: CustomTestStringConvertible {
    var testDescription: String { "\(name) [\(authority.citation)]" }
}

// MARK: - The published catalogue

extension LoudnessTestVector {
    private static let tech3341 = "EBU Tech 3341 v4 (11/2023)"
    private static let bs1770 = "ITU-R BS.1770-5 (11/2023)"

    /// The tolerance both publishers attach to a compliance reading: **±0.1**.
    /// Tech 3341 Table 1 states it per test; Report BS.2217-2 states it once for its whole set.
    static let publishedTolerance = 0.1

    /// A tone at one level for one duration — the shape of Tech 3341 tests 1 and 2 and of §2.9.
    static func steady(_ dBFS: Double, seconds: Double) -> [LoudnessSegmentSpec] {
        [LoudnessSegmentSpec(dBFS: dBFS, seconds: seconds)]
    }

    // MARK: Tech 3341 §2.9 — the calibration signal

    /// Stereo 1 kHz sine, in phase, peak −18 dBFS; the meter should read −18.0 LUFS.
    ///
    /// Tech 3341 attaches a warning to this signal that is worth carrying into any failure diagnosis:
    /// 1 kHz sits on a slope of the K-weighting filter, so this check is **more** sensitive than one
    /// might expect both to filter accuracy and to the exactness of the tone's frequency.
    ///
    /// No duration is published, so 20 s is ours — taken from Table 1's convention. That does not make
    /// the vector derived: the reading is level-determined and 20 s is far past the point where it
    /// settles.
    static let calibration = LoudnessTestVector(
        name: "t3341-2.9-calibration",
        authority: .normative(document: tech3341, section: "§2.9"),
        sampleRate: 48_000,
        channels: 2,
        frequency: 1_000,
        segments: steady(-18.0, seconds: 20),
        expectation: .measured(lufs: -18.0, tolerance: publishedTolerance),
        discriminates: "the conversion offset — a third level on the line through tests 1 and 2"
    )

    // MARK: Tech 3341 Table 1, tests 1–5

    static let table1Test1 = LoudnessTestVector(
        name: "t3341-01-steady-23",
        authority: .normative(document: tech3341, section: "Table 1, test 1"),
        sampleRate: 48_000,
        channels: 2,
        frequency: 1_000,
        segments: steady(-23.0, seconds: 20),
        expectation: .measured(lufs: -23.0, tolerance: publishedTolerance),
        discriminates: "channel summation — the same tone in mono reads 3.01 LU lower"
    )

    static let table1Test2 = LoudnessTestVector(
        name: "t3341-02-steady-33",
        authority: .normative(document: tech3341, section: "Table 1, test 2"),
        sampleRate: 48_000,
        channels: 2,
        frequency: 1_000,
        segments: steady(-33.0, seconds: 20),
        expectation: .measured(lufs: -33.0, tolerance: publishedTolerance),
        discriminates: "linearity of the energy-to-LUFS conversion — exactly 10 LU below test 1"
    )

    /// 10 s at −36, 60 s at −23, 10 s at −36.
    ///
    /// **The relative gate's lower bound.** Everything here is far above the absolute threshold, so an
    /// implementation with no relative gate at all still produces a number — just the wrong one
    /// (≈−24.2 LUFS). It also fails if the relative offset is too *large* to exclude the −36 dB
    /// passages.
    static let table1Test3 = LoudnessTestVector(
        name: "t3341-03-relative-gate",
        authority: .normative(document: tech3341, section: "Table 1, test 3"),
        sampleRate: 48_000,
        channels: 2,
        frequency: 1_000,
        segments: [
            LoudnessSegmentSpec(dBFS: -36.0, seconds: 10),
            LoudnessSegmentSpec(dBFS: -23.0, seconds: 60),
            LoudnessSegmentSpec(dBFS: -36.0, seconds: 10),
        ],
        expectation: .measured(lufs: -23.0, tolerance: publishedTolerance),
        discriminates: "the relative gate exists, and its offset is not too large"
    )

    /// Test 3 wrapped in 10 s of −72 dBFS at each end.
    ///
    /// **The absolute gate.** Its integrated reading is the same as test 3's, so `I` alone barely
    /// separates them — what separates them is the *threshold* the meter derives: with the absolute
    /// gate the −72 dB passages are removed before the relative threshold is computed, and without it
    /// they drag that threshold down by about 1 LU. The oracle reports the threshold, so the pair is
    /// checked there.
    static let table1Test4 = LoudnessTestVector(
        name: "t3341-04-absolute-gate",
        authority: .normative(document: tech3341, section: "Table 1, test 4"),
        sampleRate: 48_000,
        channels: 2,
        frequency: 1_000,
        segments: [
            LoudnessSegmentSpec(dBFS: -72.0, seconds: 10),
            LoudnessSegmentSpec(dBFS: -36.0, seconds: 10),
            LoudnessSegmentSpec(dBFS: -23.0, seconds: 60),
            LoudnessSegmentSpec(dBFS: -36.0, seconds: 10),
            LoudnessSegmentSpec(dBFS: -72.0, seconds: 10),
        ],
        expectation: .measured(lufs: -23.0, tolerance: publishedTolerance),
        discriminates: "the absolute gate runs before the relative threshold is derived"
    )

    /// 20 s at −26, 20.1 s at −20, 20 s at −26.
    ///
    /// **The relative gate's upper bound, and a negative control.** Correct gating changes nothing
    /// here — the ungated mean is already −23.0 — so this vector cannot be passed by gating harder. It
    /// fails when the relative offset is too *small*, which is exactly the failure test 3 cannot see.
    static let table1Test5 = LoudnessTestVector(
        name: "t3341-05-gating-no-op",
        authority: .normative(document: tech3341, section: "Table 1, test 5"),
        sampleRate: 48_000,
        channels: 2,
        frequency: 1_000,
        segments: [
            LoudnessSegmentSpec(dBFS: -26.0, seconds: 20),
            LoudnessSegmentSpec(dBFS: -20.0, seconds: 20.1),
            LoudnessSegmentSpec(dBFS: -26.0, seconds: 20),
        ],
        expectation: .measured(lufs: -23.0, tolerance: publishedTolerance),
        discriminates: "the relative gate's offset is not too small — over-gating is caught here"
    )

    /// Table 1 tests 1–5, in order. Test 6 (5.0 channel) needs a layout the pipeline cannot supply;
    /// tests 7–8 are authentic programme segments that may be used locally but never committed;
    /// tests 9–14 are momentary/short-term maxima, and 15–23 are true-peak signals belonging to
    /// ADR-0019's measurement.
    static let tech3341Table1: [LoudnessTestVector] = [
        table1Test1, table1Test2, table1Test3, table1Test4, table1Test5,
    ]

    /// Every vector whose signal *and* expected reading are published.
    static let normativeVectors: [LoudnessTestVector] = [calibration] + tech3341Table1

    // MARK: ITU-R BS.1770-5's own anchor

    /// A 0 dBFS, 997 Hz sine in a single channel reads **−3.01 LKFS**.
    ///
    /// Annex 1 states this directly, as a consequence of the algorithm rather than as a compliance
    /// test — so the value is BS.1770-5's and the **tolerance is not**: ±0.1 is borrowed from
    /// BS.2217-2, and that borrowing is deliberate and recorded.
    ///
    /// 997 Hz rather than 1 kHz because Annex 1 says so: IEC 61606 makes 997 Hz the exact reference
    /// frequency that "1 kHz" names in non-critical contexts. It is also the frequency at which the
    /// −0.691 offset exactly cancels the K-weighting gain, which is why this anchor pins the offset
    /// more sharply than a 1 kHz signal can.
    static let bs1770Anchor = LoudnessTestVector(
        name: "bs1770-anchor-mono-0dbfs",
        authority: .normative(document: bs1770, section: "Annex 1, after eq. (7)"),
        sampleRate: 48_000,
        channels: 1,
        frequency: 997,
        segments: steady(0.0, seconds: 20),
        expectation: .measured(lufs: -3.01, tolerance: publishedTolerance),
        discriminates: "the −0.691 conversion offset against the K-weighting gain at its own reference frequency"
    )

    /// The same anchor attenuated by 23 dB. BS.1770-5 states that attenuating the input attenuates the
    /// reading identically, so **−26.01 LKFS** follows from the published anchor — the signal is ours,
    /// the arithmetic is the document's.
    static let bs1770AnchorAttenuated = LoudnessTestVector(
        name: "bs1770-anchor-mono-23dbfs",
        authority: .derived(rationale: "BS.1770-5's 0 dBFS anchor attenuated by 23 dB"),
        sampleRate: 48_000,
        channels: 1,
        frequency: 997,
        segments: steady(-23.0, seconds: 20),
        expectation: .measured(lufs: -26.01, tolerance: publishedTolerance),
        discriminates: "attenuation maps one-for-one onto the reading, at the reference frequency"
    )
}
