import Testing

@testable import AudioInspectorDomain

// Tasks 1.2, 1.4 and 1.5 of `add-two-file-measurement-comparison`: the semantics ADR-0024 decided,
// turned into the matrix that pins them.
//
// Pure domain. No file, no decoder, no flow, no surface — the comparator is synchronous, total and
// deterministic, and these tests are the evidence that it is.

@Suite("Domain — comparing two files' measurements")
struct MeasurementComparisonTests {

    // MARK: Fixtures

    private func levels(
        peak: Float = 0.5, rms: Float = 0.25, dc: Float = 0.001, clipped: Int = 0, channels: Int = 2
    ) throws -> SignalLevelMetrics {
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 44_100, peakSample: peak, rms: rms, dcOffset: dc, clippedSampleCount: clipped
        ))
        return try #require(SignalLevelMetrics(
            channels: Array(repeating: channel, count: channels),
            overallPeakSample: peak, overallRMS: rms, overallDCOffset: dc, overallClippedSampleCount: clipped
        ))
    }

    private func truePeak(
        _ peak: Float = 0.9, oversampling: Int = 8,
        filter: TruePeakFilterIdentifier = .polyphaseFIRv1, channels: Int = 2
    ) throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: oversampling, filter: filter))
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 44_100, truePeak: peak))
        return try #require(TruePeakMeasurement(
            channels: Array(repeating: channel, count: channels), method: method
        ))
    }

    private func loudness(
        _ lufs: Double, algorithm: LoudnessAlgorithmIdentifier = .integratedBS1770v1,
        weighting: LoudnessWeightingIdentifier = .publishedAt48kHz
    ) throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: lufs, method: LoudnessMethod(algorithm: algorithm, weighting: weighting)
        ))
    }

    private func bandwidth(
        _ frequencies: [Double?], resolution: Double = 23.4375,
        identifier: String = SignificantBandwidthMethod.v1, windowFrames: Int = 2_048, rate: Double = 48_000
    ) throws -> SignificantBandwidth {
        let method = try #require(SignificantBandwidthMethod(
            identifier: identifier, windowFrames: windowFrames, hopFrames: windowFrames / 4, sampleRate: rate
        ))
        let channels: [SignificantBandwidth.Channel?] = try frequencies.map { f in
            guard let f else { return nil }
            return try #require(SignificantBandwidth.Channel(frequency: f, resolution: resolution))
        }
        return try #require(SignificantBandwidth(channels: channels, method: method))
    }

    private func bundle(
        levels: SignalLevelMetrics? = nil, truePeak: TruePeakMeasurement? = nil,
        loudness: LoudnessMeasurement? = nil, bandwidth: SignificantBandwidth? = nil
    ) -> ReportMeasurements {
        ReportMeasurements(
            signalLevelMetrics: levels, truePeak: truePeak, loudness: loudness, programmeBandwidth: bandwidth
        )
    }

    private func compare(_ a: ReportMeasurements, _ b: ReportMeasurements) -> MeasurementComparison {
        MeasurementComparison(first: a, second: b)
    }

    // MARK: 1.2 — the method compatibility matrix

    /// **Signal levels carry no method**, so nothing gates them: a direct reduction over stored samples
    /// has no methodology to disagree about.
    @Test func signalLevelsCompareWheneverBothExist() throws {
        let c = compare(bundle(levels: try levels(peak: 0.5)), bundle(levels: try levels(peak: 0.5)))
        #expect(c.signalLevels.overall.peakSample == .same(0.5))
        #expect(c.signalLevels.overall.rms == .same(0.25))
    }

    /// **True peak needs both fields.** An oversampling factor is not a provenance detail; it materially
    /// changes the estimate, and no equivalence between two factors has been measured.
    @Test("true peak requires the same oversampling factor and the same filter",
          arguments: [(8, 4, "oversampling"), (8, 8, "filter")])
    func truePeakMethodGate(firstFactor: Int, secondFactor: Int, which: String) throws {
        let other: TruePeakFilterIdentifier = which == "filter"
            ? TruePeakFilterIdentifier(rawValue: "some_other_filter_v1") : .polyphaseFIRv1
        let a = try truePeak(0.9, oversampling: firstFactor)
        let b = try truePeak(0.9, oversampling: secondFactor, filter: other)
        let c = compare(bundle(truePeak: a), bundle(truePeak: b))
        #expect(c.truePeak.overall == .incomparable(.methodsDiffer), "\(which) was ignored")
        #expect(c.truePeak.channels == .incomparable(.methodsDiffer))
    }

    /// **Identical values do not rescue an incompatible method.** Two numbers on different scales that
    /// happen to coincide are not a comparison.
    @Test func identicalValuesDoNotOverrideAnIncompatibleMethod() throws {
        let c = compare(
            bundle(truePeak: try truePeak(0.9, oversampling: 8)),
            bundle(truePeak: try truePeak(0.9, oversampling: 4))
        )
        #expect(c.truePeak.overall == .incomparable(.methodsDiffer))
    }

    /// **1.3, applied.** The two weightings compare because `LoudnessProductionMatrixTests` reads one
    /// signal at all five rates through production and holds the spread inside 0.03 LU; 48 kHz runs the
    /// published tables and the other four the rediscretised prototype, so that test crosses exactly
    /// this pair.
    @Test func loudnessComparesAcrossTheTwoDemonstratedWeightings() throws {
        let c = compare(
            bundle(loudness: try loudness(-14.0, weighting: .publishedAt48kHz)),
            bundle(loudness: try loudness(-9.3, weighting: .derivedFrom48kHz))
        )
        guard case let .different(first, second, difference) = c.loudness else {
            Issue.record("the demonstrated weighting pair was refused: \(c.loudness)"); return
        }
        #expect(first == -14.0 && second == -9.3)
        #expect(difference == 4.7000000000000011 || abs(difference - 4.7) < 1e-12)
    }

    /// **An undemonstrated weighting is incomparable until someone measures it** — the allow-list is an
    /// explicit pair check, not "ignore the weighting".
    @Test func anUnknownWeightingIsNotComparable() throws {
        let unknown = LoudnessWeightingIdentifier(rawValue: "some_future_weighting_v1")
        let c = compare(
            bundle(loudness: try loudness(-14.0, weighting: .publishedAt48kHz)),
            bundle(loudness: try loudness(-14.0, weighting: unknown))
        )
        #expect(c.loudness == .incomparable(.methodsDiffer))
    }

    @Test func adifferentLoudnessAlgorithmIsNotComparable() throws {
        let other = LoudnessAlgorithmIdentifier(rawValue: "some_other_algorithm_v1")
        let c = compare(
            bundle(loudness: try loudness(-14.0)),
            bundle(loudness: try loudness(-14.0, algorithm: other))
        )
        #expect(c.loudness == .incomparable(.methodsDiffer))
    }

    /// **Bandwidth is gated on the identifier alone.** The window geometry beside it varies by design
    /// across rates, the window being fixed in time, and the differing grids are absorbed by the cell
    /// rule rather than by refusing to compare.
    @Test func bandwidthIsGatedOnTheIdentifierAndNotOnTheGeometry() throws {
        let sameIdentity = compare(
            bundle(bandwidth: try bandwidth([16_000], resolution: 22.96875, windowFrames: 1_920, rate: 44_100)),
            bundle(bandwidth: try bandwidth([16_000], resolution: 23.4375, windowFrames: 2_048, rate: 48_000))
        )
        #expect(sameIdentity.programmeBandwidth.overall != .incomparable(.methodsDiffer),
                "differing geometry was mistaken for a differing method")

        let otherIdentity = compare(
            bundle(bandwidth: try bandwidth([16_000])),
            bundle(bandwidth: try bandwidth([16_000], identifier: "programme-bandwidth-experimental-v9"))
        )
        #expect(otherIdentity.programmeBandwidth.overall == .incomparable(.methodsDiffer))
    }

    // MARK: 1.4 — the cell rule, both sides of it

    /// `| f₁ − f₂ | < ( r₁ + r₂ ) / 2`, pinned at every point that matters. The boundary itself is
    /// **separated**, because the rule is a strict inequality.
    @Test(
        "the cell rule, at and around its boundary",
        arguments: [
            (16_000.0, 16_000.0, 23.4375, 23.4375, true, "the same reading"),
            (16_000.0, 16_010.0, 23.4375, 23.4375, true, "well inside one another's cells"),
            (16_000.0, 16_023.4374, 23.4375, 23.4375, true, "just below the boundary"),
            (16_000.0, 16_023.4375, 23.4375, 23.4375, false, "exactly on the boundary — strict `<`"),
            (16_000.0, 16_023.4376, 23.4375, 23.4375, false, "just above the boundary"),
            (16_000.0, 16_046.8750, 23.4375, 23.4375, false, "two bins apart"),
            (21_800.0, 21_850.0, 94.0, 94.0, true, "50 Hz apart on a 94 Hz grid"),
            (21_800.0, 21_850.0, 23.4375, 23.4375, false, "the same 50 Hz on a 23 Hz grid"),
        ]
    )
    func theCellRule(
        first: Double, second: Double, firstResolution: Double, secondResolution: Double,
        expectIndistinguishable: Bool, what: String
    ) throws {
        let a = try bandwidth([first], resolution: firstResolution)
        let b = try bandwidth([second], resolution: secondResolution)
        let outcome = compare(bundle(bandwidth: a), bundle(bandwidth: b)).programmeBandwidth.overall
        switch outcome {
        case .indistinguishable:
            #expect(expectIndistinguishable, "\(what): expected separated, got indistinguishable")
        case .separated:
            #expect(!expectIndistinguishable, "\(what): expected indistinguishable, got separated")
        case let .incomparable(gap):
            Issue.record("\(what): nothing was compared — \(gap)")
        }
    }

    /// Adjacent bins on one grid are **separated**: the method resolved them into different bins.
    @Test func adjacentBinsAreSeparated() throws {
        let r = 23.4375
        let c = compare(
            bundle(bandwidth: try bandwidth([16_000], resolution: r)),
            bundle(bandwidth: try bandwidth([16_000 + r], resolution: r))
        )
        #expect({ if case .separated = c.programmeBandwidth.overall { true } else { false } }())
    }

    /// Two different grids use **each reading's own resolution**, and neither is converted or preferred.
    @Test func twoGridsEachUseTheirOwn() throws {
        // Half-cells sum to (94 + 23.4375)/2 = 58.72; 50 Hz apart is inside it.
        let c = compare(
            bundle(bandwidth: try bandwidth([21_800], resolution: 94)),
            bundle(bandwidth: try bandwidth([21_850], resolution: 23.4375))
        )
        #expect({ if case .indistinguishable = c.programmeBandwidth.overall { true } else { false } }())
    }

    /// The rule is symmetric: swapping the two files cannot change whether they were distinguished.
    @Test("swapping the two files never changes the classification",
          arguments: [(16_000.0, 16_010.0), (16_000.0, 16_100.0), (16_000.0, 16_023.4375)])
    func theRuleIsSymmetric(first: Double, second: Double) throws {
        let a = bundle(bandwidth: try bandwidth([first]))
        let b = bundle(bandwidth: try bandwidth([second]))
        let forward = compare(a, b).programmeBandwidth.overall
        let backward = compare(b, a).programmeBandwidth.overall
        switch (forward, backward) {
        case (.indistinguishable, .indistinguishable), (.separated, .separated): break
        default: Issue.record("asymmetric: \(forward) forward, \(backward) backward")
        }
    }

    // MARK: 1.5 — where a difference is published, and where it is not

    /// **The difference is `second − first`, in LU, and only loudness has one.**
    @Test("the loudness difference is second minus first",
          arguments: [(-14.0, -9.3, 4.7), (-9.3, -14.0, -4.7), (-14.0, -14.0, 0.0)])
    func theLoudnessDifference(first: Double, second: Double, expected: Double) throws {
        let c = compare(bundle(loudness: try loudness(first)), bundle(loudness: try loudness(second)))
        if expected == 0 {
            #expect(c.loudness == .same(first), "equal values should not publish a difference")
            return
        }
        guard case let .different(_, _, difference) = c.loudness else {
            Issue.record("expected a difference, got \(c.loudness)"); return
        }
        #expect(abs(difference - expected) < 1e-9, "difference \(difference), expected \(expected)")
    }

    @Test func noDifferenceIsPublishedWhenTheMethodIsIncompatible() throws {
        let other = LoudnessAlgorithmIdentifier(rawValue: "other_v1")
        let c = compare(
            bundle(loudness: try loudness(-14.0)), bundle(loudness: try loudness(-9.3, algorithm: other))
        )
        #expect(c.loudness == .incomparable(.methodsDiffer))
    }

    @Test func noDifferenceIsPublishedWhenASideIsMissing() throws {
        #expect(compare(bundle(loudness: try loudness(-14)), bundle()).loudness == .incomparable(.secondMissing))
        #expect(compare(bundle(), bundle(loudness: try loudness(-14))).loudness == .incomparable(.firstMissing))
        #expect(compare(bundle(), bundle()).loudness == .incomparable(.neitherPresent))
    }

    // MARK: Absence, and channels

    /// A missing measurement is never a zero, never a `same`, and never a failure.
    @Test func absenceIsNeverInvented() throws {
        let c = compare(bundle(levels: try levels(), truePeak: try truePeak(), bandwidth: try bandwidth([16_000])), bundle())
        #expect(c.signalLevels.overall.peakSample == .incomparable(.secondMissing))
        #expect(c.signalLevels.overall.clippedSampleCount == .incomparable(.secondMissing))
        #expect(c.truePeak.overall == .incomparable(.secondMissing))
        #expect(c.programmeBandwidth.overall == .incomparable(.secondMissing))
        #expect(c.loudness == .incomparable(.neitherPresent))
    }

    /// Differing channel counts keep the **overall** comparison and report the mismatch. The
    /// intersection is deliberately not compared: index 0 is not known to mean the same thing in both.
    @Test func differingChannelCountsCompareOverallAndReportTheMismatch() throws {
        let c = compare(
            bundle(levels: try levels(channels: 2), truePeak: try truePeak(channels: 2),
                   bandwidth: try bandwidth([16_000, 16_000])),
            bundle(levels: try levels(channels: 6), truePeak: try truePeak(channels: 6),
                   bandwidth: try bandwidth([16_000, 16_000, 16_000, 16_000, 16_000, 16_000]))
        )
        #expect(c.signalLevels.overall.peakSample == .same(0.5), "the overall figures stopped comparing")
        #expect(c.signalLevels.channels == .countsDiffer(first: 2, second: 6))
        #expect(c.truePeak.channels == .countsDiffer(first: 2, second: 6))
        #expect(c.programmeBandwidth.channels == .countsDiffer(first: 2, second: 6))
    }

    /// Channels are compared by index when the counts agree.
    @Test func channelsAreComparedByIndex() throws {
        let a = try bandwidth([16_000, 20_000])
        let b = try bandwidth([16_000, 12_000])
        guard case let .byIndex(entries) = compare(bundle(bandwidth: a), bundle(bandwidth: b)).programmeBandwidth.channels else {
            Issue.record("channels were not compared by index"); return
        }
        #expect(entries.count == 2)
        #expect({ if case .indistinguishable = entries[0] { true } else { false } }(), "index 0 should agree")
        #expect({ if case .separated = entries[1] { true } else { false } }(), "index 1 should differ")
    }

    /// A channel that carried no reading stays absent. **Never a reading of 0 Hz.**
    @Test func aChannelWithNoReadingIsNotZeroHertz() throws {
        let a = try bandwidth([16_000, nil])
        let b = try bandwidth([16_000, 16_000])
        guard case let .byIndex(entries) = compare(bundle(bandwidth: a), bundle(bandwidth: b)).programmeBandwidth.channels else {
            Issue.record("channels were not compared by index"); return
        }
        #expect(entries[1] == .incomparable(.firstMissing))
    }
}
