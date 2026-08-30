import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R3's subject: **the report's secondary content, gathered into one section and unchanged by the move.**
//
// The facts are asserted against `ReportPropertyFormatter` rather than retyped, so the section cannot
// drift from the report it presents; the structural claims are read off the source, in the shape the
// earlier slices established.

@Suite("Feature — the report's details section")
struct ReportDetailsTests {

    // MARK: - Fixtures

    /// Deliberately hostile: every presentation state, a warning on a field and one without, and a
    /// partial status — so nothing below passes by only ever meeting a clean report.
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

    private func section() throws -> [String] { try code(of: "ReportDetailsView.swift") }

    // MARK: - 1.1 / 2.1 / 2.2 — the four bodies of content, and the report's own grouping

    @Test("the section presents the technical properties, the file, the notes and the result")
    func theSectionPresentsTheFourBodies() throws {
        let source = try section()
        for area in ["ReportSection(\"Technical\")", "ReportSection(\"File\")",
                     "ReportSection(\"Notes\")", "Text(\"Result\")"] {
            #expect(source.contains { $0.contains(area) }, "the section is missing \(area)")
        }
    }

    /// **The grouping is the report's, rendered — not re-decided.** The section reads
    /// `groups(for:)` and nothing else, so it cannot pick, reorder or omit a property.
    @Test("the section renders the report's own groups rather than choosing its own")
    func theGroupingIsTheReports() throws {
        let source = try section()
        #expect(source.contains { $0.contains("ReportPropertyFormatter.groups(for: report.properties)") })
        // It never reaches for a property by name, which is how a group would quietly be re-decided.
        for picked in ["\"Container\"", "\"Codec\"", "\"Sample rate\"", "\"Bit depth\"",
                       "\"Declared bitrate\"", "\"Duration\""] {
            #expect(!source.contains { $0.contains(picked) }, "the section picks \(picked) by name")
        }
    }

    /// Every property the report produces lands in exactly one group, and the two groups together are
    /// the whole of what `displays(for:)` produces. Asserted against the formatter, for a report that
    /// exercises every state.
    @Test("every property appears exactly once, in the group the report assigns it")
    func everyPropertyAppearsOnceInItsGroup() {
        for report in [everyStateReport(), cleanReport()] {
            let rows = ReportPropertyFormatter.displays(for: report.properties)
            let grouped = ReportPropertyFormatter.groups(for: report.properties).flatMap(\.properties)

            #expect(grouped.count == rows.count, "the grouping drops or duplicates a property")
            #expect(Set(grouped.map(\.name)).count == grouped.count, "a property is in two groups")
            #expect(Set(grouped.map(\.name)) == Set(rows.map(\.name)))
            for row in rows {
                #expect(grouped.contains(row), "\(row.name) changed on its way into a group")
            }
        }
    }

    // MARK: - 2.3 — absence is not zero, and a failure is not an absence

    /// The five states keep their own words. Nothing here substitutes a figure for a value the report
    /// does not have, and the two states that carry a symbol keep their label beside it.
    @Test("each presentation state keeps its own words")
    func eachStateKeepsItsWords() {
        #expect(PropertyPresentationState.measured.label == nil)
        #expect(PropertyPresentationState.notPresent.label == "Not present in the file")
        #expect(PropertyPresentationState.notDefinedByFormat.label == "Not defined by this format")
        #expect(PropertyPresentationState.readButUnreliable.label == "Read, but not reliable")
        #expect(PropertyPresentationState.couldNotBeRead.label == "Could not be read")

        // Distinct words for distinct facts: undefined, absent and unreadable are three answers.
        let labels = PropertyPresentationState.allCases.compactMap(\.label)
        #expect(Set(labels).count == labels.count)

        // A symbol never appears without its label, so nothing depends on seeing one.
        for state in PropertyPresentationState.allCases where state.symbolName != nil {
            #expect(state.label != nil, "\(state) is conveyed by a symbol with no words")
        }
        // Only a failure of the reading is coloured.
        #expect(PropertyPresentationState.couldNotBeRead.isReadFailure)
        for state in PropertyPresentationState.allCases where state != .couldNotBeRead {
            #expect(!state.isReadFailure, "\(state) is coloured as a failure")
        }
    }

