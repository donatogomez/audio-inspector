import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

/// The comparison surface's vocabulary, asserted over the formatter rather than over a rendered view.
/// Pure values only — no SwiftUI, no snapshots (this project uses none), no flow.
@MainActor
@Suite("Presentation — comparison vocabulary")
struct ComparisonPresentationTests {

    private func reference(_ name: String, sizeBytes: Int? = 1_024) -> AudioFileReference {
        AudioFileReference(
            displayName: name,
            fileExtension: "wav",
            sizeBytes: sizeBytes,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
        )
    }

    private func report(
        _ name: String,
        _ properties: TechnicalProperties,
        warnings: [InspectionWarning] = [],
        status: InspectionStatus = .completed
    ) -> InspectionReport {
        InspectionReport(file: reference(name), properties: properties, warnings: warnings, status: status)
    }

    private let base = TechnicalProperties(
        container: .available("wav"),
        duration: .available(180.0),
        sampleRate: .available(44_100),
        channelCount: .available(2),
        bitDepth: .available(16),
        codec: .available("lpcm"),
        declaredBitrate: .available(1_411_200),
        estimatedBitrate: .uncertain(value: 1_411_000, reason: "estimated from size and duration")
    )

    private func comparison(_ second: TechnicalProperties) -> FileComparison {
        FileComparison(first: report("a.wav", base), second: report("b.wav", second))
    }

    private func row(_ name: String, in comparison: FileComparison) throws -> ComparisonRowDisplay {
        let rows = ComparisonFormatter.rows(for: comparison)
        return try #require(rows.first { $0.name == name }, "no row named \(name)")
    }

    // MARK: The rows, in order

