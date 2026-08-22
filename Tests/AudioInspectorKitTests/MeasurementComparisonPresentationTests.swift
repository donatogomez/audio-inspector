import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// **Group 6's vocabulary, pinned without a view.**
//
// `MeasurementComparisonFormatter` is pure, so every string the sub-section can render is reachable
// from a function call. What these suites protect is not the layout — it is the promise that four
// measurements side by side stay four measurements and never become a verdict about two files.
//
// The measurements here are **built by hand on purpose**, which is the opposite of the rule group 5
// follows and right for the same reason it was wrong there. This suite is about words, and it needs
// states production cannot currently produce — a method mismatch, a missing side — so it constructs
// them. `MeasurementComparisonProductionSurfaceTests` is where the real files come back.
@Suite("Presentation — measurement comparison vocabulary")
struct MeasurementComparisonPresentationTests {

    // MARK: Building the two sides

    private func levels(
        peak: Float, rms: Float, dc: Float = 0, clipped: Int = 0, channels: Int = 1
    ) throws -> SignalLevelMetrics {
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 100, peakSample: peak, rms: rms, dcOffset: dc, clippedSampleCount: clipped
        ))
        return try #require(SignalLevelMetrics(
            channels: Array(repeating: channel, count: channels),
            overallPeakSample: peak, overallRMS: rms,
            overallDCOffset: dc, overallClippedSampleCount: clipped
        ))
    }

    private func truePeak(_ value: Float, factor: Int = 8, channels: Int = 1) throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: factor, filter: .polyphaseFIRv1))
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 100, truePeak: value))
        return try #require(TruePeakMeasurement(
            channels: Array(repeating: channel, count: channels), method: method
        ))
    }

    private func loudness(
        _ lufs: Double, weighting: LoudnessWeightingIdentifier = .publishedAt48kHz,
        algorithm: LoudnessAlgorithmIdentifier = .integratedBS1770v1
    ) throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: algorithm, weighting: weighting)
        ))
    }

    private func bandwidth(
        _ hertz: Double, resolution: Double = 23.4375, identifier: String = SignificantBandwidthMethod.v1,
        channels: Int = 1
    ) throws -> SignificantBandwidth {
        let method = try #require(SignificantBandwidthMethod(
            identifier: identifier, windowFrames: 2_048, hopFrames: 512, sampleRate: 48_000
        ))
        let reading = try #require(SignificantBandwidth.Channel(frequency: hertz, resolution: resolution))
        return try #require(SignificantBandwidth(
            channels: Array(repeating: reading, count: channels), method: method
        ))
    }

    private func bundle(
        levels: SignalLevelMetrics? = nil, truePeak: TruePeakMeasurement? = nil,
        loudness: LoudnessMeasurement? = nil, bandwidth: SignificantBandwidth? = nil
    ) -> ReportMeasurements {
        ReportMeasurements(
            signalLevelMetrics: levels, truePeak: truePeak, loudness: loudness, programmeBandwidth: bandwidth
        )
    }

    // MARK: Reading the result

    private func blocks(_ first: ReportMeasurements, _ second: ReportMeasurements) -> [MeasurementBlockDisplay] {
        MeasurementComparisonFormatter.blocks(for: MeasurementComparison(first: first, second: second))
    }

    private func rowNamed(
        _ name: String, _ first: ReportMeasurements, _ second: ReportMeasurements
    ) throws -> MeasurementRowDisplay {
        let all = blocks(first, second).flatMap(\.rows)
        return try #require(all.first { $0.name == name }, "no row named \(name) in \(all.map(\.name))")
    }

    /// Every string the sub-section can render for one pair, rows and notes and copy alike.
    private func everyString(_ first: ReportMeasurements, _ second: ReportMeasurements) -> [String] {
        let blocks = blocks(first, second)
        return blocks.flatMap { block -> [String] in
            [block.title] + [block.channelNote].compactMap { $0 } + block.rows.flatMap { row in
                [row.name, row.outcome.text, row.accessibilityLabel]
                    + [row.first.value, row.first.detail, row.second.value, row.second.detail,
                       row.difference, row.precisionNote].compactMap { $0 }
            }
        }
    }

    // MARK: 1–2 — signal levels

    /// **Four separate facts, never one outcome over them**, and equality is a plain word rather than a
    /// badge: peak, RMS, DC offset and a clipped-sample count are different quantities in different
    /// units.
    @Test("identical signal levels read as the same, figure by figure")
    func signalLevelsIdentical() throws {
        let metrics = try levels(peak: 0.5, rms: 0.2, dc: 0.001, clipped: 3)
        let side = bundle(levels: metrics)
        let names = [
            MeasurementComparisonCopy.peakSample, MeasurementComparisonCopy.rms,
            MeasurementComparisonCopy.dcOffset, MeasurementComparisonCopy.clippedSamples,
        ]
        for name in names {
            let row = try rowNamed(name, side, side)
            #expect(row.outcome == .same, "\(name) read \(row.outcome)")
            #expect(row.first.value == row.second.value)
            #expect(row.difference == nil, "\(name) published a difference")
        }
        // The values are the report's own formatters, not a second set.
        #expect(try rowNamed(MeasurementComparisonCopy.peakSample, side, side).first.value
            == HumanFormat.decibelsFullScale(0.5))
        #expect(try rowNamed(MeasurementComparisonCopy.dcOffset, side, side).first.value
            == HumanFormat.linearOffset(0.001))
        #expect(try rowNamed(MeasurementComparisonCopy.clippedSamples, side, side).first.value == "3")
    }

    /// **Different, with both values on screen and no direction anywhere.** Not higher, not lower, not
    /// hotter — and no difference, because these are linear amplitudes whose difference would be a ratio.
    @Test("differing signal levels show both values and rank neither")
    func signalLevelsDifferent() throws {
        let first = bundle(levels: try levels(peak: 0.5, rms: 0.2))
        let second = bundle(levels: try levels(peak: 0.9, rms: 0.4))
        let peak = try rowNamed(MeasurementComparisonCopy.peakSample, first, second)
        #expect(peak.outcome == .different)
        #expect(peak.first.value == HumanFormat.decibelsFullScale(0.5))
        #expect(peak.second.value == HumanFormat.decibelsFullScale(0.9))
        #expect(peak.difference == nil)

        // Reversing the pair changes the two values and nothing else — no word tracks which is larger.
        let reversed = try rowNamed(MeasurementComparisonCopy.peakSample, second, first)
        #expect(reversed.outcome == peak.outcome)
    }

    // MARK: 3–4 — true peak

    @Test("a comparable true peak shows both values in dBTP and no difference")
    func truePeakComparable() throws {
        let first = bundle(truePeak: try truePeak(0.9))
        let second = bundle(truePeak: try truePeak(1.05))
        let row = try rowNamed(TruePeakCopy.title, first, second)
        #expect(row.outcome == .different)
        #expect(row.first.value == HumanFormat.decibelsTruePeak(0.9))
        #expect(row.second.value == HumanFormat.decibelsTruePeak(1.05))
        #expect(row.difference == nil, "true peak published \(row.difference ?? "") — a ratio in disguise")
    }

    /// **A method mismatch is not a failure, and the copy must not call it one.** The flow ran, both
    /// files were inspected, and the two numbers are simply not on the same scale.
    @Test("differing true peak methods say why, and never that anything failed")
    func truePeakMethodsDiffer() throws {
        let first = bundle(truePeak: try truePeak(0.9, factor: 8))
        let second = bundle(truePeak: try truePeak(0.9, factor: 4))
        let row = try rowNamed(TruePeakCopy.title, first, second)
        #expect(row.outcome == .notComparable(reason: MeasurementComparisonCopy.methodsDiffer))
        #expect(row.outcome.text.contains("methods"))
        for word in ["failed", "failure", "error", "broken", "invalid"] {
            #expect(!row.outcome.text.lowercased().contains(word), "\"\(row.outcome.text)\" says \(word)")
        }
        // **Both values stay on screen.** A method mismatch is the one gap that occurs while both sides
        // measured, so hiding the two numbers would tell a reader the files measured nothing when what
        // actually happened is that the numbers are not on one scale.
        #expect(row.first.value == HumanFormat.decibelsTruePeak(0.9))
        #expect(row.second.value == HumanFormat.decibelsTruePeak(0.9))
        // And showing them does not make them comparable: the outcome is still the refusal.
        #expect(row.outcome == .notComparable(reason: MeasurementComparisonCopy.methodsDiffer))
        #expect(row.difference == nil)
    }

    /// **The other two metrics, on the same rule.** A method mismatch is the one gap that occurs while
    /// both sides measured, so every row it can appear on must keep both numbers — and none of them may
    /// publish a difference over them, because a difference needs two numbers on one scale.
    @Test("a method mismatch keeps both values on loudness and on bandwidth too")
    func methodsDifferKeepsBothValuesEverywhere() throws {
        let loudnessRow = try rowNamed(
            LoudnessCopy.title,
            bundle(loudness: try loudness(-14.2)),
            bundle(loudness: try loudness(-10.8, algorithm: LoudnessAlgorithmIdentifier(rawValue: "other_v1")))
        )
        #expect(loudnessRow.outcome == .notComparable(reason: MeasurementComparisonCopy.methodsDiffer))
        #expect(loudnessRow.first.value == HumanFormat.loudnessFullScale(-14.2))
        #expect(loudnessRow.second.value == HumanFormat.loudnessFullScale(-10.8))
        #expect(loudnessRow.difference == nil, "two numbers on different scales were subtracted")

        let bandwidthRow = try rowNamed(
            ProgrammeBandwidthCopy.title,
            bundle(bandwidth: try bandwidth(16_000)),
            bundle(bandwidth: try bandwidth(20_000, identifier: "other-v1"))
        )
        #expect(bandwidthRow.outcome == .notComparable(reason: MeasurementComparisonCopy.methodsDiffer))
        #expect(bandwidthRow.first.value != nil && bandwidthRow.second.value != nil)
        // A surviving reading keeps its resolution: the figure is only interpretable against its grid.
        #expect(bandwidthRow.first.detail == MeasurementComparisonCopy.resolution(23.4375))
        #expect(bandwidthRow.second.detail == MeasurementComparisonCopy.resolution(23.4375))
        #expect(bandwidthRow.difference == nil)
        // And neither outcome became one of the grid words: the analysis never ran on one scale.
        #expect(bandwidthRow.outcome != .indistinguishable)
        #expect(bandwidthRow.outcome != .separated)
    }

    /// A surviving value on a **bandwidth** absence keeps its resolution too, so the one number on
    /// screen is still interpretable.
    @Test("a surviving bandwidth reading keeps its resolution, and the absent side keeps nothing")
    func survivingBandwidthKeepsItsResolution() throws {
        let row = try rowNamed(
            ProgrammeBandwidthCopy.title, bundle(bandwidth: try bandwidth(16_101.5625)), bundle()
        )
        #expect(row.outcome == .notComparable(reason: MeasurementComparisonCopy.secondHasNoValue))
        #expect(row.first.value == HumanFormat.programmeBandwidth(16_101.5625, resolution: 23.4375))
        #expect(row.first.detail == MeasurementComparisonCopy.resolution(23.4375))
        #expect(row.second.value == nil)
        #expect(row.second.detail == nil, "the absent side was given a resolution it never measured on")
    }

    // MARK: 5–7 — loudness, the one row with a difference

    @Test("the loudness difference is second minus first, in LU, explicitly signed", arguments: [
        (-14.2, -10.8, "+3.4 LU"), (-10.8, -14.2, "-3.4 LU"),
    ])
    func loudnessDifference(first: Double, second: Double, expected: String) throws {
        let row = try rowNamed(
            LoudnessCopy.title, bundle(loudness: try loudness(first)), bundle(loudness: try loudness(second))
        )
        #expect(row.outcome == .different)
        #expect(row.difference == expected)
        #expect(row.first.value == HumanFormat.loudnessFullScale(first))
        #expect(row.second.value == HumanFormat.loudnessFullScale(second))
        // **LU, never LUFS.** Subtracting two levels cancels the reference; what is left is a difference.
        #expect(row.difference?.hasSuffix(" LU") == true)
        #expect(row.difference?.contains("LUFS") == false)
    }

    /// **Two equal loudness values carry no difference at all**, because `0.0 LU` states nothing the
    /// word `Same` has not already said — and the domain does not store one either.
    @Test("equal loudness reads as the same and publishes no zero difference")
    func loudnessZeroDifference() throws {
        let side = bundle(loudness: try loudness(-14.2))
        let row = try rowNamed(LoudnessCopy.title, side, side)
        #expect(row.outcome == .same)
        #expect(row.difference == nil)
        #expect(row.first.value == row.second.value)
    }

    /// **Nothing varies with the sign** (task 6.6): the two rows differ in the difference's characters
    /// and in nothing else a surface could style — same outcome, same secondary treatment, same shape.
    @Test("the sign of the difference changes no part of the row but the number")
    func nothingTracksTheSign() throws {
        let up = try rowNamed(
            LoudnessCopy.title, bundle(loudness: try loudness(-14.0)), bundle(loudness: try loudness(-10.0))
        )
        let down = try rowNamed(
            LoudnessCopy.title, bundle(loudness: try loudness(-10.0)), bundle(loudness: try loudness(-14.0))
        )
        #expect(up.outcome == down.outcome)
        #expect(up.outcome.isSecondary == down.outcome.isSecondary)
        #expect(up.difference == "+4.0 LU" && down.difference == "-4.0 LU")
        // Neither sentence characterises the direction.
        for sentence in [up.accessibilityLabel, down.accessibilityLabel] {
            for word in ["louder", "quieter", "hotter", "higher", "lower", "increase", "decrease"] {
                #expect(!sentence.lowercased().contains(word), "\"\(sentence)\" says \(word)")
            }
        }
    }

    // MARK: 8–9 — bandwidth, in the instrument's words

    /// **Words about the grid, never about the files** (task 6.2). `Indistinguishable at these
    /// resolutions` says the analysis did not separate two readings; `Same` would say the two files are
    /// alike, which is a different claim and one this measurement cannot make.
    @Test("overlapping bandwidth cells are indistinguishable, never the same")
    func bandwidthIndistinguishable() throws {
        let row = try rowNamed(
            ProgrammeBandwidthCopy.title,
            bundle(bandwidth: try bandwidth(16_101.09375, resolution: 22.96875)),
            bundle(bandwidth: try bandwidth(16_101.5625, resolution: 23.4375))
        )
        #expect(row.outcome == .indistinguishable)
        #expect(row.outcome.text == "Indistinguishable at these resolutions")
        #expect(row.outcome.text != "Same")
        #expect(row.difference == nil, "bandwidth published a hertz difference: \(row.difference ?? "")")
        // Each side's own resolution is on screen, because the outcome refers to it.
        #expect(row.first.detail == MeasurementComparisonCopy.resolution(22.96875))
        #expect(row.second.detail == MeasurementComparisonCopy.resolution(23.4375))
        #expect(row.first.detail?.contains("±") == false)
    }

    @Test("separated bandwidth cells say separated, never that the files differ")
    func bandwidthSeparated() throws {
        let row = try rowNamed(
            ProgrammeBandwidthCopy.title,
            bundle(bandwidth: try bandwidth(12_000)), bundle(bandwidth: try bandwidth(16_000))
        )
        #expect(row.outcome == .separated)
        #expect(row.outcome.text == "Separated at these resolutions")
        #expect(row.outcome.text != "Different")
        #expect(row.difference == nil)
        // Never a cut-off, never a claim about provenance.
        for word in ["cutoff", "cut-off", "upsample", "transcode", "filtered", "lossy"] {
            #expect(!row.accessibilityLabel.lowercased().contains(word))
        }
    }

    // MARK: 10–12 — the three absences, each said about the right side

    /// The side named is the one that had **nothing** — a bundle with only the first side's loudness
    /// leaves the *second* with no value, and the sentence says so.
    @Test("each missing side is named, and never rendered as a zero", arguments: [
        (true, false, "the second file"), (false, true, "the first file"),
    ])
    func oneSideMissing(hasFirst: Bool, hasSecond: Bool, mentions: String) throws {
        let present = bundle(loudness: try loudness(-14.0))
        let absent = bundle()
        let row = try rowNamed(LoudnessCopy.title, hasFirst ? present : absent, hasSecond ? present : absent)

        guard case let .notComparable(reason) = row.outcome else {
            Issue.record("a missing side read as \(row.outcome)"); return
        }
        #expect(reason.contains(mentions), "\"\(reason)\" does not name the side that had no value")
        #expect(row.difference == nil)
        #expect(!reason.contains("0"))

        // **The side that measured keeps its number; only the side that did not says so.**
        //
        // This used to assert that *both* columns were empty, and that was the defect: a pair where the
        // first file measured −14.0 LUFS and the second measured nothing printed "No value" under both,
        // stating something false about the first file. The outcome names the missing side; the columns
        // now agree with it.
        let measuredSide = hasFirst ? row.first : row.second
        let absentSide = hasFirst ? row.second : row.first
        #expect(measuredSide.value == HumanFormat.loudnessFullScale(-14.0), "the measured side lost its value")
        #expect(absentSide.value == nil, "the absent side grew a value")

        // Absence is words, never a number — and specifically never zero.
        //
        // **Asserted as "this is not parseable as a number", not as "this equals the constant".**
        // A control replacing the constant with "0" slipped straight through a test written against
        // the constant, which is the tautology every copy assertion is one step away from.
        #expect(
            Double(MeasurementComparisonCopy.noValue) == nil,
            "an absence is said with the number \(MeasurementComparisonCopy.noValue)"
        )
        #expect(absentSide.spoken == MeasurementComparisonCopy.noValue)
        #expect(Double(absentSide.spoken) == nil, "an absent side is announced as a number")
    }

    @Test("neither file having a value is said once, not twice")
    func neitherSideHasAValue() throws {
        let row = try rowNamed(LoudnessCopy.title, bundle(), bundle())
        #expect(row.outcome == .notComparable(reason: MeasurementComparisonCopy.neitherHasAValue))
        #expect(row.outcome.text.contains("neither"))
    }

    /// **An empty column stays empty, on every row — not only on the one this defect was found on.**
    ///
    /// A control fabricating `"0"` for a missing side slipped through the first time, because the only
    /// test looking at the columns of an incomparable row was the loudness one, and loudness has a
    /// branch of its own. This sweeps all seven rows, on all three shapes of absence.
    @Test("an absent side is empty on every row, never a fabricated figure")
    func noRowFabricatesAValueForAnAbsentSide() throws {
        let full = bundle(
            levels: try levels(peak: 0.5, rms: 0.2), truePeak: try truePeak(0.9),
            loudness: try loudness(-14.2), bandwidth: try bandwidth(16_000)
        )
        let empty = bundle()

        for row in blocks(empty, empty).flatMap(\.rows) {
            #expect(row.first.value == nil, "\(row.name) invented \(row.first.value ?? "") for the first file")
            #expect(row.second.value == nil, "\(row.name) invented \(row.second.value ?? "") for the second file")
            #expect(row.first.detail == nil && row.second.detail == nil)
        }
        for row in blocks(full, empty).flatMap(\.rows) {
            #expect(row.second.value == nil, "\(row.name) invented \(row.second.value ?? "") for the absent side")
            #expect(row.first.value != nil, "\(row.name) dropped the value the first file has")
        }
        for row in blocks(empty, full).flatMap(\.rows) {
            #expect(row.first.value == nil, "\(row.name) invented \(row.first.value ?? "") for the absent side")
            #expect(row.second.value != nil, "\(row.name) dropped the value the second file has")
        }
    }

    /// The four gaps produce four distinct sentences: a reader can tell *"the methods differ"* from
    /// *"this file had no value"*, which is exactly what task 6.4 requires.
    @Test("the four gaps are four different sentences")
    func everyGapIsDistinguishable() {
        let sentences = [MeasurementGapReason.firstMissing, .secondMissing, .neitherPresent, .methodsDiffer]
            .map(MeasurementComparisonFormatter.reason(for:))
        #expect(Set(sentences).count == 4, "two gaps read identically: \(sentences)")
    }

    // MARK: 13 — a channel-count mismatch

    /// **The overall figures still compare; the per-channel ones are not intersected.** Comparing the
    /// first channel of a mono file against the first of a stereo one would assert that index 0 means
    /// the same thing in both, which the pipeline refuses to claim.
    @Test("a channel-count mismatch is stated, and no index is compared")
    func channelCountMismatch() throws {
        let first = bundle(
            levels: try levels(peak: 0.5, rms: 0.2, channels: 1),
            truePeak: try truePeak(0.5, channels: 1),
            bandwidth: try bandwidth(16_000, channels: 1)
        )
        let second = bundle(
            levels: try levels(peak: 0.5, rms: 0.2, channels: 2),
            truePeak: try truePeak(0.5, channels: 2),
            bandwidth: try bandwidth(16_000, channels: 2)
        )
        let blocks = blocks(first, second)

        for block in blocks where block.title != LoudnessCopy.title {
            let note = try #require(block.channelNote, "\(block.title) said nothing about the mismatch")
            #expect(note.contains("1 and 2"), "\"\(note)\" does not name the two counts")
            #expect(note.lowercased().contains("not compared per channel"))
            // No layout, ever.
            for word in ["left", "right", "stereo", "mono", "centre", "center", "surround"] {
                #expect(!note.lowercased().contains(word), "\"\(note)\" names a layout")
            }
            // And no ranking of one count against the other.
            for word in ["better", "worse", "more", "fewer", "richer", "full"] {
                #expect(!note.lowercased().contains(word), "\"\(note)\" ranks the two counts")
            }
        }
        // Loudness has no channels at all, so it has nothing to say about them.
        let loudnessBlock = try #require(blocks.first { $0.title == LoudnessCopy.title })
        #expect(loudnessBlock.channelNote == nil)

        // The overall figures were still compared.
        #expect(try rowNamed(MeasurementComparisonCopy.peakSample, first, second).outcome == .same)
        #expect(try rowNamed(TruePeakCopy.title, first, second).outcome == .same)

        // And no per-channel detail was fabricated from the intersection.
        for name in [MeasurementComparisonCopy.peakSample, TruePeakCopy.title] {
            let row = try rowNamed(name, first, second)
            #expect(row.first.detail == nil && row.second.detail == nil,
                    "\(name) rendered a per-channel breakdown across differing counts")
        }
    }

    /// When the counts **do** match, each side shows its own per-channel figures — the way the report
    /// already shows them for one file — by index and never by name.
    @Test("matching channel counts show each side's own figures, by index")
    func matchingChannelsShowTheirFigures() throws {
        let first = bundle(levels: try levels(peak: 0.5, rms: 0.2, channels: 2))
        let second = bundle(levels: try levels(peak: 0.9, rms: 0.4, channels: 2))
        let row = try rowNamed(MeasurementComparisonCopy.peakSample, first, second)
        let detail = try #require(row.first.detail)
        #expect(detail == "Channel 1: \(HumanFormat.decibelsFullScale(0.5)) · Channel 2: \(HumanFormat.decibelsFullScale(0.5))")
        #expect(try #require(row.second.detail).contains(HumanFormat.decibelsFullScale(0.9)))
        for word in ["left", "right"] {
            #expect(!detail.lowercased().contains(word))
        }
        // One channel needs no breakdown: it would repeat the overall figure.
        let mono = bundle(levels: try levels(peak: 0.5, rms: 0.2, channels: 1))
        #expect(try rowNamed(MeasurementComparisonCopy.peakSample, mono, mono).first.detail == nil)
    }

    // MARK: The display's own limits, said rather than papered over

    /// **Two values that differ by less than the row can show.**
    ///
    /// `linearOffset` shows four decimals because `Float` does not honestly carry more at that
    /// magnitude, so two DC offsets around 10⁻¹⁴ both print as `0.0000` beside the word `Different`.
    /// Left alone the row reads as a defect. The fix is a sentence, **never another digit**.
    @Test("two values that round alike say so, rather than looking like a contradiction")
    func differenceBelowThePrecisionIsExplained() throws {
        let first = bundle(levels: try levels(peak: 0.5, rms: 0.2, dc: 1e-14))
        let second = bundle(levels: try levels(peak: 0.5, rms: 0.2, dc: -3e-14))
        let row = try rowNamed(MeasurementComparisonCopy.dcOffset, first, second)
        #expect(row.outcome == .different)
        #expect(row.first.value == row.second.value, "this fixture no longer rounds alike")
        #expect(row.precisionNote == MeasurementComparisonCopy.differsBelowThisPrecision)
        #expect(row.accessibilityLabel.contains(MeasurementComparisonCopy.differsBelowThisPrecision))
        // It says there is a difference, never how big — that is the digit the limit withholds.
        for token in ["0.00000", "e-14", "10⁻¹⁴"] {
            #expect(!(row.precisionNote ?? "").contains(token))
        }
        // And a row whose two values genuinely read the same carries no note at all.
        let same = bundle(levels: try levels(peak: 0.5, rms: 0.2, dc: 0))
        #expect(try rowNamed(MeasurementComparisonCopy.dcOffset, same, same).precisionNote == nil)
    }

    /// The bandwidth pair of the same problem, from both sides of the cell rule.
    @Test("a bandwidth row reconciles the grid with the rounding, in both directions")
    func bandwidthRoundingIsExplained() throws {
        // One bin apart at 48 kHz: separated by the rule, identical once rounded to the grid.
        let separated = try rowNamed(
            ProgrammeBandwidthCopy.title,
            bundle(bandwidth: try bandwidth(16_101.5625)), bundle(bandwidth: try bandwidth(16_125.0))
        )
        #expect(separated.outcome == .separated)
        #expect(separated.first.value == separated.second.value)
        #expect(separated.precisionNote == MeasurementComparisonCopy.separatedButRoundsAlike)

        // And the converse: cells that overlap across a rounding boundary.
        let overlapping = try rowNamed(
            ProgrammeBandwidthCopy.title,
            bundle(bandwidth: try bandwidth(16_149.0)), bundle(bandwidth: try bandwidth(16_151.0))
        )
        #expect(overlapping.outcome == .indistinguishable)
        #expect(overlapping.first.value != overlapping.second.value, "this fixture no longer rounds apart")
        #expect(overlapping.precisionNote == MeasurementComparisonCopy.overlapsButRoundsApart)

        // Neither note is a difference, and neither prints a hertz figure.
        for note in [separated.precisionNote, overlapping.precisionNote].compactMap({ $0 }) {
            #expect(!note.contains("Hz"))
            #expect(!note.contains("+"))
        }
    }

    // MARK: 14 — the forbidden vocabulary, over everything the sub-section can render

    /// **Task 6.5, extended as the task lists it**, and swept over every string reachable from a
    /// comparison rather than over a chosen few.
    ///
    /// Unlike `ComparisonCopy.subtitle`, nothing here needs an exemption: this sub-section's own
    /// disclaimer is written so that it denies the inference **without naming it**, so a blunt substring
    /// scan covers the whole vocabulary including the copy.
    @Test("no string anywhere ranks, interprets or infers")
    func noForbiddenVocabulary() throws {
        let forbidden = [
            "master", "remaster", "transcode", "upsample", "lossy", "compressed", "dynamics",
            "louder", "quieter", "hotter", "better", "worse", "original", "derived", "generation",
            "quality", "genuine", "authentic", "suspicious", "likely", "suggests", "cutoff",
            "cut-off", "fake", "score", "winner", "preferred", "upgrade", "downgrade", "%",
            "appears to be", "probably", "indicates that", "points to",
        ]

        // Every shape a comparison can take: present/absent on both sides, matching and differing
        // methods, matching and differing channel counts.
        let full = bundle(
            levels: try levels(peak: 0.5, rms: 0.2, channels: 2), truePeak: try truePeak(0.9, channels: 2),
            loudness: try loudness(-14.2), bandwidth: try bandwidth(16_000, channels: 2)
        )
        let other = bundle(
            levels: try levels(peak: 0.9, rms: 0.4, channels: 1), truePeak: try truePeak(1.05, factor: 4, channels: 1),
            loudness: try loudness(-10.8, algorithm: LoudnessAlgorithmIdentifier(rawValue: "other")),
            bandwidth: try bandwidth(20_000, identifier: "other", channels: 1)
        )
        let empty = bundle()

        var strings = Set<String>()
        for first in [full, other, empty] {
            for second in [full, other, empty] {
                strings.formUnion(everyString(first, second))
            }
        }
        strings.formUnion([
            MeasurementComparisonCopy.title, MeasurementComparisonCopy.subtitle,
            MeasurementComparisonCopy.waiting, MeasurementComparisonCopy.firstFile,
            MeasurementComparisonCopy.secondFile, MeasurementComparisonCopy.outcomeColumn,
            MeasurementComparisonCopy.measurementColumn, MeasurementComparisonCopy.differenceLabel,
            MeasurementComparisonCopy.noValue,
        ])

        for text in strings {
            for word in forbidden {
                #expect(
                    !text.lowercased().contains(word),
                    "\"\(text)\" contains the forbidden word \"\(word)\""
                )
            }
        }
    }

    // MARK: 15–17 — the difference exists on exactly one row

    /// **Task 6.3.** Swept over every comparison shape, not asserted on one example: the only row that
    /// can ever carry a difference is integrated loudness.
    @Test("no row but loudness ever carries a difference")
    func onlyLoudnessCarriesADifference() throws {
        let full = bundle(
            levels: try levels(peak: 0.5, rms: 0.2, channels: 2), truePeak: try truePeak(0.9, channels: 2),
            loudness: try loudness(-14.2), bandwidth: try bandwidth(16_000, channels: 2)
        )
        let other = bundle(
            levels: try levels(peak: 0.9, rms: 0.4, channels: 2), truePeak: try truePeak(1.05, channels: 2),
            loudness: try loudness(-10.8), bandwidth: try bandwidth(20_000, channels: 2)
        )
        for first in [full, other, bundle()] {
            for second in [full, other, bundle()] {
                for row in blocks(first, second).flatMap(\.rows) where row.name != LoudnessCopy.title {
                    #expect(
                        row.difference == nil,
                        "\(row.name) published a difference of \(row.difference ?? "")"
                    )
                    #expect(
                        !row.accessibilityLabel.contains(MeasurementComparisonCopy.differenceLabel),
                        "\(row.name) announced a difference"
                    )
                }
            }
        }
    }

    // MARK: 18–19 — no domain identity reaches the reader

    /// **This sub-section never describes a method, so no identity can leak into it — recognised or
    /// not.**
    ///
    /// The report's own sections *do* describe their methods, and each has a fallback naming an
    /// unrecognised identity verbatim rather than guessing at it. That precedent does not apply here:
    /// a comparison row states two values and what comparing them established, and the method line for
    /// each file is already on screen above, in that file's own section. So the rule this asserts is the
    /// stronger one — **no slug at all**, which also means there is no fallback that could go stale.
    @Test("no domain identity appears in any comparison string, known or unknown")
    func noIdentityLeaks() throws {
        let full = bundle(
            levels: try levels(peak: 0.5, rms: 0.2), truePeak: try truePeak(0.9),
            loudness: try loudness(-14.2), bandwidth: try bandwidth(16_000)
        )
        let strange = bundle(
            levels: try levels(peak: 0.9, rms: 0.4), truePeak: try truePeak(1.05, factor: 4),
            loudness: try loudness(-10.8, weighting: LoudnessWeightingIdentifier(rawValue: "unknown_weighting_v9")),
            bandwidth: try bandwidth(20_000, identifier: "unknown-bandwidth-v9")
        )
        let slugs = [
            LoudnessAlgorithmIdentifier.integratedBS1770v1.rawValue,
            LoudnessWeightingIdentifier.publishedAt48kHz.rawValue,
            LoudnessWeightingIdentifier.derivedFrom48kHz.rawValue,
            TruePeakFilterIdentifier.polyphaseFIRv1.rawValue,
            SignificantBandwidthMethod.v1,
            "unknown_weighting_v9", "unknown-bandwidth-v9",
        ]
        for first in [full, strange] {
            for second in [full, strange] {
                for text in everyString(first, second) {
                    for slug in slugs {
                        #expect(!text.contains(slug), "\"\(text)\" leaks the identity \"\(slug)\"")
                    }
                }
            }
        }
    }

    // MARK: 20 — what an assistive reader hears

    /// **The structural half of accessibility, and only that** (task 6.7): each row is one sentence
    /// naming the measurement, both files' values and the outcome — plus the difference where there is
    /// one. The traversal gap ADR-0015 and ADR-0017 share is untouched and stays open.
    @Test("a row is announced as one sentence with both values and the outcome")
    func aRowIsAnnouncedAsOneSentence() throws {
        let row = try rowNamed(
            LoudnessCopy.title, bundle(loudness: try loudness(-14.2)), bundle(loudness: try loudness(-10.8))
        )
        #expect(row.accessibilityLabel == """
        Integrated loudness. First file, -14.2 LUFS. Second file, -10.8 LUFS. Different. \
        Difference, +3.4 LU.
        """)
    }

    /// A bandwidth row announces the instrument's words, and both resolutions with them.
    @Test("a bandwidth row announces the resolutions its outcome refers to")
    func aBandwidthRowAnnouncesItsResolutions() throws {
        let row = try rowNamed(
            ProgrammeBandwidthCopy.title,
            bundle(bandwidth: try bandwidth(16_101.09375, resolution: 22.96875)),
            bundle(bandwidth: try bandwidth(16_101.5625, resolution: 23.4375))
        )
        #expect(row.accessibilityLabel.contains("Indistinguishable at these resolutions"))
        #expect(row.accessibilityLabel.contains("Analysis resolution"))
        #expect(!row.accessibilityLabel.contains(MeasurementComparisonCopy.differenceLabel))
    }

    /// A side with no value says so aloud rather than falling silent — a blank would be indistinguishable
    /// from a zero to a reader who cannot see the row.
    @Test("a side with no value announces the absence")
    func anAbsentSideIsAnnounced() throws {
        let row = try rowNamed(LoudnessCopy.title, bundle(loudness: try loudness(-14.0)), bundle())
        #expect(row.accessibilityLabel.contains(MeasurementComparisonCopy.noValue))
        #expect(row.accessibilityLabel.contains("the second file has no value"))
    }

    // MARK: The shape of the sub-section itself

    /// **Task 6.1's order**, and it is the report's own: levels, true peak, loudness, bandwidth. Not
    /// reordered by importance, and specifically not with loudness first because it is the row carrying
    /// a difference.
    @Test("the four metrics appear in the report's own order")
    func theOrderIsTheReports() throws {
        let side = bundle(
            levels: try levels(peak: 0.5, rms: 0.2), truePeak: try truePeak(0.9),
            loudness: try loudness(-14.2), bandwidth: try bandwidth(16_000)
        )
        #expect(blocks(side, side).map(\.title) == [
            SignalLevelMetricsCopy.title, TruePeakCopy.title,
            LoudnessCopy.title, ProgrammeBandwidthCopy.title,
        ])
    }

    /// **Colour is never the signal** (task 6.6, and ADR-0017's rule inherited).
    ///
    /// The one styling hook the model exposes is `isSecondary`, and it tracks *"this cell is an
    /// explanation rather than a value"* — nothing else. `Same` and `Different` are styled identically,
    /// the two bandwidth words are styled identically, and a positive difference is styled exactly as a
    /// negative one. A reader who cannot distinguish colours loses nothing, because the words carry the
    /// whole meaning.
    @Test("nothing but an explanation is styled differently, and the outcome words never are")
    func colourIsNeverTheSignal() {
        let outcomes: [MeasurementOutcomeDisplay] = [.same, .different, .indistinguishable, .separated]
        for outcome in outcomes {
            #expect(!outcome.isSecondary, "\(outcome.text) is styled apart from its siblings")
        }
        #expect(MeasurementOutcomeDisplay.notComparable(reason: "x").isSecondary)
        // Every outcome is distinguishable by its text alone.
        #expect(Set(outcomes.map(\.text)).count == outcomes.count)
    }

    /// **The surface cannot reach a measurement bundle, so it cannot pair one with another operation's
    /// comparison.**
    ///
    /// This is the alternative the fix rejected, pinned so it cannot creep back. Looking a missing
    /// number up from a `ReportMeasurements` travelling beside the comparison would put two values and
    /// one outcome on screen from two different places, free to belong to two different operations —
    /// the defect `MeasurementComparisonAtomicityTests` exists for. The sub-section is given exactly one
    /// thing, and everything it shows is derived from it.
    @Test("the sub-section is given the comparison and nothing else")
    func theSurfaceHasNoSecondSource() throws {
        let section = MeasurementComparisonSection(comparison: nil)
        let fields = Mirror(reflecting: section).children.compactMap(\.label)
        #expect(fields == ["comparison"], "the sub-section grew a second source: \(fields)")

        // And what it holds is the comparison, never a bundle either side could have been read from.
        let held = Mirror(reflecting: section).children.first?.value
        #expect(held is MeasurementComparison?)
        #expect(!(held is ReportMeasurements), "a measurement bundle reached the surface")
    }

    /// **No aggregate of any kind**, mirroring the domain's own refusal: no count of how many differ,
    /// no summary row, no verdict line. The formatter produces blocks of rows and nothing else.
    @Test("the sub-section offers no aggregate of the comparison")
    func thereIsNoAggregate() throws {
        let first = bundle(
            levels: try levels(peak: 0.5, rms: 0.2), truePeak: try truePeak(0.9),
            loudness: try loudness(-14.2), bandwidth: try bandwidth(16_000)
        )
        let second = bundle(
            levels: try levels(peak: 0.9, rms: 0.4), truePeak: try truePeak(1.05),
            loudness: try loudness(-10.8), bandwidth: try bandwidth(20_000)
        )
        let rows = blocks(first, second).flatMap(\.rows)
        // Seven rows: four level figures, true peak, loudness, bandwidth. No eighth summarising them.
        #expect(rows.count == 7, "\(rows.map(\.name))")
        #expect(Set(rows.map(\.name)).count == 7, "a row name repeats")
        for text in [MeasurementComparisonCopy.subtitle, MeasurementComparisonCopy.title] {
            #expect(!text.contains("differences"))
            #expect(!text.lowercased().contains("out of"))
        }
    }
}