    /// **An absent value is a dash and a sentence, never a number.** The report carries no value, and
    /// the section shows none — asserted across a report that has one of each state.
    @Test("a property with no value shows no figure in its place")
    func absenceIsNotZero() throws {
        let rows = ReportPropertyFormatter.displays(for: everyStateReport().properties)
        let valueless = rows.filter { $0.value == nil }
        #expect(!valueless.isEmpty, "the fixture has no absent property, so this proved nothing")
        for row in valueless {
            #expect(row.state != .measured)
            #expect(row.state.label != nil, "\(row.name) is absent and says nothing about it")
        }
        // The section's substitute for a missing value is a dash, and there is exactly one of them.
        let source = try section()
        #expect(source.contains { $0.contains("property.value ?? \"—\"") })
        for zero in ["?? \"0\"", "?? 0", "?? \"\"", "?? \"none\"", "?? \"n/a\""] {
            #expect(!source.contains { $0.contains(zero) }, "an absent value is substituted with \(zero)")
        }
    }

    // MARK: - 2.4 — identity without location

    @Test("the file's identity is presented, and its location is not")
    func theFileIdentityCarriesNoLocation() throws {
        let source = try section()
        for fact in ["report.file.displayName", "report.file.fileExtension", "report.file.sizeBytes",
                     "report.file.modifiedAt", "sourceDescription"] {
            #expect(source.contains { $0.contains(fact) }, "the file's \(fact) is not presented")
        }
        // Nothing that could be a location — and the domain carries none to begin with.
        for location in ["URL", "path", "absoluteString", "standardizedFileURL", "bookmark",
                         "deletingLastPathComponent", "FileManager"] {
            #expect(
                !source.contains { $0.contains(location) },
                "the section reaches for \(location), which would disclose where the file is"
            )
        }
        // The source keeps the sentence it already had.
        #expect(source.contains { $0.contains("\"User-selected local file (location omitted)\"") })

