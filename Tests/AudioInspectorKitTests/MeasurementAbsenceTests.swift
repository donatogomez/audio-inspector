import Testing

import AudioInspectorDomain

// **The surviving value, and where it used to be dropped.**
//
// A comparison whose two sides cannot be compared still knows something: *which* side had a value, and
// **what it was**. The first shape of `MeasurementGap` carried only the reason, so a pair where the
// first file measured −24.9 LUFS and the second measured nothing reached the surface as
// `No value | No value` — a true sentence about the second file printed twice, the second time about a
// file it was false of.
//
// These tests are written against the **domain** rather than the surface on purpose. The formatter
// cannot show a number the comparison never handed it, so a fix that started there would have to fetch
// the value from somewhere else — a second bundle travelling beside the comparison — and that is
// exactly the atomicity `MeasurementComparisonAtomicityTests` exists to protect. The information has to
// survive *inside* the comparison or the surface has no honest way to show it.
@Suite("Domain — what an incomparable measurement still knows")
struct MeasurementAbsenceTests {

    // MARK: Building one side at a time

    private func levels(peak: Float, rms: Float = 0.2) throws -> SignalLevelMetrics {
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 100, peakSample: peak, rms: rms, dcOffset: 0, clippedSampleCount: 0
        ))
        return try #require(SignalLevelMetrics(
            channels: [channel], overallPeakSample: peak, overallRMS: rms,
            overallDCOffset: 0, overallClippedSampleCount: 0
        ))
    }

    private func truePeak(_ value: Float, factor: Int = 8) throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: factor, filter: .polyphaseFIRv1))
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 100, truePeak: value))
        return try #require(TruePeakMeasurement(channels: [channel], method: method))
    }

    private func loudness(
        _ lufs: Double, algorithm: LoudnessAlgorithmIdentifier = .integratedBS1770v1
    ) throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: algorithm, weighting: .publishedAt48kHz)
        ))
    }

    private func bandwidth(
        _ hertz: Double, identifier: String = SignificantBandwidthMethod.v1
    ) throws -> SignificantBandwidth {
        let method = try #require(SignificantBandwidthMethod(
            identifier: identifier, windowFrames: 2_048, hopFrames: 512, sampleRate: 48_000
        ))
        let reading = try #require(SignificantBandwidth.Channel(frequency: hertz, resolution: 23.4375))
        return try #require(SignificantBandwidth(channels: [reading], method: method))
    }

    private func bundle(
        levels: SignalLevelMetrics? = nil, truePeak: TruePeakMeasurement? = nil,
        loudness: LoudnessMeasurement? = nil, bandwidth: SignificantBandwidth? = nil
    ) -> ReportMeasurements {
        ReportMeasurements(
            signalLevelMetrics: levels, truePeak: truePeak, loudness: loudness, programmeBandwidth: bandwidth
        )
    }

    // MARK: The asymmetric absence, on every metric

    /// **The first file measured and the second did not.** The comparison must still carry the first
    /// file's number: it exists, it is on screen for that file in its own report section, and a surface
    /// that printed `No value` for it would be stating something false about a file that has a value.
    @Test("a second-missing gap keeps the first file's value, on every metric")
    func secondMissingKeepsTheFirstValue() throws {
        let first = bundle(
            levels: try levels(peak: 0.5), truePeak: try truePeak(0.9),
            loudness: try loudness(-24.9), bandwidth: try bandwidth(16_101.5625)
        )
        let comparison = MeasurementComparison(first: first, second: bundle())

        guard case let .incomparable(levelGap) = comparison.signalLevels.overall.peakSample else {
            Issue.record("peak sample: \(comparison.signalLevels.overall.peakSample)"); return
        }
        #expect(levelGap.reason == .secondMissing)
        #expect(levelGap.first == 0.5, "the first file's peak was dropped")
        #expect(levelGap.second == nil)

        guard case let .incomparable(peakGap) = comparison.truePeak.overall else {
            Issue.record("true peak: \(comparison.truePeak.overall)"); return
        }
        #expect(peakGap.reason == .secondMissing)
        #expect(peakGap.first == 0.9, "the first file's true peak was dropped")

        guard case let .incomparable(loudnessGap) = comparison.loudness else {
            Issue.record("loudness: \(comparison.loudness)"); return
        }
        #expect(loudnessGap.reason == .secondMissing)
        #expect(loudnessGap.first == -24.9, "the first file's loudness was dropped — this is the bug")
        #expect(loudnessGap.second == nil)

        guard case let .incomparable(bandwidthGap) = comparison.programmeBandwidth.overall else {
            Issue.record("bandwidth: \(comparison.programmeBandwidth.overall)"); return
        }
        #expect(bandwidthGap.reason == .secondMissing)
        #expect(bandwidthGap.first?.frequency == 16_101.5625, "the first file's reading was dropped")
    }

    /// The mirror image, so nothing about the rule is positional.
    @Test("a first-missing gap keeps the second file's value, on every metric")
    func firstMissingKeepsTheSecondValue() throws {
        let second = bundle(
            levels: try levels(peak: 0.5), truePeak: try truePeak(0.9),
            loudness: try loudness(-24.9), bandwidth: try bandwidth(16_101.5625)
        )
        let comparison = MeasurementComparison(first: bundle(), second: second)

        guard case let .incomparable(loudnessGap) = comparison.loudness else {
            Issue.record("loudness: \(comparison.loudness)"); return
        }
        #expect(loudnessGap.reason == .firstMissing)
        #expect(loudnessGap.first == nil)
        #expect(loudnessGap.second == -24.9, "the second file's loudness was dropped")

        guard case let .incomparable(peakGap) = comparison.truePeak.overall else {
            Issue.record("true peak: \(comparison.truePeak.overall)"); return
        }
        #expect(peakGap.reason == .firstMissing)
        #expect(peakGap.second == 0.9)

        guard case let .incomparable(bandwidthGap) = comparison.programmeBandwidth.overall else {
            Issue.record("bandwidth: \(comparison.programmeBandwidth.overall)"); return
        }
        #expect(bandwidthGap.reason == .firstMissing)
        #expect(bandwidthGap.second?.frequency == 16_101.5625)
    }

    /// **Neither side has anything, and nothing is invented.** This is the one gap that legitimately
    /// carries no value, and it must stay that way: a zero here would manufacture a measurement.
    @Test("neither-present carries no value at all, and never a zero")
    func neitherPresentCarriesNothing() throws {
        let comparison = MeasurementComparison(first: bundle(), second: bundle())

        guard case let .incomparable(loudnessGap) = comparison.loudness,
              case let .incomparable(peakGap) = comparison.truePeak.overall,
              case let .incomparable(levelGap) = comparison.signalLevels.overall.rms,
              case let .incomparable(bandwidthGap) = comparison.programmeBandwidth.overall
        else { Issue.record("an empty pair compared something"); return }

        #expect(loudnessGap.reason == .neitherPresent)
        #expect(loudnessGap.first == nil && loudnessGap.second == nil)
        #expect(peakGap.first == nil && peakGap.second == nil)
        #expect(levelGap.first == nil && levelGap.second == nil)
        #expect(bandwidthGap.first == nil && bandwidthGap.second == nil)
    }

    // MARK: Methods that differ — both sides measured, and both values survive

    /// **The one gap that occurs while both sides have a value**, so it is the one that must carry both.
    ///
    /// Not reachable from production today — one true peak method, one bandwidth identity, one loudness
    /// algorithm — which is why it is pinned here, where the measurements can be built. A surface that
    /// showed `No value | No value` for it would be hiding two numbers it was handed, and telling a
    /// reader the files measured nothing when what actually happened is that the two numbers are not on
    /// one scale.
    @Test("a method mismatch keeps both values")
    func methodsDifferKeepsBothValues() throws {
        let first = bundle(
            truePeak: try truePeak(0.9, factor: 8),
            loudness: try loudness(-24.9),
            bandwidth: try bandwidth(16_101.5625)
        )
        let second = bundle(
            truePeak: try truePeak(0.5, factor: 4),
            loudness: try loudness(-18.9, algorithm: LoudnessAlgorithmIdentifier(rawValue: "other_v1")),
            bandwidth: try bandwidth(20_000, identifier: "other-v1")
        )
        let comparison = MeasurementComparison(first: first, second: second)

        guard case let .incomparable(peakGap) = comparison.truePeak.overall else {
            Issue.record("true peak: \(comparison.truePeak.overall)"); return
        }
        #expect(peakGap.reason == .methodsDiffer)
        #expect(peakGap.first == 0.9 && peakGap.second == 0.5, "an incompatible method dropped both values")

        guard case let .incomparable(loudnessGap) = comparison.loudness else {
            Issue.record("loudness: \(comparison.loudness)"); return
        }
        #expect(loudnessGap.reason == .methodsDiffer)
        #expect(loudnessGap.first == -24.9 && loudnessGap.second == -18.9)

        guard case let .incomparable(bandwidthGap) = comparison.programmeBandwidth.overall else {
            Issue.record("bandwidth: \(comparison.programmeBandwidth.overall)"); return
        }
        #expect(bandwidthGap.reason == .methodsDiffer)
        #expect(bandwidthGap.first?.frequency == 16_101.5625)
        #expect(bandwidthGap.second?.frequency == 20_000)
    }

    /// **Keeping the values does not make them comparable.** Two identical numbers produced by
    /// incompatible methods are still `incomparable`, and the gap is still `methodsDiffer` — carrying
    /// them is a statement about what was measured, never about whether they agree.
    @Test("carrying both values never turns a method mismatch into an equality")
    func carryingValuesDoesNotRescueTheMethod() throws {
        let comparison = MeasurementComparison(
            first: bundle(truePeak: try truePeak(0.9, factor: 8)),
            second: bundle(truePeak: try truePeak(0.9, factor: 4))
        )
        guard case let .incomparable(gap) = comparison.truePeak.overall else {
            Issue.record("identical values rescued an incompatible method: \(comparison.truePeak.overall)")
            return
        }
        #expect(gap.reason == .methodsDiffer)
        #expect(gap.first == gap.second)
    }

    // MARK: The shape itself

    /// **Each gap carries exactly what exists and no more**, which is what makes a contradictory state
    /// unrepresentable rather than merely untested: `secondMissing` has no field a second value could go
    /// in, and `neitherPresent` has none at all.
    ///
    /// `methodsDiffer` is the exception and is the only one whose payloads are optional — deliberately,
    /// because it is a statement about the two *methodologies* and says nothing about presence, so it
    /// cannot contradict itself whatever it carries.
    @Test("the gap's shape makes a contradictory state unrepresentable")
    func theShapeCannotContradictItself() throws {
        let gap = MeasurementGap<Float>.secondMissing(first: 0.5)
        #expect(gap.first == 0.5)
        #expect(gap.second == nil)
        #expect(MeasurementGap<Float>.firstMissing(second: 0.5).first == nil)
        #expect(MeasurementGap<Float>.neitherPresent.first == nil)
        #expect(MeasurementGap<Float>.neitherPresent.second == nil)
        // A reason alone, for the places that have no value to carry.
        #expect(gap.reason == .secondMissing)
    }
}
