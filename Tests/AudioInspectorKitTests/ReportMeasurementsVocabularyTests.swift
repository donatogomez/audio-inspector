import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R4's refusals: **what the section may never say, and what it may never hide.**
//
// It is a suite of its own rather than a section of `ReportMeasurementsTests` for the reason
// `ProgrammeBandwidthNegativeControlTests` is one: these assert what may never appear, and a sweep that
// shares a file with the contracts it guards is read as one of them.

@Suite("Feature — what the measurements section may never say or hide")
struct ReportMeasurementsVocabularyTests {

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
                try channel(peak: 0.5, rms: 0.2, dcOffset: -0.001, clipped: 0)
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
            )
        ]
    }

    // MARK: - 2.4 — method disclosure hides explanation, never fact

    /// Every measurement that records a method reaches the surface with it.
    @Test("every recorded method reaches the section")
    func everyRecordedMethodReachesTheSection() throws {
        let groups = try settled()
        let peak = try measurement(TruePeakCopy.title, in: groups)
        let programme = try measurement(LoudnessCopy.title, in: groups)
        let band = try measurement(ProgrammeBandwidthCopy.title, in: groups)
        let levels = try measurement(SignalLevelMetricsCopy.title, in: groups)
        #expect(peak.method?.text == TruePeakCopy.method(for: try truePeak()))
        #expect(programme.method?.text == LoudnessCopy.method(for: try loudness()))
        #expect(band.method?.text == ProgrammeBandwidthCopy.method(for: try bandwidth()))
        // Signal levels records none, so none is invented to fill the field.
        #expect(levels.method == nil)
    }

    /// **Nothing but the method is behind the disclosure.** Every value, unit, per-channel detail,
    /// absence sentence, failure sentence and the analysis resolution is outside it, by construction:
    /// they live on `rows` and `state`, and only `method` is collapsed.
    @Test("no fact is carried by the collapsible half")
    func noFactIsBehindTheDisclosure() throws {
        for groups in try everyStateCombination() {
            for measurement in flat(groups) {
                guard let method = measurement.method else { continue }
                // A method is offered only where the facts are already on screen as rows.
                #expect(!measurement.rows.isEmpty, "\(measurement.title) collapsed its only content")
                for row in measurement.rows {
                    #expect(
                        !method.text.contains(row.value ?? "\u{0}"),
                        "\(measurement.title)'s value is inside the collapsed sentence"
                    )
                }
            }
        }
        // The resolution is a row, so it is never collapsed.
        let bandwidth = MeasurementsDisplay.display(
            for: SignificantBandwidthPresentation.measurement(try self.bandwidth())
        )
        #expect(bandwidth.rows.contains { $0.name == ProgrammeBandwidthCopy.resolutionTitle })
    }

    // MARK: - 2.5 — the vocabulary sweep

    /// **No judgement, no threshold, no target, no provenance** — over every string the section can
    /// render, in every combination of states.
    @Test("nothing on this section states a verdict, a target or a provenance")
    func theSweep() throws {
        let forbidden = [
            "good", "bad", "better", "worse", "poor", "excellent", "quality", "grade", "score",
            "safe", "unsafe", "hot", "too loud", "too quiet", "excessive", "acceptable",
            "clipping detected", "distorted", "damaged", "healthy", "clean",
            "should be", "recommended", "target", "normalis", "normaliz", "loudness war",
            "broadcast", "spotify", "apple music", "youtube", "ebu r 128", "r128", "lufs target",
            "master", "remaster", "transcode", "upsampl", "downsampl", "lossy", "bitrate of",
            "sounds", "audible", "perceiv", "prefer", "ideal", "optimal", "correct level",
            "matches", "identical to", "differences", "all match", "similarity", "confidence"
        ]
        for groups in try everyStateCombination() {
            for string in everyString(groups) {
                let lower = string.lowercased()
                for word in forbidden {
                    #expect(!lower.contains(word), "\"\(word)\" reached the surface in: \(string)")
                }
            }
        }
    }

    /// **No aggregate, direct or by absence.** The section offers no total, count, percentage or single
    /// phrase over the four — and the two group names it adds carry no digit, the cheapest way to keep
    /// `"4 measurements"` from appearing quietly.
    @Test("the section publishes no aggregate over the four measurements")
    func noAggregate() throws {
        for string in MeasurementsCopy.everyRenderableString {
            let carriesAFigure = string.rangeOfCharacter(from: .decimalDigits) != nil
            #expect(!carriesAFigure, "a figure reached the section's own vocabulary: \(string)")
            #expect(!string.lowercased().contains("all"))
            #expect(!string.lowercased().contains("total"))
        }
        // Nothing in the derivation counts the measurements into a phrase.
        for groups in try everyStateCombination() {
            for headline in flat(groups).compactMap(\.state?.headline) {
                let counts = headline.lowercased().contains("of the")
                    && headline.rangeOfCharacter(from: .decimalDigits) != nil
                #expect(!counts, "a count over the measurements reached the surface: \(headline)")
            }
        }
    }

    /// **No difference of any kind.** LU is the unit of a loudness difference; this section publishes
    /// none, for any measurement, in any state.
    @Test("the section publishes no difference")
    func noDifference() throws {
        for groups in try everyStateCombination() {
            for string in everyString(groups) {
                #expect(!string.hasSuffix(" LU"), "a difference in LU reached the section: \(string)")
                #expect(!string.lowercased().contains("difference"))
            }
        }
    }

    /// **No comparison vocabulary.** The comparison stays whole, where it is, until R8: this section
    /// names no second file and no side of one.
    @Test("the section names no second file")
    func noComparisonVocabulary() throws {
        for groups in try everyStateCombination() {
            for string in everyString(groups) {
                let lower = string.lowercased()
                #expect(!lower.contains("first file"), "comparison vocabulary in: \(string)")
                #expect(!lower.contains("second file"), "comparison vocabulary in: \(string)")
                #expect(!lower.contains("compared"), "comparison vocabulary in: \(string)")
            }
        }
    }
}
