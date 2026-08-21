import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureImport

// **Task 5.1, 5.2 and 5.3 — `design.md` §7's ten fixture pairs, run through production.**
//
// Every measurement below came out of a file: written with `AudioFixtureSupport`, decoded by
// `AVFoundationAudioDecoder`, folded by the six shared consumers, collapsed by `FeatureImport` and
// handed to `MeasurementComparison`. **Nothing here constructs a measurement.** That is the whole
// difference between this suite and `MeasurementComparisonTests`, which pins the rules against values
// it wrote itself and is the right instrument for that job and no instrument at all for this one.
//
// **What these tests may say.** They report what the comparison establishes and nothing beyond it.
// A pair that differs in loudness differs in loudness; it is not louder, hotter, more compressed, a
// remaster, a transcode or a better copy. `MeasurementComparisonBoundaryTests` pins that the *type*
// cannot say those things; this suite is where the *fixtures* are given the chance to tempt someone
// into saying them, and does not.
//
// **Where a figure is asserted exactly.** Only where it is the evidence: +6 dB of gain is
// 20·log₁₀(2) LU, and the cell rule's boundary is arithmetic on two published resolutions. Everywhere
// else the assertion is a relation between two observed values, so a fixture that drifts fails loudly
// instead of being re-pinned to whatever it now produces.
@MainActor
@Suite("Feature — the ten measurement pairs, measured through production")
struct MeasurementComparisonPairsTests {

    /// One second of a band-limited comb, mono, at 48 kHz in float — the vocabulary group 6 of
    /// `add-significant-bandwidth-measurement` established, reused so the evidence is comparable.
    /// A second is long enough for several gating blocks, so an absent loudness would mean the wiring.
    private func programme(
        _ name: String, _ signal: AudioFixtureSignal,
        rate: Double = 48_000, channels: AVAudioChannelCount = 1, seconds: Double = 1
    ) -> AudioFixtureSpec {
        productionSpec(
            name, signal, rate: rate, channels: channels, frames: AVAudioFrameCount(rate * seconds)
        )
    }

    /// The two readings a bandwidth comparison classified, or a recorded failure.
    private func readings(
        _ comparison: BandwidthReadingComparison, _ what: Comment
    ) throws -> (first: SignificantBandwidth.Channel, second: SignificantBandwidth.Channel) {
        try #require(comparison.readings, "\(what): nothing was compared — \(comparison)")
    }

    // MARK: - Pair 1 — identical files