    /// The order is the one coupling in the formatter — the outcomes are listed by hand beside two
    /// arrays built elsewhere — so it is pinned rather than trusted.
    @Test("every property appears once each, in the report's own order")
    func theRowsAreCorrect() {
        let names = ComparisonFormatter.rows(for: comparison(base)).map(\.name)
        #expect(names == [
            "Container", "Duration", "Sample rate", "Channel count",
            "Bit depth", "Codec", "Declared bitrate", "Estimated bitrate", "Average file bitrate",
        ])
    }

    /// Each row's outcome belongs to that row's property, which a mis-ordered list would break.
    @Test("each row carries its own property's outcome")
    func eachRowCarriesItsOwnOutcome() throws {
        var second = base
        second.sampleRate = .available(48_000)
        second.bitDepth = .unsupported(reason: "lossy")
        let result = comparison(second)

        #expect(try row("Sample rate", in: result).outcome == .different)
        #expect(try row("Container", in: result).outcome == .same)
        if case .notComparable = try row("Bit depth", in: result).outcome {} else {
            Issue.record("bit depth should not be comparable")
        }
    }

    // MARK: same / different

    @Test("two equal values read as the same")
    func equalValuesReadAsSame() throws {
        #expect(try row("Sample rate", in: comparison(base)).outcome.text == "Same")
    }

    @Test("two unequal values read as different, with both values still shown")
    func unequalValuesReadAsDifferent() throws {
        var second = base
        second.sampleRate = .available(48_000)
        let sampleRate = try row("Sample rate", in: comparison(second))

        #expect(sampleRate.outcome.text == "Different")
        #expect(sampleRate.first.value == "44.1 kHz")
        #expect(sampleRate.second.value == "48 kHz")
    }

    /// **No direction anywhere.** The word for two unequal values is flat, whichever way round they are.
    @Test("different reads identically whichever value is larger")
    func differentCarriesNoDirection() throws {
        var lower = base
        lower.sampleRate = .available(22_050)
        var higher = base
        higher.sampleRate = .available(96_000)

        #expect(try row("Sample rate", in: comparison(lower)).outcome.text == "Different")
        #expect(try row("Sample rate", in: comparison(higher)).outcome.text == "Different")
    }

    // MARK: incomparable — the reason names what each side was

    @Test("the second file having no value is said as such")
    func secondFileUnavailable() throws {
        var second = base
        second.declaredBitrate = .unavailable(reason: nil)
        #expect(
            try row("Declared bitrate", in: comparison(second)).outcome.text
                == "Not comparable — the second file does not carry this property."
        )
    }

    @Test("the first file having no value is said about the first file")
    func firstFileUnavailable() throws {
        var first = base
        first.declaredBitrate = .unavailable(reason: nil)
        let result = FileComparison(first: report("a.wav", first), second: report("b.wav", base))
        let rows = ComparisonFormatter.rows(for: result)
        let declared = try #require(rows.first { $0.name == "Declared bitrate" })

        #expect(
            declared.outcome.text
                == "Not comparable — the first file does not carry this property."
        )
    }

    @Test("neither file carrying a property is said once, not twice")
    func neitherFileCarriesIt() throws {
        var first = base
        first.declaredBitrate = .unavailable(reason: nil)
        var second = base
        second.declaredBitrate = .unavailable(reason: nil)
        let result = FileComparison(first: report("a.wav", first), second: report("b.wav", second))
        let declared = try #require(ComparisonFormatter.rows(for: result).first { $0.name == "Declared bitrate" })

        #expect(declared.outcome.text == "Not comparable — neither file carries this property.")
    }

    @Test("a format that cannot express a property says so, not that the two differ")
    func unsupportedIsSaidAsUnsupported() throws {
        var second = base
        second.bitDepth = .unsupported(reason: "a lossy codec has no PCM bit depth")
        let bitDepth = try row("Bit depth", in: comparison(second))

        #expect(bitDepth.outcome.text == "Not comparable — the second file's format cannot express it.")
        #expect(!bitDepth.outcome.text.contains("Different"))
    }

    @Test("a failed extraction is distinguishable from an absent value")
    func failedIsNotTheSameAsAbsent() throws {
        var failed = base
        failed.codec = .failed(PropertyFailure(code: .propertyReadError, message: "boom"))
        var absent = base
        absent.codec = .unavailable(reason: nil)

        let failedText = try row("Codec", in: comparison(failed)).outcome.text
        let absentText = try row("Codec", in: comparison(absent)).outcome.text

        #expect(failedText == "Not comparable — the second file's value could not be read.")
        #expect(absentText == "Not comparable — the second file does not carry this property.")
        #expect(failedText != absentText)
    }

    /// Two sides in **different** situations are both named, rather than collapsed into one phrase.
    @Test("a mixed gap names both sides")
    func aMixedGapNamesBothSides() throws {
        var first = base
        first.bitDepth = .failed(PropertyFailure(code: .propertyReadError, message: "boom"))
        var second = base
        second.bitDepth = .unsupported(reason: "lossy")
        let result = FileComparison(first: report("a.wav", first), second: report("b.wav", second))
        let bitDepth = try #require(ComparisonFormatter.rows(for: result).first { $0.name == "Bit depth" })

        #expect(
            bitDepth.outcome.text
                == "Not comparable — the first file's value could not be read and the second file's format cannot express it."
        )
    }

    // MARK: The estimated-bitrate case, which the values must survive

    /// **The case the design insists on.** Two estimates cannot be compared — and both numbers stay on
    /// screen, each still labelled as read-but-unreliable. Nothing says *Same*, nothing says
    /// *Different*, and nothing is hidden.
    @Test("two uncertain estimates keep their values and are not called the same or different")
    func uncertainEstimatesKeepTheirValues() throws {
        var second = base
        second.estimatedBitrate = .uncertain(value: 1_410_000, reason: "estimated from size and duration")
        let estimated = try row("Estimated bitrate", in: comparison(second))

        #expect(estimated.outcome.text == "Not comparable — neither value is reliable.")
        #expect(estimated.first.value != nil)
        #expect(estimated.second.value != nil)
        #expect(estimated.first.state == .readButUnreliable)
        #expect(estimated.second.state == .readButUnreliable)
        #expect(estimated.outcome.text != "Same")
        #expect(estimated.outcome.text != "Different")
    }

    /// Even two identical estimates keep both numbers and refuse to agree.
    @Test("two identical estimates still keep both numbers")
    func identicalEstimatesStillShowBoth() throws {
        let estimated = try row("Estimated bitrate", in: comparison(base))
        #expect(estimated.outcome.text == "Not comparable — neither value is reliable.")
        #expect(estimated.first.value == estimated.second.value)
        #expect(estimated.first.value != nil)
    }

    // MARK: Accessibility

    @Test("a row is announced as one sentence with both values and the outcome")
    func aRowIsAnnouncedAsOneSentence() throws {
        var second = base
        second.sampleRate = .available(48_000)
        let sampleRate = try row("Sample rate", in: comparison(second))

        #expect(
            sampleRate.accessibilityLabel
                == "Sample rate. First file: 44.1 kHz. Second file: 48 kHz. Different"
        )
    }

    @Test("an incomparable row announces the reason, not a blank")
    func anIncomparableRowAnnouncesItsReason() throws {
        var second = base
        second.bitDepth = .unsupported(reason: "lossy")
        let bitDepth = try row("Bit depth", in: comparison(second))

        #expect(bitDepth.accessibilityLabel.contains("Not comparable"))
        #expect(bitDepth.accessibilityLabel.contains("First file: 16-bit"))
        #expect(bitDepth.accessibilityLabel.contains("Not defined by this format"))
    }

    /// A side with no value still says what it was, so nothing is announced as an empty gap.
    @Test("a side with no value announces its state rather than nothing")
    func aSideWithNoValueStillSaysSomething() throws {
        var second = base
        second.codec = .unavailable(reason: nil)
        let codec = try row("Codec", in: comparison(second))

        #expect(ComparisonRowDisplay.sideText(codec.second) == "Not present in the file")
        #expect(!ComparisonRowDisplay.sideText(codec.second).isEmpty)
    }

    // MARK: What the wording must never contain

    /// **The prohibition, checked over every outcome the formatter can produce**, not over a chosen
    /// few: every pairing of the five property states across both sides, on every one of the eight
    /// fields.
    @Test("no outcome anywhere uses ranking, direction or aggregate wording")
    func noOutcomeUsesForbiddenWording() {
        let forbidden = [
            "better", "worse", "best", "worst", "higher", "lower", "improved", "reduced",
            "winner", "preferred", "quality", "score", "similar", "%", "match",
            "mostly", "significant", "minor", "upgrade", "downgrade",
        ]

        let states: [Property<Int>] = [
            .available(1),
            .unavailable(reason: nil),
            .unsupported(reason: "x"),
            .uncertain(value: 1, reason: "x"),
            .failed(PropertyFailure(code: .propertyReadError, message: "x")),
        ]

        // Every distinct sentence the vocabulary can produce for a property: all 25 pairings of the
        // five states, which is every outcome that can ever be rendered in the outcome column.
        var outcomes: Set<String> = []
        for first in states {
            for second in states {
                outcomes.insert(ComparisonFormatter.outcome(PropertyComparison(first: first, second: second)).text)
            }
        }

        // The surrounding copy, minus the subtitle — see below.
        let fixedCopy = [
            ComparisonCopy.title, ComparisonCopy.loading,
            ComparisonCopy.contextTitle, ComparisonCopy.contextDetail,
            ComparisonCopy.firstFile, ComparisonCopy.secondFile,
            ComparisonCopy.outcomeColumn, ComparisonCopy.failedHeadline,
        ]

        for text in outcomes.union(fixedCopy) {
            for word in forbidden {
                #expect(
                    !text.lowercased().contains(word),
                    "\"\(text)\" contains the forbidden word \"\(word)\""
                )
            }
        }
    }

    /// **The subtitle is exempt from the scan above, and deliberately so.**
    ///
    /// It contains the word *better* — inside the sentence that says the comparison does **not** say
    /// which file is better. A blunt substring scan cannot tell a claim from its denial, and weakening
    /// the disclaimer to satisfy the scan would be exactly backwards. So the subtitle is asserted for
    /// what it must contain instead, and the scan covers the text that must never rank: the outcomes.
    @Test("the subtitle denies ranking rather than avoiding the word")
    func theSubtitleDeniesRanking() {
        #expect(ComparisonCopy.subtitle.contains("does not say which file is better"))
        // The denial is only meaningful if nothing else on the surface makes the claim, which is what
        // the outcome scan establishes.
        #expect(!ComparisonCopy.subtitle.lowercased().contains("score"))
        #expect(!ComparisonCopy.subtitle.lowercased().contains("%"))
    }

    /// And there is no count, percentage or summary of the comparison as a whole anywhere in the
    /// vocabulary — the formatter produces rows and nothing else.
    @Test("the vocabulary offers no aggregate of the comparison")
    func thereIsNoAggregate() {
        var second = base
        second.sampleRate = .available(48_000)
        second.channelCount = .available(1)
        let rows = ComparisonFormatter.rows(for: comparison(second))

        // One row per property, and no extra row summarising them.
        #expect(rows.count == ReportPropertyFormatter.displays(for: base).count)
        // The copy says what the section is and is not; it never counts.
        #expect(!ComparisonCopy.subtitle.contains("differences"))
        #expect(!ComparisonCopy.subtitle.contains("of 8"))
        #expect(!ComparisonCopy.subtitle.contains("of 9"))
    }

    /// The subtitle states the two things a comparison table most invites a reader to assume.
    @Test("the section says what it does not establish")
    func theSectionSaysWhatItDoesNotEstablish() {
        #expect(ComparisonCopy.subtitle.contains("does not say which file is better"))
        #expect(ComparisonCopy.subtitle.contains("same recording"))
    }
}
