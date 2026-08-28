import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R4's subject: **the four sample-derived measurements, gathered into one section and unchanged by the
// move.**
//
// Every fact is asserted against the copy owner that produces it — `SignalLevelMetricsCopy`,
// `TruePeakCopy`, `LoudnessCopy`, `ProgrammeBandwidthCopy` — rather than retyped here, so the section
// cannot drift from the measurements it presents. Retyping the strings would pin this suite to a
// snapshot of the wording rather than to the wording itself.

@Suite("Feature — the report's measurements section")
struct ReportMeasurementsTests {

    // MARK: - Fixtures

    private func channel(
        sampleCount: Int = 44_100, peak: Float? = 0.5, rms: Float? = 0.25,
        dcOffset: Float? = 0.001, clipped: Int = 0
    ) throws -> SignalLevelMetrics.Channel {
        try #require(SignalLevelMetrics.Channel(
            sampleCount: sampleCount, peakSample: peak, rms: rms,
            dcOffset: dcOffset, clippedSampleCount: clipped
        ))
    }

    /// Two distinguishable channels, so a per-channel breakdown is real content rather than a repeat.
    private func stereoMetrics() throws -> SignalLevelMetrics {
        try #require(SignalLevelMetrics(
            channels: [
                try channel(peak: 0.708, rms: 0.3, dcOffset: 0.002, clipped: 3),
                try channel(peak: 0.5, rms: 0.2, dcOffset: -0.001, clipped: 0),
            ],
            overallPeakSample: 0.708, overallRMS: 0.25,
            overallDCOffset: 0.0005, overallClippedSampleCount: 3
        ))
    }

    /// A file with no audio frames: every per-sample value not computable, the clip count still defined.
    private func zeroFrameMetrics() throws -> SignalLevelMetrics {
        try #require(SignalLevelMetrics(
            channels: [try channel(sampleCount: 0, peak: nil, rms: nil, dcOffset: nil, clipped: 0)],
            overallPeakSample: nil, overallRMS: nil,
            overallDCOffset: nil, overallClippedSampleCount: 0
        ))
    }

    /// `TruePeakMeasurement.Channel` enforces the rule in both directions — a channel has a value
    /// exactly when it carried frames — so a `nil` peak here means a channel with no frames.
    private func truePeak(_ peaks: [Float?] = [1.1], factor: Int = 8) throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: factor, filter: .polyphaseFIRv1))
        let channels = try peaks.map { peak in
            try #require(TruePeakMeasurement.Channel(
                sampleCount: peak == nil ? 0 : 44_100, truePeak: peak
            ))
        }
        return try #require(TruePeakMeasurement(channels: channels, method: method))
    }

    private func loudness(_ lufs: Double = -14.3) throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)
        ))
    }

    private func bandwidth(
        _ frequency: Double? = 16_101.5625, resolution: Double = 23.4375
    ) throws -> SignificantBandwidth {
        let method = try #require(SignificantBandwidthMethod(
            identifier: SignificantBandwidthMethod.v1, windowFrames: 2_048,
            hopFrames: 512, sampleRate: 48_000
        ))
        let channel: SignificantBandwidth.Channel?
        if let frequency {
            channel = try #require(
                SignificantBandwidth.Channel(frequency: frequency, resolution: resolution)
            )
        } else {
            channel = nil
        }
        return try #require(SignificantBandwidth(channels: [channel], method: method))
    }

    /// Every measurement settled and carrying a value — the ordinary case.
    private func settled() throws -> [MeasurementGroupDisplay] {
        MeasurementsDisplay.groups(
            signalLevelMetrics: .metrics(try stereoMetrics()),
            truePeak: .measurement(try truePeak()),
            loudness: .measurement(try loudness()),
            programmeBandwidth: .measurement(try bandwidth())
        )
    }

    private func groups(
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation
    ) -> [MeasurementGroupDisplay] {
        MeasurementsDisplay.groups(
            signalLevelMetrics: signalLevelMetrics, truePeak: truePeak,
            loudness: loudness, programmeBandwidth: programmeBandwidth
        )
    }

    private func flat(_ groups: [MeasurementGroupDisplay]) -> [MeasurementDisplay] {
        groups.flatMap(\.measurements)
    }

    private func measurement(
        _ title: String, in groups: [MeasurementGroupDisplay]
    ) throws -> MeasurementDisplay {
        try #require(flat(groups).first { $0.title == title })
    }

    /// **Every string the section can render**, for a given set of states — rows, states, methods,
    /// spoken labels, group names and the disclosure's own label.
    private func everyString(_ groups: [MeasurementGroupDisplay]) -> [String] {
        var strings = MeasurementsCopy.everyRenderableString
        for group in groups {
            strings.append(group.name)
            for measurement in group.measurements {
                strings.append(measurement.title)
                for row in measurement.rows {
                    strings += [row.name, row.value, row.detail, row.accessibilityLabel].compactMap { $0 }
                }
                if let state = measurement.state {
                    strings += [state.headline, state.detail, state.accessibilityLabel].compactMap { $0 }
                }
                if let method = measurement.method {
                    strings += [method.text, method.accessibilityLabel]
                }
            }
        }
        return strings
    }

    /// Every combination of states that matters, so a sweep meets absence, failure and loading too.
    private func everyStateCombination() throws -> [[MeasurementGroupDisplay]] {
        let failure = "The measurement could not be completed."
        return [
            try settled(),
            groups(
                signalLevelMetrics: .metrics(try zeroFrameMetrics()),
                truePeak: .measurement(try truePeak([nil])),
                loudness: .absent,
                programmeBandwidth: .measurement(try bandwidth(nil))
            ),
            groups(
                signalLevelMetrics: .loading, truePeak: .loading,
                loudness: .loading, programmeBandwidth: .loading
            ),
            groups(
                signalLevelMetrics: .absent, truePeak: .absent,
                loudness: .absent, programmeBandwidth: .absent
            ),
            groups(
                signalLevelMetrics: .failed(message: failure),
                truePeak: .failed(message: failure),
                loudness: .failed(message: failure),
                programmeBandwidth: .failed(message: failure)
            ),
            groups(
                signalLevelMetrics: .metrics(try stereoMetrics()),
                truePeak: .loading,
                loudness: .failed(message: failure),
                programmeBandwidth: .absent
            ),
        ]
    }

    // MARK: - 2.1 — the section owns exactly the four families, in the report's order

    @Test("the section presents exactly the four measurements, each once")
    func exactlyTheFourMeasurements() throws {
        let titles = flat(try settled()).map(\.title)
        #expect(titles == [
            SignalLevelMetricsCopy.title,
            TruePeakCopy.title,
            LoudnessCopy.title,
            ProgrammeBandwidthCopy.title,
        ])
        #expect(Set(titles).count == titles.count, "a measurement appears more than once")
    }

    /// The grouping is a distinction between physical quantities: three about level, one about
    /// frequency. Every measurement sits in exactly one group.
    @Test("two groups, and every measurement in exactly one")
    func twoGroupsAndOneHomeEach() throws {
        let groups = try settled()
        #expect(groups.map(\.name) == [MeasurementsCopy.levelGroup, MeasurementsCopy.frequencyGroup])
        #expect(groups.map(\.measurements.count) == [3, 1])
        #expect(flat(groups).count == 4)
    }

    /// The order and the grouping hold whatever state each measurement is in — a section that
    /// rearranged itself around what happened to be available would move the reader's eye for reasons
    /// that are not about the file.
    @Test("the order and grouping do not depend on the states")
    func orderIsIndependentOfState() throws {
        for groups in try everyStateCombination() {
            #expect(groups.map(\.name) == [MeasurementsCopy.levelGroup, MeasurementsCopy.frequencyGroup])
            #expect(flat(groups).map(\.title) == [
                SignalLevelMetricsCopy.title, TruePeakCopy.title,
                LoudnessCopy.title, ProgrammeBandwidthCopy.title,
            ])
        }
    }

    // MARK: - 2.2 — no fact is lost, and none is re-formatted

    /// Signal levels: the four rows, with the values, units and details the copy owner produced —
    /// asserted against that owner rather than retyped.
    @Test("signal levels keep their rows, values and per-channel details")
    func signalLevelsKeepTheirFacts() throws {
        let metrics = try stereoMetrics()
        let levels = try measurement(SignalLevelMetricsCopy.title, in: try settled())
        let rows = levels.rows
        let expected = SignalLevelMetricsCopy.rows(for: metrics)
        #expect(rows.map(\.name) == expected.map(\.name))
        #expect(rows.map(\.value) == expected.map(\.value))
        #expect(rows.map(\.detail) == expected.map(\.detail))
        #expect(rows.map(\.accessibilityLabel) == expected.map(\.accessibilityLabel))
        // The units the two decibel rows are quoted in, and the two that are not decibels at all.
        #expect(rows.first { $0.name == "Peak sample" }?.value?.hasSuffix("dBFS") == true)
        #expect(rows.first { $0.name == "RMS level" }?.value?.hasSuffix("dBFS") == true)
        #expect(rows.first { $0.name == "DC offset" }?.value?.contains("dB") == false)
        #expect(rows.first { $0.name == "Clipped samples" }?.value == "3")
    }

    @Test("true peak keeps its value in dBTP and its per-channel detail")
    func truePeakKeepsItsFacts() throws {
        let stereo = try truePeak([1.1, 0.5])
        let display = MeasurementsDisplay.display(for: TruePeakPresentation.measurement(stereo))
        let expected = TruePeakCopy.rows(for: stereo)
        #expect(display.rows.map(\.value) == expected.map(\.value))
        #expect(display.rows.map(\.detail) == expected.map(\.detail))
        let value = try #require(display.rows.first?.value)
        #expect(value.hasSuffix("dBTP"), "the true peak lost its own unit")
        #expect(!value.contains("dBFS"), "the true peak is quoted under the sample peak's unit")
    }

    @Test("integrated loudness keeps its value in LUFS")
    func loudnessKeepsItsFacts() throws {
        let display = MeasurementsDisplay.display(for: LoudnessPresentation.measurement(try loudness()))
        let expected = LoudnessCopy.row(for: try loudness())
        #expect(display.rows.count == 1)
        #expect(display.rows.first?.name == expected.name)
        #expect(display.rows.first?.value == expected.value)
        let value = try #require(display.rows.first?.value)
        #expect(value.hasSuffix("LUFS"), "the loudness lost its unit")
        // LU is the unit of a *difference*, and this section publishes none.
        #expect(!value.hasSuffix(" LU"))
    }

    /// Programme bandwidth keeps **both** rows: the reading, and the grid it sits on.
    @Test("programme bandwidth keeps its reading and its analysis resolution")
    func bandwidthKeepsItsFacts() throws {
        let measured = try bandwidth()
        let display = MeasurementsDisplay.display(
            for: SignificantBandwidthPresentation.measurement(measured)
        )
        let value = try #require(ProgrammeBandwidthCopy.row(for: measured))
        let resolution = try #require(ProgrammeBandwidthCopy.resolutionRow(for: measured))
        #expect(display.rows.map(\.name) == [value.name, resolution.name])
        #expect(display.rows.map(\.value) == [value.value, resolution.value])
        #expect(display.rows.last?.name == ProgrammeBandwidthCopy.resolutionTitle)
    }

    /// The grid-rounding is the copy owner's, so a digit the analysis cannot support cannot appear here.
    @Test("the bandwidth value keeps the rounding the grid supports")
    func bandwidthKeepsItsRounding() throws {
        let measured = try bandwidth(16_101.5625, resolution: 23.4375)
        let display = MeasurementsDisplay.display(
            for: SignificantBandwidthPresentation.measurement(measured)
        )
        #expect(display.rows.first?.value == HumanFormat.programmeBandwidth(16_101.5625, resolution: 23.4375))
    }

    /// **The resolution is never joined to the value as a tolerance.** `16.1 ± 0.02 kHz` claims an
    /// uncertainty interval this measurement does not support (ADR-0023).
    @Test("the resolution is a quantity of its own, never a tolerance on the value")
    func resolutionIsNeverATolerance() throws {
        for groups in try everyStateCombination() {
            for string in everyString(groups) {
                #expect(!string.contains("±"), "a tolerance operator reached the surface: \(string)")
                #expect(!string.lowercased().contains("plus or minus"))
            }
        }
    }

    // MARK: - 2.3 — states: absence is not zero, failure is not absence

    @Test("a value that is not computable shows the words, never a number")
    func notComputableIsNeverANumber() throws {
        let display = MeasurementsDisplay.display(
            for: SignalLevelMetricsPresentation.metrics(try zeroFrameMetrics())
        )
        for name in ["Peak sample", "RMS level", "DC offset"] {
            let row = try #require(display.rows.first { $0.name == name })
            #expect(row.value == nil, "\(name) fabricated a value")
            #expect(row.detail?.contains("Not computable") == true, "\(name) lost its reason")
        }
    }

    /// The one metric that is always defined stays a number beside three that are not.
    @Test("a defined count survives beside values that are not computable")
    func definedCountSurvives() throws {
        let display = MeasurementsDisplay.display(
            for: SignalLevelMetricsPresentation.metrics(try zeroFrameMetrics())
        )
        #expect(display.rows.first { $0.name == "Clipped samples" }?.value == "0")
    }

    /// Absent, failed and loading are three different answers and read as three different sentences.
    @Test("absent, failed and loading are distinguishable")
    func theThreeStatesAreDistinguishable() throws {
        let absent = MeasurementsDisplay.display(for: LoudnessPresentation.absent)
        let failed = MeasurementsDisplay.display(
            for: LoudnessPresentation.failed(message: "The measurement could not be completed.")
        )
        let loading = MeasurementsDisplay.display(for: LoudnessPresentation.loading)
        let headlines = [absent, failed, loading].map(\.state?.headline)
        #expect(Set(headlines.compactMap { $0 }).count == 3, "two states share a sentence")
        #expect(absent.rows.isEmpty && failed.rows.isEmpty && loading.rows.isEmpty)
        #expect(absent.state?.headline == LoudnessCopy.text(for: .absent)?.headline)
    }

    /// **Only a failure of the reading is read at full weight.** An absence is not a defect of the file,
    /// and nothing about a value's magnitude may earn emphasis.
    @Test("only a read failure is emphasised")
    func onlyAReadFailureIsEmphasised() throws {
        for groups in try everyStateCombination() {
            for measurement in flat(groups) where measurement.isReadFailure {
                #expect(measurement.state != nil, "a failure with no sentence to read")
            }
        }
        #expect(MeasurementsDisplay.display(for: TruePeakPresentation.absent).isReadFailure == false)
        #expect(MeasurementsDisplay.display(for: TruePeakPresentation.loading).isReadFailure == false)
        // A value above full scale earns no emphasis of any kind.
        #expect(
            MeasurementsDisplay.display(for: TruePeakPresentation.measurement(try truePeak([1.9])))
                .isReadFailure == false
        )
        #expect(
            MeasurementsDisplay.display(for: TruePeakPresentation.failed(message: "x")).isReadFailure
        )
    }

    /// A bandwidth measurement can exist and carry **no reading**, and that reads as an absence rather
    /// than as an empty measurement with a method line under it.
    @Test("a bandwidth measurement with no reading reads as an absence")
    func bandwidthWithNoReadingIsAnAbsence() throws {
        let display = MeasurementsDisplay.display(
            for: SignificantBandwidthPresentation.measurement(try bandwidth(nil))
        )
        #expect(display.rows.isEmpty, "an empty measurement rendered rows")
        #expect(display.method == nil, "a method was offered for a measurement with no reading")
        #expect(
            display.state?.headline == ProgrammeBandwidthCopy.text(for: .absent)?.headline,
            "it does not read in the absence's own words"
        )
    }

    /// Every state that has no rows has a sentence, and every state with rows needs none: a measurement
    /// can never be a blank area the reader has to interpret.
    @Test("no measurement is ever silent")
    func noMeasurementIsEverSilent() throws {
        for groups in try everyStateCombination() {
            for measurement in flat(groups) {
                #expect(
                    !measurement.rows.isEmpty || measurement.state != nil,
                    "\(measurement.title) renders neither rows nor a sentence"
                )
            }
        }
    }

    // MARK: - 2.6 — accessibility, locally

    /// Each row is announced as one coherent sentence carrying its name, value and detail — the label
    /// the copy owner already built, never one rebuilt here.
    @Test("each row is announced as one sentence, taken from its own copy owner")
    func eachRowIsOneSentence() throws {
        let metrics = try stereoMetrics()
        let levels = try measurement(SignalLevelMetricsCopy.title, in: try settled())
        for (row, expected) in zip(levels.rows, SignalLevelMetricsCopy.rows(for: metrics)) {
            #expect(row.accessibilityLabel == expected.accessibilityLabel)
            #expect(row.accessibilityLabel.contains(row.name))
        }
        // Every state sentence carries a spoken form too, and it names the measurement.
        for groups in try everyStateCombination() {
            for measurement in flat(groups) {
                guard let state = measurement.state else { continue }
                #expect(!state.accessibilityLabel.isEmpty)
                #expect(state.accessibilityLabel.contains(measurement.title))
            }
        }
    }

    /// The method's spoken form is the copy owner's, so a reader hears the same sentence the eye reads.
    @Test("the method's spoken form is its own copy owner's")
    func methodSpokenFormIsTheCopyOwners() throws {
        let display = MeasurementsDisplay.display(for: LoudnessPresentation.measurement(try loudness()))
        #expect(display.method?.accessibilityLabel
            == LoudnessCopy.methodAccessibilityLabel(for: try loudness()))
        #expect(display.method?.accessibilityLabel.contains(MeasurementsCopy.methodDisclosure) == true)
    }
}
