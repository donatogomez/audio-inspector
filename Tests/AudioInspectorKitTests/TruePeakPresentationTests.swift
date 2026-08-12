import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport

/// What the true peak surface must keep, asserted over the pure formatter and copy rather than over a
/// rendering — the discipline `SignalLevelMetricsPresentationTests` already applies.
///
/// The measurement this section shows is the one a reader is most likely to misread as a verdict: a
/// number above full scale looks like a fault if the surface hints that it is one. Most of what follows
/// exists to pin that it never hints.
@Suite("Feature — true peak presentation")
struct TruePeakPresentationTests {

    // MARK: - Fixtures

    private func method(factor: Int = 8, filter: TruePeakFilterIdentifier = .polyphaseFIRv1) throws -> TruePeakMethod {
        try #require(TruePeakMethod(oversamplingFactor: factor, filter: filter))
    }

    private func measurement(_ peaks: [Float?], sampleCount: Int = 44_100) throws -> TruePeakMeasurement {
        let channels = try peaks.map { peak in
            try #require(TruePeakMeasurement.Channel(
                sampleCount: peak == nil ? 0 : sampleCount, truePeak: peak
            ))
        }
        let built = try method()
        return try #require(TruePeakMeasurement(channels: channels, method: built))
    }

    /// Every string a state can put on screen, including the spoken one.
    private func allStateText(_ presentation: TruePeakPresentation) -> [String] {
        guard let text = TruePeakCopy.text(for: presentation) else { return [] }
        return [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }
    }

    /// Every string a measurement can put on screen, including the method line and the spoken forms.
    private func allMeasurementText(_ measurement: TruePeakMeasurement) -> [String] {
        let rows = TruePeakCopy.rows(for: measurement)
        return rows.flatMap { [$0.name, $0.value, $0.detail, $0.accessibilityLabel].compactMap { $0 } }
            + [TruePeakCopy.method(for: measurement), TruePeakCopy.methodAccessibilityLabel(for: measurement)]
    }

    // MARK: - The unit, pinned at exact reference points

    /// dBTP, not dBFS — and the same reference points the dBFS formatter is pinned at, so the two can be
    /// compared line for line and differ **only** in the unit.
    @Test func theFormatterIsPinnedAtItsReferencePoints() {
        #expect(HumanFormat.decibelsTruePeak(1.0) == "0.00 dBTP")
        #expect(HumanFormat.decibelsTruePeak(0.5) == "-6.02 dBTP")
        #expect(HumanFormat.decibelsTruePeak(0.25) == "-12.04 dBTP")
    }

    /// **The unit is the whole point of a second formatter.** The arithmetic is identical to dBFS, which
    /// is why nothing but the unit may differ: a true peak shown as dBFS would claim it was the largest
    /// stored sample, which is a different measurement produced by a different method.
    @Test func theUnitIsDBTPAndNeverDBFS() {
        for amplitude: Float in [1.0, 0.5, 0.25, 1.1, 0.0] {
            let formatted = HumanFormat.decibelsTruePeak(amplitude)
            #expect(formatted.hasSuffix(" dBTP"), "\(formatted) is not quoted in dBTP")
            #expect(!formatted.contains("dBFS"), "\(formatted) borrowed the sample peak's unit")
        }
        // The sibling formatter is untouched: same number, its own unit.
        #expect(HumanFormat.decibelsFullScale(0.5) == "-6.02 dBFS")
    }

    /// A reconstruction above full scale is **kept, signed and unclamped**. This is the fact the whole
    /// measurement exists to reveal, and clamping it to `0.00` would delete the answer.
    @Test func aValueAboveFullScaleReadsPositiveAndIsNeverClamped() {
        #expect(HumanFormat.decibelsTruePeak(1.1) == "+0.83 dBTP")
        #expect(HumanFormat.decibelsTruePeak(1.5) == "+3.52 dBTP")
        // Not clamped to full scale, and not silently equal to it.
        #expect(HumanFormat.decibelsTruePeak(1.1) != HumanFormat.decibelsTruePeak(1.0))
    }

    /// **Measured silence floors; it does not read as minus infinity.** The project already has one floor
    /// convention and this reuses it rather than inventing a second.
    @Test func measuredSilenceFloorsRatherThanReadingAsInfinity() {
        let formatted = HumanFormat.decibelsTruePeak(0)
        #expect(formatted == "-120.00 dBTP")
        #expect(!formatted.contains("∞"))
        #expect(!formatted.lowercased().contains("inf"))
    }

    // MARK: - Absence is not a measured zero

    /// A file with no audio frames has **no maximum**, and says so in the project's existing words —
    /// never `0.00 dBTP`, and never the floor, both of which would claim a measurement that never
    /// happened.
    @Test func aFileWithNoFramesIsNotComputableRatherThanZero() throws {
        let rows = TruePeakCopy.rows(for: try measurement([nil, nil]))
        let row = try #require(rows.first)

        #expect(row.value == nil)
        #expect(row.detail == "Not computable — this file has no audio frames.")
        #expect(row.detail == TruePeakCopy.notComputable)
        for text in allMeasurementText(try measurement([nil, nil])) {
            #expect(!text.contains("0.00 dBTP"), "an absent measurement was shown as a measured zero: \(text)")
            #expect(!text.contains("-120.00 dBTP"), "an absent measurement was shown as the silence floor: \(text)")
        }
    }

    /// The mirror case, and the reason the one above cannot simply check for "no number": a genuinely
    /// silent file **was** measured, so it reports a real, floored value.
    @Test func genuineSilenceIsMeasuredAndFloored() throws {
        let rows = TruePeakCopy.rows(for: try measurement([0.0, 0.0]))
        let row = try #require(rows.first)

        #expect(row.value == "-120.00 dBTP")
        #expect(row.detail != TruePeakCopy.notComputable)
        // The two cases must not collapse into one another.
        let absent = try #require(TruePeakCopy.rows(for: try measurement([nil, nil])).first)
        #expect(row.value != absent.value)
        #expect(row.detail != absent.detail)
    }

    // MARK: - Overall and channels

    /// Mono shows one value and **no per-channel line**: repeating the same number would be a wall of
    /// digits with no new information.
    @Test func monoShowsOneValueAndNoChannelBreakdown() throws {
        let row = try #require(TruePeakCopy.rows(for: try measurement([0.5])).first)
        #expect(row.value == "-6.02 dBTP")
        #expect(row.detail == nil)
    }

    /// Stereo shows the breakdown, numbered and never named.
    @Test func stereoShowsEachChannelByNumber() throws {
        let row = try #require(TruePeakCopy.rows(for: try measurement([1.1, 0.5])).first)
        #expect(row.value == "+0.83 dBTP", "the overall value is the maximum of the channels")
        #expect(row.detail == "Channel 1: +0.83 dBTP · Channel 2: -6.02 dBTP")
    }

    /// Six channels, to prove the form generalises rather than being written for two — and that no
    /// layout is asserted for a file that declared none.
    @Test func sixChannelsAreNumberedAndNeverNamed() throws {
        let row = try #require(TruePeakCopy.rows(for: try measurement([0.5, 0.5, 0.5, 0.5, 0.5, 1.0])).first)
        #expect(row.value == "0.00 dBTP")
        let detail = try #require(row.detail)
        #expect(detail.contains("Channel 6: 0.00 dBTP"))
        for name in ["Left", "Right", "Centre", "Center", "LFE", "Surround"] {
            #expect(!detail.contains(name), "“\(name)” asserts a channel layout the domain never reports")
        }
    }

    /// The overall value is the **measurement's own** maximum, not a second implementation here: a
    /// channel that carried no samples contributes nothing rather than dragging the maximum to zero.
    @Test func theOverallValueIsTheMeasurementsOwn() throws {
        let mixed = try measurement([nil, 0.708])
        let row = try #require(TruePeakCopy.rows(for: mixed).first)
        let overall = try #require(mixed.overallTruePeak)
        #expect(row.value == HumanFormat.decibelsTruePeak(overall))
        #expect(row.value == "-3.00 dBTP")
        #expect(try #require(row.detail).contains("Channel 1: not computable"))
    }

    // MARK: - The method travels with the value

    /// ADR-0006 requires the factor and the filter to be recorded with the result; this is the visible
    /// half. The factor comes from the measurement, so a value produced under a different method could
    /// not be described under this one.
    @Test func theMethodIsStatedInWordsBesideTheValue() throws {
        let line = TruePeakCopy.method(for: try measurement([0.5]))
        #expect(line.contains("8×"))
        #expect(line.lowercased().contains("polyphase fir"))
        #expect(line.lowercased().contains("between the stored samples"), "the reader is not told this is a reconstruction: \(line)")
        // Not the coefficients, and not the raw identifier with its underscores.
        #expect(!line.contains("_"))
        #expect(!line.lowercased().contains("kaiser"))
        #expect(!line.lowercased().contains("tap"))
    }

    /// A factor other than 8 is described as itself: the words follow the measurement, never a constant
    /// repeated in this file.
    @Test func theStatedFactorFollowsTheMeasurement() throws {
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: 0.5))
        let fourTimesMethod = try method(factor: 4)
        let fourTimes = try #require(TruePeakMeasurement(channels: [channel], method: fourTimesMethod))
        #expect(TruePeakCopy.method(for: fourTimes).contains("4×"))
        #expect(!TruePeakCopy.method(for: fourTimes).contains("8×"))
    }

    /// An identity this surface does not recognise is shown as it is rather than described with words
    /// that would be a guess — the case where inventing a description would mislead most.
    @Test func anUnrecognisedFilterIsNotDescribedWithBorrowedWords() throws {
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 10, truePeak: 0.5))
        let futureMethod = try method(filter: TruePeakFilterIdentifier(rawValue: "some-future-design"))
        let future = try #require(TruePeakMeasurement(channels: [channel], method: futureMethod))
        let line = TruePeakCopy.method(for: future)
        #expect(line.contains("some-future-design"))
        #expect(!line.lowercased().contains("polyphase fir"), "an unknown filter was described as the known one")
    }

    /// **No standard is claimed anywhere**, because this filter was designed to recorded parameters and
    /// validated against analytic truth and an independent meter rather than built from BS.1770 Annex
    /// 2's own coefficients (ADR-0019 §6).
    @Test func noTextClaimsConformanceToAStandard() throws {
        var texts = allMeasurementText(try measurement([1.1, 0.5])) + allMeasurementText(try measurement([nil, nil]))
        texts += allStateText(.loading) + allStateText(.absent)
            + allStateText(.failed(message: "The true peak for this file could not be measured."))
        let claims = ["bs.1770", "bs1770", "itu", "ebu", "r128", "compliant", "conformant", "certified", "standard"]
        for text in texts {
            for claim in claims {
                #expect(
                    !text.lowercased().contains(claim),
                    "“\(claim)” claims a conformance this project's own ADR forbids, in: \(text)"
                )
            }
        }
    }

    // MARK: - It states what was measured, never what it means

    /// The vocabulary this metric attracts, swept over every string it can produce — including the case
    /// that most invites a verdict, a reconstruction above full scale.
    @Test func noTruePeakTextTurnsAValueIntoAVerdict() throws {
        let phrases = [
            "clipping detected", "inter-sample clipping", "intersample clipping", "too hot",
            "bad master", "poor quality", "clipping is", "you should", "consider ",
        ]
        let words: Set<String> = [
            "clipping", "clipped", "unsafe", "safe", "hot", "distorted", "poor", "bad", "good", "better",
            "worse", "overs", "over", "quality", "fake", "transcode", "transcoded", "loud", "excessive",
            "problematic", "damaged", "healthy", "warning",
        ]
        var texts = allMeasurementText(try measurement([1.5, 1.1]))  // the value most likely to attract one
            + allMeasurementText(try measurement([0.5]))
            + allMeasurementText(try measurement([0.0, 0.0]))
            + allMeasurementText(try measurement([nil, nil]))
        texts += allStateText(.loading) + allStateText(.absent)
            + allStateText(.failed(message: "The true peak for this file could not be measured."))

        for text in texts {
            let lowered = text.lowercased()
            for phrase in phrases {
                #expect(!lowered.contains(phrase), "a diagnosis, not a measurement, in: \(text)")
            }
            let found = Set(lowered.split { !$0.isLetter }.map(String.init)).intersection(words)
            #expect(found.isEmpty, "judgement word(s) \(found.sorted()) in: \(text)")
        }
    }

    /// **The sample peak is never brought into this section.** No delta, no comparison, no "higher
    /// than": the two are different measurements, and the surface that put them side by side would be
    /// inviting a conclusion neither type can support.
    @Test func nothingIsComparedAgainstTheSamplePeak() throws {
        for text in allMeasurementText(try measurement([1.5, 1.1])) {
            let lowered = text.lowercased()
            for phrase in ["sample peak", "higher than", "exceeds", "above full scale", "difference", "versus", " vs "] {
                #expect(!lowered.contains(phrase), "the true peak was compared against something, in: \(text)")
            }
        }
    }

    /// No stable code, wire key, framework name or domain case name reaches the screen.
    @Test func noTruePeakTextLeaksAnInternalIdentifier() throws {
        let internals = [
            "unavailable", "cancelled", "TruePeakOutcome", "TruePeakAccumulator", "TruePeakMeasurement",
            "polyphase_fir_v1", "AVFoundation", "vDSP", "OSStatus", "NSError", "schemaVersion", "truePeak(",
        ]
        var texts = allMeasurementText(try measurement([1.1, 0.5])) + allMeasurementText(try measurement([nil, nil]))
        texts += allStateText(.loading) + allStateText(.absent)
            + allStateText(.failed(message: "The true peak for this file could not be measured."))
        for text in texts {
            #expect(!text.contains("_"), "underscored identifier surfaced: \(text)")
            for identifier in internals {
                #expect(
                    !text.lowercased().contains(identifier.lowercased()),
                    "internal identifier “\(identifier)” surfaced in: \(text)"
                )
            }
        }
    }

    // MARK: - States

    /// Each state says the state it is in, and none of them blames the file for a limit of the
    /// measurement.
    @Test func eachStateSaysWhatItIs() throws {
        let loading = try #require(TruePeakCopy.text(for: .loading))
        #expect(loading.headline == "Preparing the true peak…")
        #expect(loading.accessibilityLabel.hasPrefix("True peak."))

        let absent = try #require(TruePeakCopy.text(for: .absent))
        #expect(try #require(absent.headline).contains("No true peak for this file."))
        #expect(try #require(absent.detail).contains("Everything else in this report is unchanged."))

        let message = "The true peak for this file could not be measured."
        let failed = try #require(TruePeakCopy.text(for: .failed(message: message)))
        #expect(failed.headline == message, "the outcome's own message is shown, not a rewritten one")
        #expect(try #require(failed.detail).contains("not something read from the audio"))

        // A measurement has rows instead of a statement — the two are never both present.
        #expect(TruePeakCopy.text(for: .measurement(try measurement([0.5]))) == nil)
    }

    /// Cancellation has no presentation at all: the flow already collapses it, and a state for it would
    /// invite showing a user's own action as a limitation of the file.
    @Test func thereIsNoVisibleCancelledState() {
        #expect(TruePeakState(.cancelled) == nil)
        #expect(TruePeakState(.unavailable) == .unavailable)
    }

    // MARK: - Accessibility

    /// A row is announced as one coherent sentence: the metric, its value, and its per-channel detail.
    @Test func aRowIsAnnouncedAsOneSentence() throws {
        let row = try #require(TruePeakCopy.rows(for: try measurement([1.1, 0.5])).first)
        #expect(row.accessibilityLabel == "True peak, +0.83 dBTP, Channel 1: +0.83 dBTP · Channel 2: -6.02 dBTP")
    }

    /// The method is spoken too — it is part of the measurement rather than decoration around it.
    @Test func theMethodIsAvailableToAnAssistiveReader() throws {
        let spoken = TruePeakCopy.methodAccessibilityLabel(for: try measurement([0.5]))
        #expect(spoken.hasPrefix("How it was measured."))
        #expect(spoken.contains("8×"))
    }

    /// Every meaning is carried by words: the value that a coloured surface would flag is announced with
    /// the same wording as any other, and an absent one names its reason rather than reading as a dash.
    @Test func everyMeaningIsInTheWordsRatherThanTheColour() throws {
        let above = try #require(TruePeakCopy.rows(for: try measurement([1.5])).first)
        let below = try #require(TruePeakCopy.rows(for: try measurement([0.5])).first)
        #expect(above.name == below.name, "a value above full scale was given a different name")
        #expect(above.accessibilityLabel.contains("+3.52 dBTP"))

        // The absent case names its reason in words. The em dash inside that sentence is punctuation,
        // not a stand-in — what must never happen is the row being announced as a bare dash with no
        // reason at all, which is what this asserts.
        let absent = try #require(TruePeakCopy.rows(for: try measurement([nil])).first)
        #expect(absent.accessibilityLabel.contains("Not computable"))
        #expect(absent.accessibilityLabel.contains("no audio frames"))
        #expect(absent.value == nil, "an absent value must not be given a number")
        #expect(absent.accessibilityLabel != "True peak, —")
    }

    // MARK: - The flow's state reaches this surface

    /// Every state the flow can hold has exactly one presentation, and none is invented on the way.
    @Test func everyFlowStateTranslatesToItsOwnPresentation() throws {
        let model = try measurement([0.5])
        #expect(RootView.truePeakPresentation(for: .loading) == .loading)
        #expect(RootView.truePeakPresentation(for: .available(model)) == .measurement(model))
        #expect(RootView.truePeakPresentation(for: .unavailable) == .absent)
        #expect(RootView.truePeakPresentation(for: .failed(message: "boom")) == .failed(message: "boom"))
    }
}
