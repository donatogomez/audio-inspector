import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

/// Presentation-logic tests for the report view's property rows. Pure — no SwiftUI, no snapshots.
/// They assert the eight fields exist and that each `Property` state maps to a distinct, honest row
/// (no fabricated values; units only alongside a value).
@Suite("Feature — report property display")
struct ReportPropertyDisplayTests {

    private func mixedProperties() -> TechnicalProperties {
        TechnicalProperties(
            container: .available("wav"),
            duration: .available(10.5),
            sampleRate: .available(44_100),
            channelCount: .unavailable(reason: nil),
            bitDepth: .unsupported(reason: "lossy codec"),
            codec: .uncertain(value: "aac", reason: "inferred"),
            declaredBitrate: .failed(PropertyFailure(code: .propertyReadError, message: "boom")),
            estimatedBitrate: .uncertain(value: nil, reason: "cannot estimate")
        )
    }

    @Test func allEightPropertiesAreRepresentedInOrder() {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())
        #expect(displays.map(\.name) == [
            "Container", "Duration", "Sample rate", "Channel count",
            "Bit depth", "Codec", "Declared bitrate", "Estimated bitrate",
        ])
    }

    @Test func eachStateIsDistinctlyRepresented() {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())
        // Same eight distinctions as before, now as a closed presentation enum instead of free strings.
        #expect(displays.map(\.state) == [
            .measured, .measured, .measured, .notPresent,
            .notDefinedByFormat, .readButUnreliable, .couldNotBeRead, .readButUnreliable,
        ])
    }

    /// Only a cleanly measured value goes unlabelled; every other state says what it is, in words that
    /// describe the reading and never characterise the file.
    @Test func onlyMeasuredValuesCarryNoStateLabel() {
        #expect(PropertyPresentationState.measured.label == nil)
        for state in PropertyPresentationState.allCases where state != .measured {
            let label = state.label
            #expect(label != nil)
            #expect(label?.isEmpty == false)
        }
    }

    /// Values are self-contained — the unit is part of the value, never a separate wire name such as
    /// `hertz` — and every rounded form keeps its exact figure as detail.
    @Test func availableRowsAreReadableAndKeepTheExactFigure() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        // `wav` is not a resolvable type identifier, so it is shown unchanged rather than guessed at.
        let container = try #require(displays.first { $0.name == "Container" })
        #expect(container.value == "wav")
        #expect(container.detail == nil) // nothing to preserve: the name is the token

        let duration = try #require(displays.first { $0.name == "Duration" })
        #expect(duration.value == "0:10")
        #expect(duration.detail == "10.5 seconds")

        let sampleRate = try #require(displays.first { $0.name == "Sample rate" })
        #expect(sampleRate.value == "44.1 kHz")
        #expect(sampleRate.detail == "44,100 Hz")
    }

    @Test func absentStatesCarryNoValue() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        // unavailable → no value.
        let channels = try #require(displays.first { $0.name == "Channel count" })
        #expect(channels.value == nil)

        // unsupported → no value, reason surfaced.
        let bitDepth = try #require(displays.first { $0.name == "Bit depth" })
        #expect(bitDepth.value == nil)
        #expect(bitDepth.detail == "lossy codec")

        // failed → no value, and the human message only: the stable code stays in the JSON, where it
        // is the contract's identity, not something to read.
        let declared = try #require(displays.first { $0.name == "Declared bitrate" })
        #expect(declared.value == nil)
        #expect(declared.detail == "boom")
        #expect(declared.detail?.contains("property_read_error") == false)
    }

    @Test func uncertainWithValueKeepsTheReasonAndTheExactFigure() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        // uncertain WITH value → named codec, with the exact token preserved alongside the reason.
        let codec = try #require(displays.first { $0.name == "Codec" })
        #expect(codec.value == "AAC")
        #expect(codec.detail == "aac — inferred")

        // uncertain WITHOUT value → no value, reason kept.
        let estimated = try #require(displays.first { $0.name == "Estimated bitrate" })
        #expect(estimated.value == nil)
        #expect(estimated.detail == "cannot estimate")
    }

    @Test func uncertainNumericValueIsReadableAndKeepsItsExactFigure() throws {
        var properties = TechnicalProperties()
        properties.estimatedBitrate = .uncertain(value: 180_904, reason: "estimated")
        let displays = ReportPropertyFormatter.displays(for: properties)

        let estimated = try #require(displays.first { $0.name == "Estimated bitrate" })
        #expect(estimated.value == "180.9 kbps")
        #expect(estimated.detail == "180,904 bit/s — estimated")
    }

    // MARK: - Grouping and summary

    /// Grouping reorganises; it must never drop a row.
    @Test func everyPropertyAppearsInExactlyOneGroup() {
        let properties = mixedProperties()
        let all = ReportPropertyFormatter.displays(for: properties)
        let grouped = ReportPropertyFormatter.groups(for: properties).flatMap(\.properties)

        #expect(grouped.count == all.count)
        #expect(Set(grouped.map(\.name)) == Set(all.map(\.name)))
        #expect(Set(grouped.map(\.name)).count == grouped.count) // no row in two groups
    }

    @Test func groupsSeparateWhatTheFileIsFromHowItIsEncoded() {
        let groups = ReportPropertyFormatter.groups(for: mixedProperties())
        #expect(groups.map(\.name) == ["Format", "Encoding"])
        #expect(groups[0].properties.map(\.name) == ["Container", "Codec", "Duration"])
        #expect(groups[1].properties.map(\.name) == [
            "Sample rate", "Channel count", "Bit depth", "Declared bitrate", "Estimated bitrate",
        ])
    }

    /// The header summarises what was read; anything missing is left out rather than filled in.
    @Test func theSummaryOmitsWhatWasNotRead() {
        let report = InspectionReport(
            file: AudioFileReference(
                displayName: "clip.wav",
                fileExtension: "wav",
                sizeBytes: 8_421_376,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: "clip.wav", locationDisclosure: .omitted)
            ),
            properties: mixedProperties(), // channelCount is unavailable
            warnings: [],
            status: .partial(message: nil)
        )
        let summary = ReportPropertyFormatter.summary(for: report)

        #expect(summary.fileName == "clip.wav")
        #expect(summary.highlights == ["AAC", "44.1 kHz", "0:10", "8.4 MB"])
        #expect(!summary.highlights.contains { $0.contains("channel") }) // unavailable ⇒ absent
    }

    @Test func theSummaryIsEmptyOfHighlightsWhenNothingWasRead() {
        let report = InspectionReport(
            file: AudioFileReference(
                displayName: "unreadable.bin",
                fileExtension: nil,
                sizeBytes: nil,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: "unreadable.bin", locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(InspectionError(code: .fileUnreadable, message: "This file could not be inspected."))
        )
        let summary = ReportPropertyFormatter.summary(for: report)

        #expect(summary.fileName == "unreadable.bin")
        #expect(summary.highlights.isEmpty) // nothing invented to fill the header
    }

    // MARK: - Accessibility, colour and iconography (modelled as data, no snapshots)

    /// A row is announced as one sentence carrying everything it shows, in the same order.
    @Test func eachRowComposesOneAccessibilityLabel() throws {
        let displays = ReportPropertyFormatter.displays(for: mixedProperties())

        let sampleRate = try #require(displays.first { $0.name == "Sample rate" })
        #expect(sampleRate.accessibilityLabel == "Sample rate, 44.1 kHz, 44,100 Hz")

        // Absent values are not announced as empty: the state and reason carry the meaning.
        let bitDepth = try #require(displays.first { $0.name == "Bit depth" })
        #expect(bitDepth.accessibilityLabel == "Bit depth, Not defined by this format, lossy codec")

        for display in displays {
            #expect(!display.accessibilityLabel.isEmpty)
            #expect(display.accessibilityLabel.hasPrefix(display.name))
        }
    }

    @Test func warningsComposeOneAccessibilityLabel() {
        let warnings = ReportPropertyFormatter.displays(for: [
            InspectionWarning(code: .propertyUnsupported, field: "bitDepth", kind: .unsupported, message: "Not defined for this codec."),
            InspectionWarning(code: .metadataSizeUnavailable, field: nil, kind: .unavailable, message: "Size is unknown."),
        ])
        #expect(warnings[0].accessibilityLabel == "Bit depth, Not defined for this codec.")
        #expect(warnings[1].accessibilityLabel == "Size is unknown.") // no subject ⇒ no invented label
    }

    /// Only a failure of the reading is alerting. Anything else would tell the user their file is
    /// worse, which presentation may not say.
    @Test func onlyAReadFailureIsTreatedAsAlerting() {
        #expect(PropertyPresentationState.couldNotBeRead.isReadFailure)
        for state in PropertyPresentationState.allCases where state != .couldNotBeRead {
            #expect(!state.isReadFailure)
        }
    }

    /// A symbol marks the one distinction text alone conflates, and never appears without its label,
    /// so nothing depends on seeing it.
    @Test func symbolsAreLimitedToTheKindsOfAbsenceAndNeverStandAlone() {
        #expect(PropertyPresentationState.notDefinedByFormat.symbolName != nil)
        #expect(PropertyPresentationState.couldNotBeRead.symbolName != nil)
        #expect(PropertyPresentationState.measured.symbolName == nil)
        #expect(PropertyPresentationState.notPresent.symbolName == nil)
        #expect(PropertyPresentationState.readButUnreliable.symbolName == nil)

        for state in PropertyPresentationState.allCases where state.symbolName != nil {
            #expect(state.label != nil) // a symbol always has words beside it
        }
    }

    /// The whole presentation surface, swept for judgement words (invariant #4).
    @Test func noPresentedTextCharacterisesQuality() {
        let texts = ReportPropertyFormatter.displays(for: mixedProperties())
            .flatMap { [$0.name, $0.value, $0.detail, $0.state.label].compactMap { $0 } }
            + PropertyPresentationState.allCases.compactMap(\.label)
            + [
                InspectionOutcomeDisplay.allRead(count: 8).text,
                InspectionOutcomeDisplay.someNotRead(read: 6, total: 8).text,
            ]
        let forbidden = ["good", "bad", "better", "worse", "quality", "professional", "recommended", "poor"]
        for text in texts {
            for word in forbidden {
                #expect(!text.lowercased().contains(word))
            }
        }
    }

    /// The outcome talks about the reading, never about the audio, and never in enum names.
    @Test func theOutcomeDescribesTheReadingNotTheFile() {
        let properties = mixedProperties()
        let rows = ReportPropertyFormatter.displays(for: properties)

        let partial = ReportPropertyFormatter.outcome(for: .partial(message: nil), properties: rows)
        #expect(partial == .someNotRead(read: 3, total: 8))
        for name in ["completed", "partial", "failed"] {
            #expect(!partial.text.lowercased().contains(name))
        }

        let failed = ReportPropertyFormatter.outcome(
            for: .failed(InspectionError(code: .fileUnreadable, message: "This file could not be inspected.")),
            properties: rows
        )
        #expect(failed == .couldNotInspect(message: "This file could not be inspected."))
        #expect(!failed.text.contains("file_unreadable")) // the stable code stays in the JSON
    }

    // MARK: - The outcome is factual about the reading

    /// The remaining count is the arithmetic complement of what was read, so the sentence can never
    /// disagree with the rows on screen.
    @Test(arguments: [(0, 8, 8), (3, 8, 5), (7, 8, 1)])
    func theOutcomeStatesHowManyRemain(read: Int, total: Int, remaining: Int) {
        let text = InspectionOutcomeDisplay.someNotRead(read: read, total: total).text
        #expect(text.contains("\(read) of \(total)"))
        #expect(text.contains("remaining \(remaining)"))
    }

    /// `readButUnreliable` and `couldNotBeRead` are **not** absence: those properties were read, or an
    /// attempt failed. The sentence must not attribute a cause it has not established.
    @Test func theOutcomeAttributesNoCauseToTheUnreadProperties() {
        var properties = TechnicalProperties()
        properties.sampleRate = .available(44_100)                       // measured
        properties.codec = .uncertain(value: "aac", reason: "inferred")  // read, but unreliable
        properties.duration = .failed(PropertyFailure(code: .propertyReadError, message: "could not be read"))
        let rows = ReportPropertyFormatter.displays(for: properties)

        // The fixture really does contain the two states this guards against.
        #expect(rows.contains { $0.state == .readButUnreliable })
        #expect(rows.contains { $0.state == .couldNotBeRead })

        let text = ReportPropertyFormatter.outcome(for: .partial(message: nil), properties: rows).text

        // Claiming absence or undefinedness would be false for the two states above.
        for claim in ["not present", "not defined", "missing", "absent", "unavailable"] {
            #expect(!text.lowercased().contains(claim), "outcome asserts an unestablished cause: \(text)")
        }
    }

    /// The approved wording is part of the presentation contract, so it is pinned as well.
    @Test func theOutcomeUsesTheApprovedWording() {
        var properties = TechnicalProperties()
        properties.sampleRate = .available(44_100)
        let rows = ReportPropertyFormatter.displays(for: properties)
        let outcome = ReportPropertyFormatter.outcome(for: .partial(message: nil), properties: rows)

        #expect(outcome == .someNotRead(read: 1, total: 8))
        #expect(outcome.text == "Read 1 of 8 properties cleanly. Each of the remaining 7 shows what is known about it.")
    }

    /// No internal vocabulary and no judgement, across every shape the outcome can take.
    @Test func theOutcomeCarriesNoInternalVocabularyAndNoJudgement() {
        let texts = [
            InspectionOutcomeDisplay.allRead(count: 8).text,
            InspectionOutcomeDisplay.someNotRead(read: 3, total: 8).text,
            InspectionOutcomeDisplay.couldNotInspect(message: "This file could not be inspected.").text,
        ]
        let internalVocabulary = [
            "measured", "notpresent", "notdefinedbyformat", "readbutunreliable", "couldnotberead",
            "available", "unsupported", "uncertain", "completed", "partial", "_",
        ]
        let judgements = ["good", "bad", "better", "worse", "quality", "professional", "recommended", "poor"]

        for text in texts {
            for term in internalVocabulary {
                #expect(!text.lowercased().contains(term), "internal vocabulary in: \(text)")
            }
            for word in judgements {
                #expect(!text.lowercased().contains(word), "judgement in: \(text)")
            }
        }
    }
}
