import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport

/// What the integrated loudness surface must keep, asserted over the pure formatter and copy rather
/// than over a rendering — the discipline `TruePeakPresentationTests` already applies.
///
/// This is the number in the whole report a reader is most likely to arrive at with a target in mind:
/// −14, −16, −23, a platform's published figure. The surface's whole job is to state what was measured
/// and stop, and most of what follows exists to pin that it never does more than that.
@Suite("Feature — integrated loudness presentation")
struct LoudnessPresentationTests {

    // MARK: - Fixtures

    private func measurement(
        _ lufs: Double,
        weighting: LoudnessWeightingIdentifier = .publishedAt48kHz,
        algorithm: LoudnessAlgorithmIdentifier = .integratedBS1770v1
    ) throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: algorithm, weighting: weighting)
        ))
    }

    /// Every string a state can put on screen, including the spoken one.
    private func allStateText(_ presentation: LoudnessPresentation) -> [String] {
        guard let text = LoudnessCopy.text(for: presentation) else { return [] }
        return [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }
    }

    /// Every string a measurement can put on screen, including the method line and the spoken forms.
    private func allMeasurementText(_ measurement: LoudnessMeasurement) -> [String] {
        let row = LoudnessCopy.row(for: measurement)
        return [row.name, row.value, row.accessibilityLabel]
            + [LoudnessCopy.method(for: measurement), LoudnessCopy.methodAccessibilityLabel(for: measurement)]
    }

    /// Every string the surface can produce across every state, for the sweeps that must work from a
    /// complete inventory rather than from the branches one fixture happens to hit.
    private func everyStringTheSurfaceCanProduce() throws -> [String] {
        try [-23.04, -18.01, 0, 2.14, -70, -0.5].flatMap { try allMeasurementText(try measurement($0)) }
            + allMeasurementText(try measurement(-23.0, weighting: .derivedFrom48kHz))
            + allStateText(.loading) + allStateText(.absent)
            + allStateText(.failed(message: "The integrated loudness for this file could not be measured."))
            + [LoudnessCopy.title]
    }

    // MARK: - The unit and the precision, pinned at exact reference points

    /// One decimal, `LUFS`, and the reference points stated in the brief.
    @Test func theFormatterIsPinnedAtItsReferencePoints() {
        #expect(HumanFormat.loudnessFullScale(-23.04) == "-23.0 LUFS")
        #expect(HumanFormat.loudnessFullScale(-18.01) == "-18.0 LUFS")
        #expect(HumanFormat.loudnessFullScale(0) == "0.0 LUFS")
        #expect(HumanFormat.loudnessFullScale(2.14) == "+2.1 LUFS")
    }

    /// **LUFS, and never a decibel unit borrowed from a neighbouring section.** dBFS describes a stored
    /// sample and dBTP a reconstructed peak; quoting a gated, frequency-weighted programme level under
    /// either would claim a measurement that was never made.
    @Test func theUnitIsLUFSAndNeverDecibels() throws {
        for value in [-23.0, 0.0, 1.5, -60.0] {
            let formatted = HumanFormat.loudnessFullScale(value)
            #expect(formatted.hasSuffix(" LUFS"), "\(formatted) is not quoted in LUFS")
            #expect(!formatted.contains("dBFS"), "\(formatted) borrowed the sample peak's unit")
            #expect(!formatted.contains("dBTP"), "\(formatted) borrowed the true peak's unit")
            #expect(!formatted.contains("LKFS"), "\(formatted) used the other spelling of the unit")
        }
        // The sibling formatters are untouched: their own numbers, their own units.
        #expect(HumanFormat.decibelsFullScale(0.5) == "-6.02 dBFS")
        #expect(HumanFormat.decibelsTruePeak(0.5) == "-6.02 dBTP")
    }

    /// **One decimal, not two.** It is the display precision the measurement is qualified to; a second
    /// place would assert a resolution the ±0.1 agreement does not support.
    @Test func theValueIsShownToOneDecimal() {
        #expect(HumanFormat.loudnessFullScale(-23.0139) == "-23.0 LUFS")
        #expect(HumanFormat.loudnessFullScale(-23.06) == "-23.1 LUFS")
        #expect(!HumanFormat.loudnessFullScale(-23.0139).contains("-23.01"))
    }

    /// A programme genuinely above full scale reads **positive, explicitly signed, and unclamped** — the
    /// rule true peak already follows for the same reason: clamping would delete a real fact.
    @Test func aPositiveValueIsSignedAndNeverClamped() throws {
        #expect(HumanFormat.loudnessFullScale(2.14) == "+2.1 LUFS")
        #expect(HumanFormat.loudnessFullScale(0.4) == "+0.4 LUFS")
        #expect(HumanFormat.loudnessFullScale(2.14) != HumanFormat.loudnessFullScale(0))
        // And the row shows it as the formatter does, rather than clamping on the way through.
        #expect(LoudnessCopy.row(for: try measurement(2.14)).value == "+2.1 LUFS")
    }

    /// **No floor is invented.** Unlike the two decibel formatters, there is no `log10(0)` to reach an
    /// infinity through: the value is already logarithmic and finite by the domain type's own invariant,
    /// so a low reading is shown as itself rather than clipped to a convention.
    @Test func aLowValueIsShownAsItselfRatherThanFloored() {
        #expect(HumanFormat.loudnessFullScale(-70.0) == "-70.0 LUFS")
        #expect(HumanFormat.loudnessFullScale(-90.5) == "-90.5 LUFS")
        #expect(HumanFormat.loudnessFullScale(-130.0) == "-130.0 LUFS", "a dBFS-style floor leaked in")
    }

    // MARK: - Absence is words, never a number

    /// **The control the brief names first.** An unmeasurable file says so in words: never −70 (the
    /// standard's absolute gate, not a result), never an infinity, never a zero, never a dash alone.
    @Test func absenceIsStatedInWordsAndNeverAsAFabricatedValue() throws {
        let text = try #require(LoudnessCopy.text(for: .absent))
        #expect(try #require(text.headline).contains("Not computable"))
        #expect(try #require(text.detail).contains("Everything else in this report is unchanged."))

        for string in allStateText(.absent) {
            for fabricated in ["-70", "−70", "0.0 LUFS", "-∞", "−∞", "-inf"] {
                #expect(
                    !string.lowercased().contains(fabricated.lowercased()),
                    "the absent state showed “\(fabricated)”, which is not a measurement: \(string)"
                )
            }
            #expect(!string.contains("LUFS"), "an absent measurement was given a unit: \(string)")
        }
    }

    /// The mirror case, and the reason the one above cannot simply check for "no number": a value that
    /// *was* measured is shown, however low it is. −70 as a **reading** is a real answer; −70 as a
    /// stand-in for absence is not, and the two never collapse.
    @Test func aLowMeasuredValueIsShownRatherThanTreatedAsAbsence() throws {
        let row = LoudnessCopy.row(for: try measurement(-70.2))
        #expect(row.value == "-70.2 LUFS")
        #expect(!row.accessibilityLabel.contains("Not computable"))
    }

    /// The absent sentence covers every cause the flow collapses into it, and **attributes none of
    /// them**: the state does not carry the reason, so the words must not claim one.
    @Test func theAbsentSentenceNamesNoSingleCause() throws {
        let detail = try #require(LoudnessCopy.text(for: .absent)?.detail)
        #expect(detail.contains("Either"), "the disjunction was stated as a fact")
        #expect(detail.contains("or"))
        for internals in ["400 ms", "gating block", "absolute gate", "-70", "22,050", "unsupported"] {
            #expect(!detail.contains(internals), "an internal cause was asserted: \(detail)")
        }
    }

    // MARK: - The method travels with the value

    /// The visible half of "the methodology is recorded with the result" — stated in plain words, from
    /// the measurement's own record.
    @Test func theMethodIsStatedInWordsBesideTheValue() throws {
        let line = LoudnessCopy.method(for: try measurement(-23.0))
        #expect(line.contains("K-weighting"))
        #expect(line.contains("programme gating"))
        #expect(line.contains("whole file"))
        // Not the raw identifiers, and not the constants behind them.
        #expect(!line.contains("_"))
        #expect(!line.contains("400"))
        #expect(!line.contains("-70"))
    }

    /// **The two known weightings read identically, deliberately.** The derived coefficients exist to
    /// reproduce the published response, and the measurement's rate-invariance is demonstrated — so a
    /// line that varied by rate would suggest the two numbers mean different things. The distinction is
    /// exported, where it is an audit fact rather than a caption.
    @Test func thePublishedAndDerivedWeightingsAreDescribedTheSameWay() throws {
        let published = LoudnessCopy.method(for: try measurement(-23.0, weighting: .publishedAt48kHz))
        let derived = LoudnessCopy.method(for: try measurement(-23.0, weighting: .derivedFrom48kHz))
        #expect(published == derived)
        for line in [published, derived] {
            for leak in ["48 k", "44.1", "derived", "published", "rediscretised", "prototype"] {
                #expect(!line.lowercased().contains(leak.lowercased()), "the weighting's provenance surfaced: \(line)")
            }
        }
    }

    /// An identity this surface does **not** recognise is named verbatim rather than described with the
    /// known one's words — the precedent true peak set for the case where a guess would mislead most.
    @Test func anUnrecognisedIdentityIsNotDescribedWithBorrowedWords() throws {
        let weighting = LoudnessWeightingIdentifier(rawValue: "some-future-weighting")
        let line = LoudnessCopy.method(for: try measurement(-23.0, weighting: weighting))
        #expect(line.contains("some-future-weighting"))
        #expect(!line.contains("K-weighting"), "an unknown weighting was described as the known one")

        let algorithm = LoudnessAlgorithmIdentifier(rawValue: "some-future-algorithm")
        let other = LoudnessCopy.method(for: try measurement(-23.0, algorithm: algorithm))
        #expect(other.contains("some-future-algorithm"))
        #expect(!other.contains("programme gating"), "an unknown algorithm was described as the known one")
    }

    // MARK: - No verdict, and no target

    /// **The sweep the brief names, over every string the surface can produce.** This is the metric that
    /// attracts a judgement, and the words below are the ones it attracts.
    @Test func noLoudnessTextTurnsAValueIntoAVerdict() throws {
        let phrases = [
            "too loud", "too quiet", "loud enough", "quiet enough", "streaming ready", "broadcast ready",
            "you should", "consider ", "we recommend", "turn it down", "turn it up",
        ]
        let words: Set<String> = [
            "loud", "quiet", "hot", "good", "bad", "better", "worse", "poor", "excessive", "low", "high",
            "compliant", "conformant", "certified", "compliance", "pass", "fail", "normalise", "normalize",
            "normalisation", "normalization", "target", "recommended", "ready", "safe", "unsafe", "correct",
            "incorrect", "quality", "problematic", "healthy", "damaged", "warning",
        ]

        for text in try everyStringTheSurfaceCanProduce() {
            let lowered = text.lowercased()
            for phrase in phrases {
                #expect(!lowered.contains(phrase), "a verdict, not a measurement, in: \(text)")
            }
            // Word-split rather than substring: “loudness” legitimately contains “loud”, and it is the
            // name of the thing being measured.
            let found = Set(lowered.split { !$0.isLetter }.map(String.init)).intersection(words)
            #expect(found.isEmpty, "judgement word(s) \(found.sorted()) in: \(text)")
        }
    }

    /// **No platform, and no target level — including R 128's own −23.0 LUFS**, which is a delivery
    /// requirement someone imposes on a file, never a property this file has.
    @Test func noLoudnessTextNamesAPlatformOrATargetLevel() throws {
        let platforms = ["spotify", "apple music", "youtube", "tidal", "amazon", "netflix", "podcast"]
        let targets = ["-14", "−14", "-16", "−16", "-23", "−23", "-24", "−24"]

        for text in try everyStringTheSurfaceCanProduce() {
            let lowered = text.lowercased()
            for platform in platforms {
                #expect(!lowered.contains(platform), "a platform was named in: \(text)")
            }
            // The *row* legitimately shows a measured −23.0; a target is a figure quoted in prose, so
            // only the non-value strings are swept for one.
            guard !text.hasSuffix(" LUFS"), !text.contains(", -"), !text.contains(", +") else { continue }
            for target in targets {
                #expect(!text.contains(target), "a target level was quoted in: \(text)")
            }
        }
    }

    /// **No standard is worn as a seal.** Naming a recommendation on screen would read as certification;
    /// the full identity travels on the wire instead, where it is an audit fact.
    @Test func noLoudnessTextClaimsConformanceToAStandard() throws {
        let claims = ["bs.1770", "bs1770", "itu", "ebu", "r128", "r 128", "tech 3341", "ebu mode", "standard"]
        for text in try everyStringTheSurfaceCanProduce() {
            for claim in claims {
                #expect(
                    !text.lowercased().contains(claim),
                    "“\(claim)” reads as a seal of quality, in: \(text)"
                )
            }
        }
    }

    /// The neighbouring measurements are never brought into this section: no delta against the true
    /// peak, no comparison with the RMS, nothing that invites a conclusion neither type supports.
    @Test func nothingIsComparedAgainstAnotherMeasurement() throws {
        for text in try everyStringTheSurfaceCanProduce() {
            let lowered = text.lowercased()
            for phrase in ["true peak", "sample peak", "rms", "higher than", "lower than", "versus", " vs "] {
                #expect(!lowered.contains(phrase), "the loudness was compared against something, in: \(text)")
            }
        }
    }

    /// No stable code, wire key, framework name or domain case name reaches the screen.
    @Test func noLoudnessTextLeaksAnInternalIdentifier() throws {
        let internals = [
            "unavailable", "cancelled", "LoudnessOutcome", "LoudnessAccumulator", "LoudnessMeasurement",
            "itu_r_bs1770", "integratedLoudness", "AVFoundation", "vDSP", "OSStatus", "NSError",
            "schemaVersion", "measurements",
        ]
        for text in try everyStringTheSurfaceCanProduce() {
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
        let loading = try #require(LoudnessCopy.text(for: .loading))
        #expect(loading.headline == "Preparing the integrated loudness…")
        #expect(loading.accessibilityLabel.hasPrefix("Integrated loudness."))

        let absent = try #require(LoudnessCopy.text(for: .absent))
        #expect(absent.headline == "Not computable for this file.")

        let message = "The integrated loudness for this file could not be measured."
        let failed = try #require(LoudnessCopy.text(for: .failed(message: message)))
        #expect(failed.headline == message, "the outcome's own message is shown, not a rewritten one")
        #expect(try #require(failed.detail).contains("not something read from the audio"))

        // A measurement has a row instead of a statement — the two are never both present.
        #expect(LoudnessCopy.text(for: .measurement(try measurement(-23.0))) == nil)
    }

    /// Cancellation has no presentation at all — the precedent every sibling analysis already set. A
    /// state for it would show a user's own action as a limitation of the file.
    @Test func thereIsNoVisibleCancelledState() {
        #expect(LoudnessState(.cancelled) == nil)
        #expect(LoudnessState(.unavailable) == .unavailable)
    }

    // MARK: - Accessibility

    /// The value and its unit are announced together, as one coherent sentence — task 8.3, and the rule
    /// true peak's row already follows.
    @Test func theRowIsAnnouncedAsOneSentenceCarryingTheUnit() throws {
        #expect(LoudnessCopy.row(for: try measurement(-23.04)).accessibilityLabel == "Integrated loudness, -23.0 LUFS")
        #expect(LoudnessCopy.row(for: try measurement(2.14)).accessibilityLabel == "Integrated loudness, +2.1 LUFS")
    }

    /// The method is spoken too — it is part of the measurement rather than decoration around it.
    @Test func theMethodIsAvailableToAnAssistiveReader() throws {
        let spoken = LoudnessCopy.methodAccessibilityLabel(for: try measurement(-23.0))
        #expect(spoken.hasPrefix("How it was measured."))
        #expect(spoken.contains("K-weighting"))
    }

    /// **No semantics differ by sign**, and nothing depends on colour: a positive reading is announced
    /// with the same name and the same shape as a negative one, and the state sentences carry their
    /// whole meaning in words.
    @Test func everyMeaningIsInTheWordsRatherThanTheSignOrTheColour() throws {
        let positive = LoudnessCopy.row(for: try measurement(2.14))
        let negative = LoudnessCopy.row(for: try measurement(-23.04))
        #expect(positive.name == negative.name, "a positive value was given a different name")
        #expect(positive.accessibilityLabel.hasPrefix("Integrated loudness, "))
        #expect(negative.accessibilityLabel.hasPrefix("Integrated loudness, "))

        // An absent measurement is a sentence, never a bare dash for a reader to interpret.
        let absent = try #require(LoudnessCopy.text(for: .absent))
        #expect(absent.accessibilityLabel.contains("Not computable"))
        #expect(absent.accessibilityLabel != "Integrated loudness, —")
    }

    // MARK: - The flow's state reaches this surface

    /// Every state the flow can hold has exactly one presentation, and none is invented on the way.
    @Test func everyFlowStateTranslatesToItsOwnPresentation() throws {
        let model = try measurement(-23.0)
        #expect(RootView.loudnessPresentation(for: .loading) == .loading)
        #expect(RootView.loudnessPresentation(for: .available(model)) == .measurement(model))
        #expect(RootView.loudnessPresentation(for: .unavailable) == .absent)
        #expect(RootView.loudnessPresentation(for: .failed(message: "boom")) == .failed(message: "boom"))
    }

    /// A result from an operation the user already replaced never reaches the surface: it is discarded
    /// at the flow, so there is no stale value for this section to show.
    @Test func aSupersededResultNeverReachesThisSurface() throws {
        #expect(LoudnessState(.cancelled) == nil)
        #expect(LoudnessState(.available(try measurement(-23.0))) == .available(try measurement(-23.0)))
    }
}