        // **And no literal on this surface is a location either.** Refusing the symbols alone was not
        // enough: a path written out by hand reaches the reader without any of them, which is what the
        // control demonstrated. Every string the section can render is swept, and a path separator is
        // refused outright — no sentence here has ever needed one, and a file name cannot contain one.
        var literals: [String] = []
        for line in source {
            literals += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(literals.count > 8, "the sweep covered \(literals.count) strings")
        for literal in literals {
            for shape in ["/", "~", "file:", "Users", "Volumes", "\\\\"] {
                #expect(
                    !literal.contains(shape),
                    "\"\(literal)\" looks like a location, and this surface may not carry one"
                )
            }
        }
    }

    // MARK: - 2.5 — notes as they are

    @Test("notes keep their words and their states, and are absent when there are none")
    func notesAreUnchanged() throws {
        let notes = ReportPropertyFormatter.displays(for: everyStateReport().warnings)
        #expect(notes.count == 2)
        #expect(notes.contains { $0.message == "The file size could not be read." })
        #expect(notes.contains { $0.message == "The container was inferred rather than declared." })
        #expect(ReportPropertyFormatter.displays(for: cleanReport().warnings).isEmpty)

        let source = try section()
        // The area exists only when there is something in it.
        #expect(source.contains { $0.contains("if !notes.isEmpty") })
        // Nothing counts, scores or ranks them.
        for aggregate in ["notes.count", "warnings.count", "severity", "priority", "sorted(",
                          "issues", "problems"] {
            #expect(!source.contains { $0.contains(aggregate) }, "the section \(aggregate) the notes")
        }
    }

    // MARK: - 2.6 — the result is about the reading

    /// It is the report's own sentence, and it is set apart from the properties: outside the areas the
    /// facts sit in, so it does not read as a tenth fact.
    @Test("the result is the report's own statement, set apart from the facts")
    func theResultIsUnchangedAndApart() throws {
        let source = try section()
        #expect(source.contains { $0.contains("ReportPropertyFormatter.outcome(") })
        // It is not inside a ReportSection — the facts' container.
        let resultStart = try #require(source.firstIndex { $0.contains("private var resultStatement") })
        // The block ends where the next declaration begins. R8 appended comparison mode to this file,
        // so the marker is whichever of the two comes first rather than the one that used to be last.
        let resultEnd = source[resultStart...].firstIndex {
            $0.contains("private struct DetailPropertyRow") || $0.contains("extension ReportDetailsView")
        } ?? source.endIndex
        let result = Array(source[resultStart ..< resultEnd])
        #expect(!result.contains { $0.contains("ReportSection(") }, "the result is styled as a fact area")
        #expect(result.contains { $0.contains("Text(\"Result\")") })
    }

    /// The sentences the outcome may use, and the ones it may not. Presentation states what became of
    /// the reading; it never characterises the file.
    @Test("no wording on this section states a verdict, a score or a provenance")
    func theSectionStatesNoVerdict() throws {
        var strings: [String] = []
        for report in [everyStateReport(), cleanReport()] {
            let rows = ReportPropertyFormatter.displays(for: report.properties)
            strings.append(ReportPropertyFormatter.outcome(for: report.status, properties: rows).text)
            strings += rows.flatMap { [$0.name, $0.value, $0.detail, $0.accessibilityLabel].compactMap { $0 } }
            strings += ReportPropertyFormatter.displays(for: report.warnings).flatMap {
                [$0.subject, $0.message, $0.accessibilityLabel].compactMap { $0 }
            }
        }
        strings += PropertyPresentationState.allCases.compactMap(\.label)
        for line in try section() {
            strings += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(strings.count > 40, "the sweep covered \(strings.count) strings")

        let forbidden = [
            "quality", "grade", "score", "rating", "verdict", "good", "bad", "better", "worse",
            "excellent", "poor", "high quality", "low quality", "lossy-sounding",
            "original", "master", "remaster", "transcode", "transcoded", "upsample", "upsampled",
            "source file", "provenance", "authentic", "fake", "severity", "critical",
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

    // MARK: - 2.7 — nothing is collapsed

    /// ADR-0026 §11 forbids collapsing a value, an absence, a failure or a certainty state. Nothing here
    /// is collapsed at all, and the reason is in `design.md` §4 rather than the disclosure being added
    /// for its own sake.
    @Test("no factual content is hidden behind a disclosure")
    func nothingFactualIsHidden() throws {
        let source = try section()
        for hiding in ["DisclosureGroup", ".help(", ".popover(", ".onHover", "isExpanded",
                       "@State private var showing"] {
            #expect(!source.contains { $0.contains(hiding) }, "the section hides content behind \(hiding)")
        }
    }

    // MARK: - Accessibility, for this section

    /// Each property is one element carrying its whole sentence — the rule `PropertyRow` already
    /// follows — and the group names and the result are headings.
    @Test("each row is one element, and the groups are headings")
    func theSectionReadsAsGroupsOfRows() throws {
        let source = try section()
        #expect(source.contains { $0.contains(".accessibilityElement(children: .ignore)") })
        #expect(source.filter { $0.contains(".accessibilityAddTraits(.isHeader)") }.count >= 2)
        // A row falls back to its own name and value when the report gives it no sentence.
        #expect(source.contains { $0.contains("accessibilityLabel ?? \"\\(name): \\(value)\"") })

        // The rows' sentences are the report's, and they name the state in words.
        let rows = ReportPropertyFormatter.displays(for: everyStateReport().properties)
        for row in rows where row.state.label != nil {
            #expect(
                row.accessibilityLabel.contains(row.state.label!),
                "\(row.name)'s spoken sentence omits its state"
            )
        }
    }
}