    /// **Exact equality is reachable through production**, which is what licenses `same` as a case at
    /// all. Two files written from one specification measure identically, byte for byte in every
    /// figure, and the comparison says so without a tolerance anywhere.
    ///
    /// The two files are the **same container** deliberately. Whether two containers holding the same
    /// audio measure identically is a different question with a different answer, and it is asked in
    /// `MeasurementComparisonProductionReachTests` rather than smuggled in here.
    @Test("pair 1 — two files of the same signal compare equal in every figure")
    func identicalFiles() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("identical-a", signal), programme("identical-b", signal), in: directory
            )
            let c = pair.comparison

            #expect(c.gaps.isEmpty, "an identical pair reported \(c.gaps)")
            guard case .same = c.signalLevels.overall.peakSample, case .same = c.signalLevels.overall.rms,
                  case .same = c.signalLevels.overall.dcOffset,
                  case .same = c.signalLevels.overall.clippedSampleCount
            else { Issue.record("a level figure differed between identical files: \(c.signalLevels.overall)"); return }
            guard case .same = c.truePeak.overall else {
                Issue.record("true peak differed between identical files: \(c.truePeak.overall)"); return
            }
            guard case .same = c.loudness else {
                Issue.record("loudness differed between identical files: \(c.loudness)"); return
            }
            // Bandwidth has no `same`: two equal readings are `indistinguishable` carrying equal
            // payloads, which is where exact equality shows for this metric.
            guard case let .indistinguishable(first, second) = c.programmeBandwidth.overall else {
                Issue.record("identical bandwidth readings were separated: \(c.programmeBandwidth.overall.evidence)")
                return
            }
            #expect(first == second, "two identical files read \(first) and \(second)")

            // Per channel, and not merely overall.
            guard case let .byIndex(levels) = c.signalLevels.channels,
                  case let .byIndex(peaks) = c.truePeak.channels,
                  case let .byIndex(bands) = c.programmeBandwidth.channels
            else { Issue.record("channels were not compared by index for an identical pair"); return }
            #expect(levels.count == 1 && peaks.count == 1 && bands.count == 1)
            for peak in peaks {
                guard case .same = peak else { Issue.record("a channel's true peak differed: \(peak)"); return }
            }
        }
    }

    // MARK: - Pair 2 — the same signal, 6 dB apart

    /// **Gain moves the levels and the loudness, and leaves the spectral extent where it was.**
    ///
    /// The loudness difference is the one figure asserted against a published number rather than
    /// against the other side: doubling every sample is exactly 20·log₁₀(2) = 6.0206 LU, and a
    /// measurement that does not reproduce it is wrong regardless of what the fixture did.
    ///
    /// **Nothing here says the second file is louder in any sense a listener would mean**, and nothing
    /// says it is more compressed, a remaster or worth more. It says the programme loudness of the
    /// second is 6.0206 LU above the first, which is arithmetic on two measured numbers.
    @Test("pair 2 — doubling every sample moves loudness by 20·log₁₀(2) LU and leaves bandwidth where it was")
    func gainOnly() async throws {
        try await withTemporaryDirectory { directory in
            let pair = try await MeasurementProduction.pair(
                programme("gain-a", productionProgramme(to: 16_000, level: 0.01)),
                programme("gain-b", productionProgramme(to: 16_000, level: 0.02)),
                in: directory
            )
            let c = pair.comparison
            #expect(c.gaps.isEmpty, "a gain-only pair reported \(c.gaps)")

            // Levels and true peak move, and neither publishes a difference — the stored values are
            // linear amplitudes, so a difference would be a ratio (ADR-0017 §3, ADR-0024 §6).
            guard case let .different(firstPeak, secondPeak) = c.signalLevels.overall.peakSample,
                  case .different = c.signalLevels.overall.rms,
                  case let .different(firstTrue, secondTrue) = c.truePeak.overall
            else {
                Issue.record("""
                a gain change left a level unchanged — peak \(c.signalLevels.overall.peakSample), \
                rms \(c.signalLevels.overall.rms), true peak \(c.truePeak.overall)
                """)
                return
            }
            #expect(secondPeak > firstPeak); #expect(secondTrue > firstTrue)

            guard case let .different(_, _, difference) = c.loudness else {
                Issue.record("a 6 dB gain change did not move the loudness: \(c.loudness)"); return
            }
            let sixDecibels = 20 * log10(2.0)
            #expect(
                abs(difference - sixDecibels) < 0.001,
                "doubling every sample moved the loudness by \(difference) LU, not \(sixDecibels)"
            )

            // Bandwidth is a statement about where content is, not about how loud it is: the threshold
            // is relative to the window's own peak, so a uniform gain cancels out of it entirely.
            let (a, b) = try readings(c.programmeBandwidth.overall, "pair 2 bandwidth")
            #expect(a == b, "a uniform gain moved the bandwidth reading: \(c.programmeBandwidth.overall.evidence)")
            guard case .indistinguishable = c.programmeBandwidth.overall else {
                Issue.record("gain separated two bandwidth readings: \(c.programmeBandwidth.overall.evidence)")
                return
            }
        }
    }

    // MARK: - Pair 3 — the same bandwidth, a different loudness

    /// **The two are independent, and this is the half that shows loudness moving alone.**
    ///
    /// The second file interleaves a second comb between the first's components: twice the energy at
    /// the *same* per-bin level and with the *same* top component, so the loudness rises while the
    /// spectral extent does not move by even one bin. Adding a loud low tone would have done the first
    /// job and quietly failed the second — it raises each window's own peak, which is what the
    /// significance threshold is relative to, and the reading drops two bins. That was measured, not
    /// guessed, which is why the fixture is built this way.
    @Test("pair 3 — loudness moves while the bandwidth reading does not")
    func loudnessAloneMoves() async throws {
        try await withTemporaryDirectory { directory in
            let comb = productionProgramme(to: 16_000, level: 0.01)
            let interleaved = AudioFixtureSignal.tones(
                highest: 15_750, spacing: 500, lowest: 750, perComponentAmplitude: 0.01
            )
            let pair = try await MeasurementProduction.pair(
                programme("bandsame-a", comb),
                programme("bandsame-b", .sum([comb, interleaved])),
                in: directory
            )
            let c = pair.comparison
            #expect(c.gaps.isEmpty, "pair 3 reported \(c.gaps)")

            guard case let .different(_, _, difference) = c.loudness else {
                Issue.record("pair 3's two files measured the same loudness: \(c.loudness)"); return
            }
            #expect(abs(difference) > 1, "pair 3 moved the loudness by only \(difference) LU")

            let (a, b) = try readings(c.programmeBandwidth.overall, "pair 3 bandwidth")
            #expect(
                a == b,
                "a loudness-only change moved the reading: \(c.programmeBandwidth.overall.evidence)"
            )
            guard case .indistinguishable = c.programmeBandwidth.overall else {
                Issue.record("pair 3 separated two bandwidth readings: \(c.programmeBandwidth.overall.evidence)")
                return
            }
        }
    }

    // MARK: - Pair 4 — the same loudness, a different bandwidth

    /// **The converse, and the one that needed no normalisation to reach.**
    ///
    /// The second file is the first plus a 12.5–16 kHz band 30 dB below the programme's per-component
    /// level. That is loud enough to clear the significance threshold — group 6 of the bandwidth change
    /// measured a band at −40 dB still being kept — and quiet enough that it contributes a part in
    /// 10⁻³ of the energy, so the loudness stays put. Adjusting a gain to match two loudnesses would
    /// have worked too; not needing to is better, because the fixture then states its own equivalence
    /// instead of inheriting it from a measurement.
    ///
    /// The loudness is `different` rather than `same` and that is honest: the two numbers are not
    /// equal, they are equal to a thousandth of a LU. **This test asserts what was observed** and does
    /// not round two measurements together to make a nicer word appear.
    @Test("pair 4 — the bandwidth separates while the loudness stays within a thousandth of a LU")
    func bandwidthAloneMoves() async throws {
        try await withTemporaryDirectory { directory in
            let comb = productionProgramme(to: 12_000, level: 0.01)
            let highBand = AudioFixtureSignal.tones(
                highest: 16_000, spacing: 500, lowest: 12_500,
                perComponentAmplitude: 0.01 * Float(pow(10.0, -30.0 / 20))
            )
            let pair = try await MeasurementProduction.pair(
                programme("loudsame-a", comb),
                programme("loudsame-b", .sum([comb, highBand])),
                in: directory
            )
            let c = pair.comparison
            #expect(c.gaps.isEmpty, "pair 4 reported \(c.gaps)")

            guard case let .different(_, _, difference) = c.loudness else {
                Issue.record("pair 4's two files measured exactly the same loudness: \(c.loudness)"); return
            }
            #expect(
                abs(difference) < 0.01,
                "the added band was meant to be inaudible to the loudness and moved it \(difference) LU"
            )

            let (a, b) = try readings(c.programmeBandwidth.overall, "pair 4 bandwidth")
            guard case .separated = c.programmeBandwidth.overall else {
                Issue.record("pair 4 did not separate: \(c.programmeBandwidth.overall.evidence)"); return
            }
            #expect(b.frequency > a.frequency, "the wider file read lower: \(a.frequency) → \(b.frequency)")
        }
    }

    // MARK: - Pair 5 — a different true peak over an identical sample peak

    /// **True peak is its own fact, and this is the pair that proves the comparison is not reading the
    /// stored samples twice.**
    ///
    /// Both files hold one 0.5 sample; the second holds a second one immediately after it. The stored
    /// maximum is therefore **exactly** 0.5 in both — `same(0.5)`, no tolerance — while the waveform
    /// reconstructed between two adjacent samples rises well above either of them. A comparison that
    /// compared true peak by its samples would report these two files as equal.
    ///
    /// Nothing here is a statement about either file's headroom, mastering or fitness for anything.
    @Test("pair 5 — the sample peak is identical and the true peak is not")
    func truePeakIsItsOwnFact() async throws {
        try await withTemporaryDirectory { directory in
            let pair = try await MeasurementProduction.pair(
                programme("truepeak-a", .impulse(amplitude: 0.5, frameIndex: 10_000), seconds: 0.5),
                programme("truepeak-b", .sum([
                    .impulse(amplitude: 0.5, frameIndex: 10_000),
                    .impulse(amplitude: 0.5, frameIndex: 10_001),
                ]), seconds: 0.5),
                in: directory
            )
            let c = pair.comparison

            guard case let .same(storedPeak) = c.signalLevels.overall.peakSample else {
                Issue.record("the two files' stored peaks differed: \(c.signalLevels.overall.peakSample)"); return
            }
            #expect(storedPeak == 0.5)

            guard case let .different(firstTrue, secondTrue) = c.truePeak.overall else {
                Issue.record("""
                two files with the same stored peak reported the same true peak: \(c.truePeak.overall) — \
                the comparison is reading the samples rather than the reconstruction
                """)
                return
            }
            #expect(secondTrue > firstTrue)
            #expect(firstTrue == storedPeak, "an isolated sample reconstructed to \(firstTrue), not its own height")
            #expect(secondTrue > storedPeak, "the second file's reconstruction never left its samples")
        }
    }

    // MARK: - Pair 6 — a different channel count

    /// **`countsDiffer`, never an intersection.**
    ///
    /// Comparing the mono file's only channel against the stereo file's first would assert that index 0
    /// means the same thing in both, which is precisely the layout claim the pipeline refuses to make:
    /// it reads channel counts and never labels. The overall figures still compare, because each is a
    /// summary over whatever channels the file had.
    ///
    /// A channel-count mismatch is **not** a method incompatibility, and the two must not be confused:
    /// no gap of any kind is reported here — `countsDiffer` is a case of its own carrying the two
    /// counts, and it says a comparison was not attempted rather than that one was refused.
    @Test("pair 6 — differing channel counts are reported, never intersected")
    func channelCountsDiffer() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("chan-mono", signal, channels: 1),
                programme("chan-stereo", signal, channels: 2),
                in: directory
            )
            let c = pair.comparison

            let mismatches = [
                ("signal levels", c.signalLevels.channels.differingCounts),
                ("true peak", c.truePeak.channels.differingCounts),
                ("bandwidth", c.programmeBandwidth.channels.differingCounts),
            ]
            for (metric, counts) in mismatches {
                guard let counts else {
                    Issue.record("\(metric) did not report the channel mismatch"); return
                }
                #expect(counts == (1, 2), "\(metric) reported \(counts)")
            }

            // No index was compared, and nothing was called incomparable either.
            #expect(c.gaps.isEmpty, "a channel-count mismatch was reported as a gap: \(c.gaps)")

            // The overall figures still compare, on their own terms.
            guard case .different = c.loudness else {
                Issue.record("the overall loudness stopped comparing over a channel mismatch: \(c.loudness)"); return
            }
            let (a, b) = try readings(c.programmeBandwidth.overall, "pair 6 overall bandwidth")
            #expect(a == b, "the overall bandwidth readings differed: \(c.programmeBandwidth.overall.evidence)")
        }
    }

    // MARK: - Pair 7 — two rates, two weightings, one comparison

    /// **Task 5.3.** BS.1770-5 publishes K-weighting coefficients for 48 kHz alone, so the same content
    /// at 44.1 kHz runs a rediscretised prototype instead and the two measurements carry **different**
    /// weighting identities. A naive `first.method == second.method` gate would refuse to compare them.
    ///
    /// The rule admits exactly this pair and only because it was measured: `LoudnessProductionMatrixTests`
    /// reads one signal at five rates through this same path and requires the spread within 0.03 LU.
    ///
    /// **The weightings are read from what actually ran**, never assumed from the rates: a production
    /// change that made both sides publish the same identity would make this test vacuous, so it fails
    /// rather than passes if the two ever coincide.
    @Test("pair 7 — the same content at two rates compares across two weightings")
    func crossWeightingLoudness() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("rate-44100", signal, rate: 44_100),
                programme("rate-48000", signal, rate: 48_000),
                in: directory
            )
            let first = try #require(pair.first.loudness, "44.1 kHz produced no loudness")
            let second = try #require(pair.second.loudness, "48 kHz produced no loudness")

            #expect(
                first.method.weighting != second.method.weighting,
                """
                both rates ran the same weighting (\(first.method.weighting.rawValue)) — this pair no \
                longer crosses the equivalence the rule admits, and proves nothing about it
                """
            )
            #expect(first.method.algorithm == second.method.algorithm)

            guard case let .different(_, _, difference) = pair.comparison.loudness else {
                Issue.record("""
                loudness did not compare across the two weightings: \(pair.comparison.loudness) — \
                \(first.method.weighting.rawValue) against \(second.method.weighting.rawValue)
                """)
                return
            }
            // Not a claim about the standard: the tolerance is the one the rate-invariance evidence
            // established, and this pair sits inside it.
            #expect(abs(difference) < 0.03, "the same content at two rates differed by \(difference) LU")
        }
    }

    // MARK: - Pairs 8 and 9 — the cell rule, from both sides, on readings production produced

    /// **Task 5.2, the `indistinguishable` half.** Two rates that share a weighting, so nothing about
    /// loudness is mixed into the claim: 88.2 kHz and 96 kHz put the same 16 kHz edge in bins whose
    /// centres are **not equal** and whose cells overlap. A rule comparing hertz for equality would call
    /// this a difference; the analysis simply did not separate the two.
    ///
    /// The four published quantities and the boundary they imply are recorded in the failure message,
    /// so a regression says *which* number moved.
    @Test("pair 8 — two readings with different centres fall inside one another's cells")
    func indistinguishableAcrossTwoGrids() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("grid-88200", signal, rate: 88_200),
                programme("grid-96000", signal, rate: 96_000),
                in: directory
            )
            let comparison = pair.comparison.programmeBandwidth.overall
            let (a, b) = try readings(comparison, "pair 8")

            #expect(
                a.frequency != b.frequency,
                "the two grids produced the same centre — this pair no longer discriminates equality: \(comparison.evidence)"
            )
            #expect(
                abs(a.frequency - b.frequency) < (a.resolution + b.resolution) / 2,
                "pair 8's readings do not overlap: \(comparison.evidence)"
            )
            guard case .indistinguishable = comparison else {
                Issue.record("overlapping cells were separated: \(comparison.evidence)"); return
            }
            // The loudness claim is deliberately not part of this pair: both rates run the same
            // rediscretised weighting, so nothing here rests on the equivalence pair 7 exercises.
            let first = try #require(pair.first.loudness)
            let second = try #require(pair.second.loudness)
            #expect(first.method.weighting == second.method.weighting)
        }
    }

    /// **Task 5.2, the `separated` half — and it lands on the boundary itself.**
    ///
    /// Two edges one bin apart at one rate put the readings exactly `(r₁ + r₂)/2` = one bin apart, which
    /// is the strict inequality's own boundary. It classifies as `separated`, because the analysis
    /// resolved the two into different bins — and a rule written `<=` would call them indistinguishable.
    /// **The boundary is reachable from production**, so it is pinned here rather than only in the
    /// domain suite where it is pinned exactly.
    @Test("pair 9 — readings exactly one bin apart are separated, on the boundary itself")
    func separatedAtTheBoundary() async throws {
        try await withTemporaryDirectory { directory in
            // One bin at 48 kHz over a 2048-frame window. Written as the arithmetic rather than as
            // 16 023.4375, so a change of window length moves the fixture with the grid.
            let bin = 48_000.0 / 2_048.0
            let pair = try await MeasurementProduction.pair(
                programme("edge-lower", productionProgramme(to: 16_000)),
                programme("edge-upper", productionProgramme(to: 16_000 + bin)),
                in: directory
            )
            let comparison = pair.comparison.programmeBandwidth.overall
            let (a, b) = try readings(comparison, "pair 9")

            let separation = abs(a.frequency - b.frequency)
            let boundary = (a.resolution + b.resolution) / 2
            #expect(
                separation == boundary,
                "pair 9 was meant to land on the boundary exactly: \(comparison.evidence)"
            )
            guard case .separated = comparison else {
                Issue.record("""
                two readings a whole bin apart were called indistinguishable: \(comparison.evidence) — \
                the rule is strictly less-than, and this is the case that says so
                """)
                return
            }
        }
    }

    // MARK: - Pair 10 — a real absence on one side

    /// **An absence is not a zero, is not a `same`, and does not take the other three measurements down
    /// with it.**
    ///
    /// The second file is a tenth of a second of the same signal. BS.1770 integrated loudness needs a
    /// whole 400 ms gating block, so it has none — a real absence produced by the standard's own rule,
    /// not a failure and not something this test arranged. Everything else measures, and measures
    /// *identically*, because it is the same signal: which is what shows the bundle did not collapse.
    @Test("pair 10 — one side's loudness is absent and the other three still compare")
    func absenceOnOneSide() async throws {
        try await withTemporaryDirectory { directory in
            let signal = productionProgramme(to: 16_000)
            let pair = try await MeasurementProduction.pair(
                programme("absence-long", signal), programme("absence-short", signal, seconds: 0.1),
                in: directory
            )
            let c = pair.comparison

            #expect(pair.second.loudness == nil, "the short file measured a loudness after all")
            #expect(c.loudness.gapReason == .secondMissing, "an absent loudness became \(c.loudness)")
            // **The first file's own number survives the second file's absence**, taken from what
            // production measured rather than from a literal, so the assertion cannot drift from the
            // fixture. Without this, the surface prints "No value" under a file that has a loudness.
            let measuredFirst = try #require(pair.first.loudness).integratedLoudness
            #expect(c.loudness == .incomparable(.secondMissing(first: measuredFirst)))
            // Not a zero and not an equality: `same(0)` and `different(x, 0)` are both statements about
            // a value, and there is no value on that side.
            if case let .different(_, second, _) = c.loudness {
                Issue.record("an absence became \(second) LUFS")
            }
            if case .same = c.loudness {
                Issue.record("an absence became an equality")
            }

            // The siblings are untouched, and equal, because it is the same signal.
            guard case .same = c.signalLevels.overall.peakSample, case .same = c.signalLevels.overall.rms,
                  case .same = c.truePeak.overall
            else {
                Issue.record("""
                one absent measurement took its siblings with it — peak \
                \(c.signalLevels.overall.peakSample), rms \(c.signalLevels.overall.rms), \
                true peak \(c.truePeak.overall)
                """)
                return
            }
            let (a, b) = try readings(c.programmeBandwidth.overall, "pair 10 bandwidth")
            #expect(a == b)
            #expect(c.gaps == [.secondMissing], "pair 10 reported \(c.gaps)")
        }
    }

    /// **The other side of the same coin: a measured zero is a value.**
    ///
    /// Digital silence has no programme loudness and no bandwidth reading — both genuinely absent — and
    /// a true peak and a sample peak of **exactly 0.0**, which are measurements. The comparison keeps
    /// the two apart: the absences are gaps, and the zeros are `different(x, 0.0)`.
    @Test("pair 10 — a measured zero and an absence are not the same answer")
    func silenceKeepsZeroApartFromAbsence() async throws {
        try await withTemporaryDirectory { directory in
            let pair = try await MeasurementProduction.pair(
                programme("silence-against", productionProgramme(to: 16_000)),
                programme("silence", .silence),
                in: directory
            )
            let c = pair.comparison

            #expect(c.loudness.gapReason == .secondMissing)
            #expect(c.programmeBandwidth.overall.gapReason == .secondMissing)
            // Silence has neither, and the programme file has both — so both gaps keep the first file's.
            let measuredLoudness = try #require(pair.first.loudness).integratedLoudness
            let measuredBandwidth = try #require(pair.first.bandwidth)
            let measuredReading = try #require(measuredBandwidth.overall)
            #expect(c.loudness == .incomparable(.secondMissing(first: measuredLoudness)))
            #expect(c.programmeBandwidth.overall == .incomparable(.secondMissing(first: measuredReading)))

            guard case let .different(_, silentTrue) = c.truePeak.overall,
                  case let .different(_, silentPeak) = c.signalLevels.overall.peakSample
            else {
                Issue.record("""
                silence's measured zeros were not compared as values — true peak \(c.truePeak.overall), \
                peak \(c.signalLevels.overall.peakSample)
                """)
                return
            }
            #expect(silentTrue == 0); #expect(silentPeak == 0)
        }
    }
}
