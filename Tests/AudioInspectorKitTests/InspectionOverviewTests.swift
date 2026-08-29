import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R7's subject: **the section a reader lands on, built only from facts that already had an owner.**
//
// Every claim is asserted against the owner that produces it — `ReportPropertyFormatter`,
// `MeasurementsDisplay`, `WaveformCopy` — rather than retyped, so the overview cannot drift from the
// inspection it presents. The structural claims are read off the source in the shape R3, R4, R5 and R6
// established.

@Suite("Feature — the inspection overview")
struct InspectionOverviewTests {

    // MARK: - Fixtures

    /// Deliberately hostile: every property presentation state, a partial status, and warnings — so
    /// nothing below passes by only ever meeting a clean report.
    private func everyStateReport() -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: "interview-side-a.m4a",
                fileExtension: "m4a",
                sizeBytes: 8_421_376,
                modifiedAt: Date(timeIntervalSince1970: 1_749_718_980),
                source: .userSelectedLocalFile(
                    displayName: "interview-side-a.m4a", locationDisclosure: .omitted
                )
            ),
            properties: TechnicalProperties(
                container: .uncertain(value: "public.mpeg-4-audio", reason: "inferred from the file type"),
                duration: .available(372.51),
                sampleRate: .available(44_100),
                channelCount: .available(2),
                bitDepth: .unsupported(reason: "not defined for this codec"),
                codec: .available("aac"),
                declaredBitrate: .unavailable(reason: nil),
                estimatedBitrate: .failed(
                    PropertyFailure(code: PropertyFailureCode(rawValue: "bitrate_unreadable"),
                                    message: "unreadable")
                ),
                averageFileBitrate: .available(192_000)
            ),
            warnings: [
                InspectionWarning(code: .metadataSizeUnavailable, field: "size", kind: .unavailable,
                                  message: "The file size could not be read."),
                InspectionWarning(code: .propertyUnavailable, field: nil, kind: .uncertain,
                                  message: "The container was inferred rather than declared."),
            ],
            status: .partial(message: nil)
        )
    }

    private func cleanReport() -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: "clip.wav", fileExtension: "wav", sizeBytes: 1_024, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: "clip.wav", locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(
                container: .available("wav"), duration: .available(1.0),
                sampleRate: .available(44_100), channelCount: .available(2), bitDepth: .available(16),
                codec: .available("lpcm")
            ),
            warnings: [],
            status: .completed
        )
    }

    private func truePeak(_ peaks: [Float?] = [1.1]) throws -> TruePeakMeasurement {
        let method = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let channels = try peaks.map { peak in
            try #require(TruePeakMeasurement.Channel(
                sampleCount: peak == nil ? 0 : 44_100, truePeak: peak
            ))
        }
        return try #require(TruePeakMeasurement(channels: channels, method: method))
    }

    // MARK: - Reading the section's source

    private static var featureAnalysis: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis")
    }

    private func code(of file: String) throws -> [String] {
        try String(contentsOf: Self.featureAnalysis.appendingPathComponent(file), encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    private func section() throws -> [String] { try code(of: "InspectionOverviewView.swift") }

    // MARK: - 2.1 / 4.1 — the five blocks ADR-0026 §6 permits

    @Test("the overview presents the identity, the facts, the measurements, the drawing and the result")
    func theOverviewPresentsTheFiveBlocks() throws {
        let source = try section()
        for area in ["ReportSection(\"File\")", "ReportSection(\"Technical\")",
                     "ReportSection(\"Measurements\")", "ReportSection(WaveformCopy.title)",
                     "Text(\"Result\")"] {
            #expect(source.contains { $0.contains(area) }, "the overview is missing \(area)")
        }
    }

    // MARK: - 2.2 / 4.6 — the facts are the formatter's selection, not the view's

    /// **The selection lives with the formatter.** The overview reads `coreFacts(for:)` and nothing else,
    /// so it cannot pick, reorder, rename or omit a property — which is the only thing that could make
    /// this surface and Details disagree about the same file.
    @Test("the overview renders the formatter's core facts rather than choosing its own")
    func theFactsAreTheFormattersSelection() throws {
        let source = try section()
        #expect(source.contains { $0.contains("ReportPropertyFormatter.coreFacts(for: report.properties)") })
        for picked in ["\"Container\"", "\"Codec\"", "\"Sample rate\"", "\"Channel count\"",
                       "\"Bit depth\"", "\"Duration\"", "\"Declared bitrate\"",
                       "properties.sampleRate", "properties.codec", "properties.container"] {
            #expect(!source.contains { $0.contains(picked) }, "the overview reaches for \(picked) itself")
        }
    }

    /// The six ADR-0026 §6 names, in the formatter's own order, and **each one is the very row
    /// `displays(for:)` produced** — not a re-derivation of it.
    @Test("the core facts are six of the report's own rows, unchanged")
    func theCoreFactsAreTheReportsOwnRows() {
        for report in [everyStateReport(), cleanReport()] {
            let rows = ReportPropertyFormatter.displays(for: report.properties)
            let core = ReportPropertyFormatter.coreFacts(for: report.properties)
            #expect(core.map(\.name) == ["Container", "Codec", "Duration",
                                         "Sample rate", "Channel count", "Bit depth"])
            for fact in core {
                let owned = rows.first { $0.name == fact.name }
                #expect(owned == fact, "\(fact.name) is not the row the report produced")
            }
        }
    }

    /// **The three bitrates stay in Details.** They are three separate claims about a rate (ADR-0018),
    /// and a glance that carried all three would be the detail it exists to precede.
    @Test("the core facts carry no bitrate")
    func theCoreFactsCarryNoBitrate() {
        let core = ReportPropertyFormatter.coreFacts(for: everyStateReport().properties)
        #expect(!core.contains { $0.name.localizedCaseInsensitiveContains("bitrate") })
    }

    // MARK: - 4.3 — an absence is words, and it is not an omission

    /// A fact the file does not carry keeps its row and its state, so it is **stated** on the overview
    /// rather than silently missing — the difference between this and `summary(for:)`, which drops it.
    @Test("a fact with no value keeps its row and states its state in words")
    func anAbsentFactIsStatedRatherThanDropped() throws {
        let core = ReportPropertyFormatter.coreFacts(for: everyStateReport().properties)
        let depth = try #require(core.first { $0.name == "Bit depth" })
        #expect(depth.value == nil)
        #expect(depth.state == .notDefinedByFormat)
        #expect(depth.state.label != nil, "the state has no words to state")

        // An unreliable reading stays distinguishable from one the format does not define.
        let container = try #require(core.first { $0.name == "Container" })
        #expect(container.state == .readButUnreliable)
        #expect(container.state != depth.state)
    }

    // MARK: - 2.3 — one fact per measurement, in the copy owner's own order

    /// The four displays are the ones the Measurements section is built from, in the same order, through
    /// the same call — so a figure cannot differ between the two surfaces.
    @Test("the overview takes the measurements' own first row, and ranks nothing")
    func theMeasurementsAreAPrefixNotAChoice() throws {
        let source = try section()
        #expect(source.contains { $0.contains("MeasurementsDisplay.groups(") })
        #expect(source.contains { $0.contains("measurement.rows.first") })
        // The label is the fact's own name, so a figure never appears under a name that does not
        // identify it — "Signal levels: -3.00 dBFS" does not say which level that is.
        #expect(source.contains { $0.contains("name: row.name") })
        #expect(!source.contains { $0.contains("name: measurement.title,\n") })
        // No method line and no per-channel breakdown reach the glance.
        for detail in ["method", "DisclosureGroup", "rows[1]", "rows.dropFirst"] {
            #expect(!source.contains { $0.contains(detail) }, "the overview carries \(detail)")
        }
        // Nothing describes a measurement as more important than another.
        // `headline` is deliberately absent from this list: it is the copy owners' own field name for
        // the sentence a measurement shows in place of rows, not a claim that anything is foremost.
        for ranking in ["principal", "notable", "foremost", "primary metric", "key metric"] {
            #expect(!source.contains { $0.localizedCaseInsensitiveContains(ranking) },
                    "the overview ranks a measurement as \(ranking)")
        }

        let groups = MeasurementsDisplay.groups(
            signalLevelMetrics: .loading,
            truePeak: .measurement(try truePeak()),
            loudness: .absent,
            programmeBandwidth: .loading
        )
        let displays = groups.flatMap(\.measurements)
        #expect(displays.count == 4, "a measurement is dropped before it reaches the overview")
        // The one that measured shows a figure; the ones that did not show their own sentence, and
        // neither is presented as the other.
        let peak = try #require(displays.first { $0.title == TruePeakCopy.title })
        #expect(peak.rows.first?.value != nil)
        // **The row's name identifies the fact; the measurement's does not always.** This is why the
        // overview labels the row rather than the measurement.
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 44_100, peakSample: 0.708, rms: 0.3, dcOffset: 0.002, clippedSampleCount: 0))
        let metrics = try #require(SignalLevelMetrics(
            channels: [channel], overallPeakSample: 0.708, overallRMS: 0.3,
            overallDCOffset: 0.002, overallClippedSampleCount: 0))
        let levels = MeasurementsDisplay.display(for: SignalLevelMetricsPresentation.metrics(metrics))
        #expect(levels.rows.first?.name != levels.title,
                "the measurement's title would have identified the figure on its own")
        #expect(levels.rows.first?.name == "Peak sample")

        let absent = try #require(displays.first { $0.title == LoudnessCopy.title })
        #expect(absent.rows.isEmpty)
        #expect(absent.state?.headline != nil)
        #expect(absent.isReadFailure == false, "an absence is presented as a failure")
    }

    // MARK: - 2.4 — identity, and never a location

    @Test("the identity is presented and no location is disclosed")
    func theIdentityCarriesNoLocation() throws {
        let source = try section()
        for location in ["url", "URL", "path", "absoluteString", "standardizedFileURL", "bookmark"] {
            #expect(!source.contains { $0.contains(location) },
                    "the overview reaches for \(location), which would disclose where the file is")
        }
        #expect(source.contains { $0.contains("\"User-selected local file (location omitted)\"") })

        var literals: [String] = []
        for line in source {
            literals += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(literals.count > 8, "the sweep covered \(literals.count) strings")
        for literal in literals {
            for shape in ["/", "~", "file:", "Users", "Volumes", "\\\\"] {
                #expect(!literal.contains(shape),
                        "\"\(literal)\" looks like a location, and this surface may not carry one")
            }
        }
    }

    // MARK: - 2.5 — the result is the report's own, over the whole report

    /// It is the report's account of **its own reading**, so it is derived from every property rather
    /// than from the six shown above it — narrowing it would invent a second, quieter outcome.
    @Test("the result is the report's own statement over all its properties")
    func theResultIsTheReportsOwn() throws {
        let source = try section()
        #expect(source.contains { $0.contains("ReportPropertyFormatter.outcome(") })
        #expect(source.contains { $0.contains("ReportPropertyFormatter.displays(for: report.properties)") })
        #expect(!source.contains { $0.contains("outcome(for: report.status, properties: coreFacts") })
    }

    // MARK: - 2.6 / 2.7 / 4.5 — the drawing is compact, reused, and still

    @Test("the drawing reuses the envelope at a compact fixed size, and is not a control")
    func theDrawingIsCompactAndStill() throws {
        let source = try section()
        #expect(source.contains { $0.contains("WaveformDrawing(envelope: envelope, sizing: .overviewCompact)") })
        // It is handed the presentation, not a state, an envelope source or a generator of its own.
        #expect(source.contains { $0.contains("let waveform: WaveformPresentation") })
        for recomputing in ["WaveformEnvelope(", "buckets.map", "stride(", "Accumulator", "decode",
                            "AVAudio", "normalis", "normaliz", "maximum(", "scale"] {
            #expect(!source.contains { $0.contains(recomputing) },
                    "the overview \(recomputing)s the envelope rather than reusing it")
        }
        // Nothing on this surface is a control.
        for control in ["Button", "onTapGesture", "gesture(", "NavigationLink", "onHover",
                        "DisclosureGroup", "TapGesture", "DragGesture", "focusable", ".onKeyPress"] {
            #expect(!source.contains { $0.contains(control) }, "the overview carries \(control)")
        }
    }

    /// The compact strip is smaller than the report page's, and the workspace sizings R5 budgeted are
    /// untouched by this slice.
    @Test("the compact sizing is fixed, smaller than the page's, and changes no other sizing")
    func theCompactSizingIsItsOwn() {
        #expect(WaveformPlotSizing.overviewCompact.minimum == WaveformPlotSizing.overviewCompact.maximum,
                "the overview's drawing is not a fixed strip")
        #expect(WaveformPlotSizing.overviewCompact.maximum < WaveformPlotSizing.reportPage.maximum,
                "the overview's drawing is not compact")
        #expect(WaveformPlotSizing.reportPage == .fixed(96))
        #expect(WaveformPlotSizing.workspaceSingle == WaveformPlotSizing(minimum: 140, maximum: 420))
        #expect(WaveformPlotSizing.workspaceLane == WaveformPlotSizing(minimum: 90, maximum: 260))
    }

    /// Loading, absence and failure are the drawing's own three answers, in `WaveformCopy`'s words, and
    /// none of them is drawn as silence.
    @Test("an absent or failed envelope is words, not a flat line")
    func anAbsentEnvelopeIsWords() throws {
        let source = try section()
        #expect(source.contains { $0.contains("WaveformCopy.text(for: waveform)") })
        // **Both lines are rendered.** An envelope carries no headline and puts what the drawing is in
        // the detail, so a surface that showed only headlines would leave the drawing unnamed.
        #expect(source.contains { $0.contains("if let headline = text.headline") })
        #expect(source.contains { $0.contains("if let detail = text.detail") })
        let envelopeText = WaveformCopy.text(for: .envelope(
            WaveformEnvelope(buckets: [WaveformBucket(minimum: -0.5, maximum: 0.5)!],
                             frameCount: 128, channelCount: 2)!
        ))
        #expect(envelopeText.headline == nil)
        #expect(envelopeText.detail != nil, "the drawn state would be the one state with no words")
        // The drawing exists only for an envelope with buckets; every other state falls to the words.
        #expect(source.contains { $0.contains("if case let .envelope(envelope) = waveform, !envelope.buckets.isEmpty") })
        for presentation in [WaveformPresentation.loading, .absent, .failed(message: "no")] {
            let text = WaveformCopy.text(for: presentation)
            #expect(text.headline != nil, "\(presentation) states nothing")
        }
    }

    // MARK: - 4.4 — the vocabulary sweep

    /// Everything this surface can render, plus its own string literals — because a word added straight
    /// into the view would never reach a copy owner.
    @Test("no wording on the overview states a verdict, a summary, a provenance or a count of notes")
    func theOverviewStatesNoVerdict() throws {
        var strings: [String] = []
        for report in [everyStateReport(), cleanReport()] {
            let rows = ReportPropertyFormatter.displays(for: report.properties)
            strings.append(ReportPropertyFormatter.outcome(for: report.status, properties: rows).text)
            strings += ReportPropertyFormatter.coreFacts(for: report.properties)
                .flatMap { [$0.name, $0.value, $0.accessibilityLabel].compactMap { $0 } }
        }
        strings += PropertyPresentationState.allCases.compactMap(\.label)
        strings += MeasurementsCopy.everyRenderableString
        for presentation in [WaveformPresentation.loading, .absent, .failed(message: "x")] {
            let text = WaveformCopy.text(for: presentation)
            strings += [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 }
        }
        for line in try section() {
            strings += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(strings.count > 40, "the sweep covered \(strings.count) strings")

        let forbidden = [
            "quality", "grade", "score", "rating", "verdict", "summary", "overall",
            "good", "bad", "better", "worse", "excellent", "poor", "acceptable",
            "original", "master", "remaster", "transcode", "transcoded", "upsample", "upsampled",
            "provenance", "authentic", "fake", "severity", "critical", "warnings", "issues", "problems",
        ]
        for string in strings {
            for term in forbidden {
                #expect(
                    string.range(of: "\\b\(term)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
                    "\"\(string)\" states \(term)"
                )
            }
        }
    }

    /// **The count ADR-0026 §6 permits is not here**, and §7's own last line is why: it cannot be held
    /// against `audio-file-inspection`'s *a note MUST NOT be counted … or summarised into a total*.
    /// Asserted structurally as well as by vocabulary, because a count reaches the reader as a digit
    /// long before it reaches a word.
    @Test("the overview states no count of the report's notes")
    func theOverviewCountsNoNotes() throws {
        let source = try section()
        for counting in ["warnings.count", "notes.count", "report.warnings", "displays(for: report.warnings)",
                         "Notes"] {
            #expect(!source.contains { $0.contains(counting) }, "the overview \(counting)")
        }
        // No literal on this surface carries a digit: a count added by hand would be one.
        for line in source {
            for literal in line.matches(of: /"[^"]*"/).map({ String($0.output) }) {
                #expect(!literal.contains { $0.isNumber }, "\(literal) carries a digit on a surface that counts nothing")
            }
        }
    }

    // MARK: - Accessibility, for this section

    /// Each row is one element carrying its whole sentence, the drawing is one element rather than one
    /// per bucket, and the result is a heading.
    @Test("each row and the drawing are one element each")
    func theOverviewReadsAsRows() throws {
        let source = try section()
        #expect(source.filter { $0.contains(".accessibilityElement(children: .ignore)") }.count >= 2)
        #expect(source.contains { $0.contains(".accessibilityAddTraits(.isHeader)") })
        #expect(source.contains { $0.contains("accessibilityLabel(text.accessibilityLabel)") })
    }
}
