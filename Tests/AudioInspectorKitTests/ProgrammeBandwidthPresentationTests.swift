import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// Group 7 of `add-significant-bandwidth-measurement`: what the surface is allowed to say about a
// programme bandwidth, and — more of the work — what it must never say.
//
// The measurement is a **fact about the file's content**: how far up the programme reaches
// persistently, inside a declared budget. The surface answers that and nothing else. It never answers
// why it reaches that far, and never what that implies about where the file came from or what it is
// worth.

@Suite("Feature — programme bandwidth presentation")
struct ProgrammeBandwidthPresentationTests {

    private func measurement(
        _ frequency: Double?, resolution: Double = 23.4375, rate: Double = 48_000,
        windowFrames: Int = 2_048, identifier: String = SignificantBandwidthMethod.v1
    ) throws -> SignificantBandwidth {
        let method = try #require(SignificantBandwidthMethod(
            identifier: identifier, windowFrames: windowFrames,
            hopFrames: windowFrames / 4, sampleRate: rate
        ))
        let channel: SignificantBandwidth.Channel?
        if let frequency {
            channel = try #require(SignificantBandwidth.Channel(frequency: frequency, resolution: resolution))
        } else {
            channel = nil
        }
        return try #require(SignificantBandwidth(channels: [channel], method: method))
    }

    private func allStateText(_ presentation: SignificantBandwidthPresentation) -> [String] {
        guard let text = ProgrammeBandwidthCopy.text(for: presentation) else { return [] }
        return [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }
    }

    private func allMeasurementText(_ measurement: SignificantBandwidth) -> [String] {
        [ProgrammeBandwidthCopy.row(for: measurement), ProgrammeBandwidthCopy.resolutionRow(for: measurement)]
            .compactMap { $0 }
            .flatMap { [$0.name, $0.value, $0.accessibilityLabel] }
            + [
                ProgrammeBandwidthCopy.method(for: measurement),
                ProgrammeBandwidthCopy.methodAccessibilityLabel(for: measurement),
            ]
    }

    /// Every string the surface can produce, across every state and a spread of ordinary values.
    private func everyStringTheSurfaceCanProduce() throws -> [String] {
        try [8_000.0, 16_101.5625, 20_015.625, 23_976.5625, 24_000].flatMap { allMeasurementText(try measurement($0)) }
            + allMeasurementText(try measurement(21_000, resolution: 22.96875, rate: 44_100, windowFrames: 1_920))
            + allMeasurementText(try measurement(90_000, resolution: 23.4375, rate: 192_000, windowFrames: 8_192))
            + allStateText(.loading) + allStateText(.absent)
            + allStateText(.measurement(try measurement(nil)))
            + allStateText(.failed(message: "The programme bandwidth for this file could not be measured."))
            + [ProgrammeBandwidthCopy.title, ProgrammeBandwidthCopy.resolutionTitle]
    }

    // MARK: - The visible name

    /// **"Programme bandwidth"**, and none of the names that would overclaim. Each rejected one asserts
    /// a property of the world rather than describing a measurement: an "effective sample rate" claims
    /// the file should have been stored differently, a "real" or "true" bandwidth implies the declared
    /// one is false, and a "cut-off" asserts a filter nobody observed.
    @Test func theVisibleNameDescribesTheMeasurement() {
        #expect(ProgrammeBandwidthCopy.title == "Programme bandwidth")
        #expect(ProgrammeBandwidthCopy.resolutionTitle == "Analysis resolution")
    }

    /// The domain's own name is **not** the product's, and must not reach the surface.
    @Test func theSurfaceNeverSaysSignificantBandwidth() throws {
        for text in try everyStringTheSurfaceCanProduce() {
            #expect(
                !text.lowercased().contains("significant"),
                "the domain's internal name reached the surface in: \(text)"
            )
        }
    }

    // MARK: - Precision: never finer than the resolution

    /// **The rule, at the reference points.** The displayed value is rounded to the smallest power of
    /// ten that is at least the resolution, so no digit claims a distinction the bins cannot make.
    @Test func theValueNeverClaimsMorePrecisionThanTheResolution() {
        #expect(HumanFormat.programmeBandwidth(16_101.5625, resolution: 23.4375) == "16.1 kHz")
        #expect(HumanFormat.programmeBandwidth(20_015.625, resolution: 23.4375) == "20 kHz")
        #expect(HumanFormat.programmeBandwidth(8_000, resolution: 23.4375) == "8 kHz")
        #expect(HumanFormat.programmeBandwidth(24_000, resolution: 23.4375) == "24 kHz")
        // A finer grid earns a finer digit; a coarser one loses it. The rule is derived, not tabulated.
        #expect(HumanFormat.programmeBandwidth(16_101.5625, resolution: 5) == "16.1 kHz")
        #expect(HumanFormat.programmeBandwidth(16_101.5625, resolution: 400) == "16 kHz")
        #expect(HumanFormat.programmeBandwidth(16_101.5625, resolution: 4_000) == "20 kHz")
    }

    /// **The rule is the same at all five rates**, which is a consequence of the window being fixed in
    /// time rather than in samples: the resolution is about 23 Hz whether the file is 44.1 or 192 kHz,
    /// so the form is one decimal in kilohertz everywhere. A sample-locked window would make the
    /// displayed precision depend on the file's rate.
    @Test(
        "the displayed precision is identical at every supported rate",
        arguments: [(44_100.0, 1_920), (48_000.0, 2_048), (88_200.0, 3_840), (96_000.0, 4_096), (192_000.0, 8_192)]
    )
    func precisionIsConsistentAcrossRates(rate: Double, windowFrames: Int) throws {
        let resolution = rate / Double(windowFrames)
        let model = try measurement(16_101.5625, resolution: resolution, rate: rate, windowFrames: windowFrames)
        let row = try #require(ProgrammeBandwidthCopy.row(for: model))
        #expect(row.value == "16.1 kHz", "\(Int(rate)) Hz displayed \(row.value)")
        // At most one decimal in kilohertz: a second would be worth 10 Hz against a ~23 Hz grid.
        let digits = row.value.split(separator: ".").dropFirst().first.map { $0.prefix { $0.isNumber }.count } ?? 0
        #expect(digits <= 1, "\(Int(rate)) Hz showed \(digits) decimals for a \(resolution) Hz grid")
    }

    /// Nothing the formatter can be handed produces a digit finer than its grid — swept rather than
    /// spot-checked, because the rule is one-sided and a single counter-example would break it.
    @Test func noValueEverShowsADigitFinerThanItsGrid() {
        for resolution in [22.96875, 23.4375, 47.0, 93.75, 5.0, 1.0] {
            for frequency in stride(from: 1_000.0, through: 96_000.0, by: 137.0) {
                let text = HumanFormat.programmeBandwidth(frequency, resolution: resolution)
                let shown = text.replacingOccurrences(of: " kHz", with: "").replacingOccurrences(of: " Hz", with: "")
                let decimals = shown.split(separator: ".").dropFirst().first?.count ?? 0
                let quantum = text.hasSuffix("kHz") ? 1_000.0 / pow(10, Double(decimals)) : pow(10, -Double(decimals))
                #expect(
                    quantum >= resolution || decimals == 0,
                    "\(text) resolves \(quantum) Hz on a \(resolution) Hz grid"
                )
            }
        }
    }

    /// **The resolution is a quantity of its own, never an error bar.** ADR-0023 refuses to publish a
    /// false bound of uncertainty, and `±` is exactly that claim.
    @Test func theResolutionIsNeverShownAsAnUncertainty() throws {
        let model = try measurement(16_101.5625)
        let value = try #require(ProgrammeBandwidthCopy.row(for: model))
        let resolution = try #require(ProgrammeBandwidthCopy.resolutionRow(for: model))

        #expect(resolution.name == "Analysis resolution")
        #expect(resolution.value == "23 Hz")
        // Two rows, two names, no operator joining them.
        #expect(value.name != resolution.name)
        for text in try everyStringTheSurfaceCanProduce() {
            #expect(!text.contains("±"), "an uncertainty operator in: \(text)")
            #expect(!text.contains("+/-"), "an uncertainty operator in: \(text)")
            for word in ["uncertainty", "error", "tolerance", "margin", "accuracy", "precision", "confidence"] {
                #expect(
                    !text.lowercased().split(separator: " ").map({ $0.trimmingCharacters(in: .punctuationCharacters) }).contains(word),
                    "the resolution was described as \(word) in: \(text)"
                )
            }
        }
    }

    // MARK: - No verdict, and no comparison against the declared rate

    /// **The sweep task 7.2 names**, over every string the surface can produce, extended with the words
    /// this measurement attracts: a top frequency is the figure a reader is most likely to convert into
    /// a story about the file's origin.
    @Test func noProgrammeBandwidthTextTurnsAValueIntoAVerdict() throws {
        let phrases = [
            "low-pass", "low pass", "band limited", "band-limited", "real resolution", "true resolution",
            "hi-res", "high-res", "you should", "we recommend", "consider ", "sounds like",
            "was probably", "appears to be", "suggests that",
        ]
        let words: Set<String> = [
            "upsample", "upsampled", "upsampling", "upsampler", "downsample", "downsampled",
            "transcode", "transcoded", "transcoding", "codec", "mp3", "aac", "fake", "faked",
            "suspicious", "suspect", "lossy", "lossless", "wasted", "unnecessary", "genuine", "authentic",
            "cutoff", "rolloff", "filtered", "truncated", "capped", "limited",
            "good", "bad", "better", "worse", "poor", "excessive", "quality", "grade",
            "pass", "fail", "passed", "failed", "compliant", "certified", "warning", "problem",
            "problematic", "correct", "incorrect", "healthy", "damaged", "wrong", "real", "true",
        ]

        for text in try everyStringTheSurfaceCanProduce() {
            let lowered = text.lowercased()
            for phrase in phrases {
                #expect(!lowered.contains(phrase), "a verdict, not a measurement, in: \(text)")
            }
            // Word-split rather than substring: "bandwidth" contains "band", and "programme" contains
            // "gram". Only whole words are judgements.
            let found = Set(lowered.split { !$0.isLetter }.map(String.init)).intersection(words)
            #expect(found.isEmpty, "judgement word(s) \(found.sorted()) in: \(text)")
        }
    }

    /// **No platform, no format name, and no target.** The measurement is about this file's content, and
    /// naming anything it might be destined for or derived from would be an inference.
    @Test func noProgrammeBandwidthTextNamesAPlatformOrAFormat() throws {
        let named = [
            "spotify", "apple music", "youtube", "tidal", "amazon", "netflix", "bandcamp",
            "cd", "dvd", "vinyl", "redbook", "flac", "wav", "opus", "vorbis", "ogg",
        ]
        for text in try everyStringTheSurfaceCanProduce() {
            let tokens = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
            for name in named where !name.contains(" ") {
                #expect(!tokens.contains(name), "\(name) was named in: \(text)")
            }
            for name in named where name.contains(" ") {
                #expect(!text.lowercased().contains(name), "\(name) was named in: \(text)")
            }
        }
    }

    /// **Nothing on the surface compares the reading to the file's rate or to Nyquist**, and no string
    /// changes as the value approaches the top of the band. A reading at Nyquist is rendered exactly as
    /// one in the middle of the band.
    @Test func nothingComparesTheReadingAgainstTheDeclaredRate() throws {
        for text in try everyStringTheSurfaceCanProduce() {
            let tokens = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
            for word in ["nyquist", "sample", "samplerate", "rate", "half", "declared", "expected", "should"] {
                #expect(!tokens.contains(word), "the declared rate was invoked in: \(text)")
            }
        }

        // The wording is a pure function of the value, and the value is the only thing that changes:
        // mid-band and at-Nyquist readings produce the same shape of output.
        let midBand = try measurement(12_000)
        let atNyquist = try measurement(24_000)
        let midRow = try #require(ProgrammeBandwidthCopy.row(for: midBand))
        let topRow = try #require(ProgrammeBandwidthCopy.row(for: atNyquist))
        #expect(midRow.name == topRow.name)
        #expect(ProgrammeBandwidthCopy.method(for: midBand) == ProgrammeBandwidthCopy.method(for: atNyquist))
        #expect(ProgrammeBandwidthCopy.text(for: .measurement(midBand)) == nil)
        #expect(ProgrammeBandwidthCopy.text(for: .measurement(atNyquist)) == nil,
                "a reading at the top of the band gained a statement a mid-band one does not have")
    }

    /// Ordinary values are rendered as facts: a row, a resolution and a method line, and nothing else.
    @Test("an ordinary reading is a row and nothing more",
          arguments: [8_000.0, 16_101.5625, 20_015.625, 23_976.5625, 24_000])
    func ordinaryValuesAreJustRows(frequency: Double) throws {
        let model = try measurement(frequency)
        #expect(ProgrammeBandwidthCopy.row(for: model) != nil)
        #expect(ProgrammeBandwidthCopy.resolutionRow(for: model) != nil)
        #expect(ProgrammeBandwidthCopy.text(for: .measurement(model)) == nil, "a reading gained a statement")
    }

    // MARK: - The states

    @Test func loadingSaysSoAndClaimsNothing() {
        let text = ProgrammeBandwidthCopy.text(for: .loading)
        #expect(text?.headline == "Preparing the programme bandwidth…")
        #expect(text?.detail == nil)
    }

    /// **Absence in the report's existing not-computable phrasing** (task 7.3), and never as a number.
    @Test func absenceUsesTheReportsOwnNotComputablePhrasing() throws {
        let text = try #require(ProgrammeBandwidthCopy.text(for: .absent))
        #expect(text.headline == "Not computable for this file.")
        #expect(text.detail?.contains("Everything else in this report is unchanged.") == true)
        for forbidden in ["0 Hz", "0 kHz", "no bandwidth", "no high frequencies", "silence", "silent", "insufficient"] {
            let all = [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }.joined(separator: " ")
            #expect(!all.lowercased().contains(forbidden.lowercased()), "absence was said as \(forbidden)")
        }
    }

    /// A measurement that produced no reading is an absence **to a reader**, and is said in the same
    /// words — not as a zero, and not as a row with a dash.
    @Test func aMeasurementCarryingNoReadingReadsAsAnAbsence() throws {
        let empty = try measurement(nil)
        #expect(ProgrammeBandwidthCopy.row(for: empty) == nil)
        #expect(ProgrammeBandwidthCopy.resolutionRow(for: empty) == nil)
        #expect(ProgrammeBandwidthCopy.text(for: .measurement(empty)) == ProgrammeBandwidthCopy.text(for: .absent))
    }

    /// **A failure is a failure**, never folded into absence, and it carries the message it arrived
    /// with — the pattern every sibling measurement follows.
    @Test func failureKeepsItsOwnMessageAndIsNotAnAbsence() throws {
        let message = "The programme bandwidth for this file could not be measured."
        let text = try #require(ProgrammeBandwidthCopy.text(for: .failed(message: message)))
        #expect(text.headline == message)
        #expect(text.detail?.contains("not something read from the audio") == true)
        #expect(text.headline != ProgrammeBandwidthCopy.text(for: .absent)?.headline)
    }

    // MARK: - The method line

    /// Three ideas and only three: the highest frequency, that it is carried persistently, and that this
    /// is judged within 60 dB of the programme's own strongest spectral level.
    @Test func theMethodLineSaysWhatWasMeasuredWithoutReadingLikeASpecification() throws {
        let line = ProgrammeBandwidthCopy.method(for: try measurement(16_101.5625))
        #expect(line == "The highest frequency this programme carries persistently, within 60 dB of its "
            + "own strongest spectral level.")
        // The identity's internals belong on the wire, not on screen.
        for internalDetail in ["hann", "fft", "stft", "hop", "window", "bin", "-50", "10 %", "10%", "overlap", "2048"] {
            #expect(!line.lowercased().contains(internalDetail), "\(internalDetail) leaked into the method line")
        }
    }

    /// An identity this surface does not recognise is **named verbatim** rather than described with the
    /// known one's words — true peak's precedent, followed by loudness, and followed here.
    @Test func anUnknownMethodIsNamedRatherThanDescribed() throws {
        let model = try measurement(16_101.5625, identifier: "programme-bandwidth-experimental-v9")
        let line = ProgrammeBandwidthCopy.method(for: model)
        #expect(line.contains("programme-bandwidth-experimental-v9"))
        #expect(!line.contains("60 dB"), "an unrecognised method was described with the known one's words")
    }

    /// The raw identity is never shown for the method the surface **does** recognise: a reader gains
    /// nothing from a slug, and loudness sets the precedent of human words on screen.
    @Test func theRecognisedIdentityIsNeverShownRaw() throws {
        let line = ProgrammeBandwidthCopy.method(for: try measurement(16_101.5625))
        #expect(!line.contains(SignificantBandwidthMethod.v1))
    }

    // MARK: - Accessibility, structural only

    /// The value and its unit are announced together, in one sentence, with the resolution as its own
    /// sentence rather than appended to the value's (task 7.4, structural half).
    @Test func theValueAndItsUnitAreAnnouncedTogether() throws {
        let model = try measurement(16_101.5625)
        let value = try #require(ProgrammeBandwidthCopy.row(for: model))
        let resolution = try #require(ProgrammeBandwidthCopy.resolutionRow(for: model))
        #expect(value.accessibilityLabel == "Programme bandwidth, 16.1 kHz")
        #expect(resolution.accessibilityLabel == "Analysis resolution, 23 Hz")
    }

    /// Every state names the section first, so a reader who lands on the sentence knows what it is
    /// about — the shape loudness's own state text already uses.
    @Test("every state's spoken form names the section first",
          arguments: [SignificantBandwidthPresentation.loading, .absent, .failed(message: "It could not be measured.")])
    func spokenStatesNameTheSection(presentation: SignificantBandwidthPresentation) throws {
        let text = try #require(ProgrammeBandwidthCopy.text(for: presentation))
        #expect(text.accessibilityLabel.hasPrefix("Programme bandwidth."))
    }
}
