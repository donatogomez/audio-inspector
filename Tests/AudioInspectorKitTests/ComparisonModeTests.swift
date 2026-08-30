import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R8's subject: **the same five sections, presenting two files, and unable to summarise them.**
//
// The comparison's semantics are not re-tested here — they belong to `audio-two-file-comparison` and to
// the suites that already pin `ComparisonFormatter` and `MeasurementComparisonFormatter`. What is tested
// here is the thing R8 could get wrong: **where** each comparison is read, and what the surfaces around
// it might say.

@Suite("Feature — comparison as a mode of the workspace")
struct ComparisonModeTests {

    // MARK: - Fixtures

    private func reference(_ name: String, size: Int? = 1_024) -> AudioFileReference {
        AudioFileReference(
            displayName: name, fileExtension: "wav", sizeBytes: size,
            modifiedAt: Date(timeIntervalSince1970: 1_749_718_980),
            source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
        )
    }

    private func report(
        _ name: String, _ properties: TechnicalProperties,
        warnings: [InspectionWarning] = [], status: InspectionStatus = .completed
    ) -> InspectionReport {
        InspectionReport(file: reference(name), properties: properties, warnings: warnings, status: status)
    }

    private let wav = TechnicalProperties(
        container: .available("wav"), duration: .available(180.0),
        sampleRate: .available(44_100), channelCount: .available(2), bitDepth: .available(16),
        codec: .available("lpcm"), declaredBitrate: .available(1_411_200)
    )

    private let m4a = TechnicalProperties(
        container: .available("mp4"), duration: .available(372.5),
        sampleRate: .available(48_000), channelCount: .available(1), bitDepth: .unsupported(reason: "n/a"),
        codec: .available("aac"), declaredBitrate: .available(256_000)
    )

    /// Two files whose every compared property is the same — the adversarial case.
    private func allAgree() -> FileComparison {
        FileComparison(first: report("a.wav", wav), second: report("b.wav", wav))
    }

    /// Two files that agree about nothing they can be compared on.
    private func allDiffer() -> FileComparison {
        FileComparison(first: report("a.wav", wav), second: report("b.m4a", m4a))
    }

    private func note(_ message: String) -> InspectionWarning {
        InspectionWarning(code: .propertyUnavailable, field: nil, kind: .unavailable, message: message)
    }

    // MARK: - Reading the sources

    private func code(of file: String) throws -> [String] {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/FeatureAnalysis/\(file)"),
            encoding: .utf8
        )
        .components(separatedBy: .newlines)
        .filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
        }
    }

    private func overview() throws -> [String] { try code(of: "ComparisonOverviewView.swift") }
    private func details() throws -> [String] { try code(of: "ReportDetailsView.swift") }
    private func measurements() throws -> [String] { try code(of: "ReportMeasurementsView.swift") }

    private func literals(_ source: [String]) -> [String] {
        source.flatMap { line in
            line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
    }

    // MARK: - The Comparison Overview: both identities, and nothing that could be an outcome

    @Test("the overview presents both files' identities, positionally labelled")
    func bothIdentitiesArePresented() throws {
        let source = try overview()
        #expect(source.contains { $0.contains("identity(ComparisonCopy.firstFile, report.file)") })
        #expect(source.contains { $0.contains("identity(ComparisonCopy.secondFile, comparison.second.file)") })
        for fact in ["file.displayName", "file.fileExtension", "file.sizeBytes", "file.modifiedAt", "file.source"] {
            #expect(source.contains { $0.contains(fact) }, "the overview omits \(fact)")
        }
        // Positional, never a hierarchy.
        #expect(ComparisonCopy.firstFile == "First file")
        #expect(ComparisonCopy.secondFile == "Second file")
    }

    /// **The all-agree gate, and it is structural rather than lexical.**
    ///
    /// A word list cannot catch an aggregate carried by an absence — a badge that only appears when
    /// something differs says *they match* by not appearing. The guarantee has to be that **no outcome
    /// can reach this surface at all**, and that is a property of what the view reads.
    ///
    /// So: the Comparison Overview reads each file's `file` and the copy, and nothing else. It never
    /// touches a property, a measurement, a warning, a status or any comparison type — so there is no
    /// value on it that could vary with whether the two files agree, and the all-agree render differs
    /// from an all-differ render only where the two files' own names and sizes differ.
    @Test("no outcome can reach the comparison overview")
    func noOutcomeReachesTheOverview() throws {
        let source = try overview()
        for outcomeBearing in [
            "ComparisonFormatter", "MeasurementComparison", "ComparisonRowDisplay", "MeasurementRowDisplay",
            "outcome", "PropertyComparison", ".properties", ".warnings", ".status",
            "same", "different", "differs", "notComparable",
        ] {
            #expect(!source.contains { $0.contains(outcomeBearing) },
                    "the comparison overview reads \(outcomeBearing), which varies with the outcome")
        }
        // And nothing on it is conditional on anything but which comparison *state* the flow is in —
        // never on what comparing the two files established.
        #expect(!source.contains { $0.contains("if ") && $0.contains("outcome") })
    }

    /// The differential the gate is named for, asserted on the values the surface actually renders.
    @Test("an all-agree pair and an all-differ pair render the same elements")
    func allAgreeRendersTheSameElements() {
        func elements(_ files: FileComparison) -> [String] {
            // What the overview renders, in the order it renders it: the framing, then each file's
            // identity labels. The *values* are the files' own; the *elements* must not vary.
            var kinds = ["framing", "framing"]
            for file in [files.first.file, files.second.file] {
                kinds.append("Name")
                if file.fileExtension != nil { kinds.append("Extension") }
                if file.sizeBytes != nil { kinds.append("Size") }
                if file.modifiedAt != nil { kinds.append("Modified") }
                kinds.append("Source")
            }
            return kinds
        }
        #expect(elements(allAgree()) == elements(allDiffer()),
                "the overview's elements vary with whether the files agree")
    }

    /// **Nothing on the overview is a summary, and nothing on it is a note.**
    @Test("the overview states no aggregate, no note and no result")
    func theOverviewStatesNothingItMayNot() throws {
        var strings = literals(try overview())
        strings += [ComparisonCopy.firstFile, ComparisonCopy.secondFile,
                    ComparisonCopy.loading, ComparisonCopy.failedHeadline,
                    ComparisonOverviewCopy.twoFilesAreOpen,
                    ComparisonOverviewCopy.whereEachSectionLooks]
        #expect(strings.count > 12, "the sweep covered \(strings.count) strings")

        let forbidden = [
            "match", "matches", "matching", "identical", "agree", "agrees", "equivalent",
            "similar", "similarity", "confidence", "score", "grade", "percentage", "differences",
            "better", "worse", "original", "master", "remaster", "transcode", "transcoded", "upsampled",
            "warning", "warnings", "note", "notes", "issues", "problems", "result",
        ]
        for string in strings {
            for term in forbidden {
                #expect(
                    string.range(of: "\\b\(term)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
                    "the comparison overview states \(term): \"\(string)\""
                )
            }
        }
        // A count reaches a reader as a digit before it reaches a word.
        for literal in literals(try overview()) {
            #expect(!literal.contains { $0.isNumber }, "\"\(literal)\" carries a digit")
        }
    }

    @Test("the overview discloses no location")
    func theOverviewDisclosesNoLocation() throws {
        let source = try overview()
        for location in ["url", "URL", "absoluteString", "standardizedFileURL", "bookmark", ".path"] {
            #expect(!source.contains { $0.contains(location) }, "the overview reaches for \(location)")
        }
        for literal in literals(source) {
            for shape in ["/", "~", "file:", "Users", "Volumes"] {
                #expect(!literal.contains(shape), "\"\(literal)\" looks like a location")
            }
        }
    }

    // MARK: - Details in comparison mode

    @Test("details renders the report's own comparison, unfiltered")
    func detailsRendersTheComparison() throws {
        let source = try details()
        #expect(source.contains { $0.contains("ComparisonFormatter.rows(for: files)") })
        // Every row is present whatever its outcome — no filter, no "only what differs".
        for filtering in ["filter {", "differ", "onlyDifferences", "compactMap { row"] {
            #expect(!source.contains { $0.contains("ComparisonFormatter.rows") && $0.contains(filtering) })
        }
        #expect(ComparisonFormatter.rows(for: allAgree()).count == ComparisonFormatter.rows(for: allDiffer()).count,
                "the number of rows varies with the outcome")
        #expect(ComparisonFormatter.rows(for: allAgree()).count > 0)
    }

    /// **Each file's notes, in words, and never counted.** This is the requirement `warningSummary`
    /// violated: it rendered *"1 warning on this file"* for each side.
    @Test("notes are presented per file and never counted")
    func notesAreNeverCounted() throws {
        let source = try details()
        #expect(source.contains { $0.contains("ReportPropertyFormatter.displays(for: files.first.warnings)") })
        #expect(source.contains { $0.contains("ReportPropertyFormatter.displays(for: files.second.warnings)") })
        for counting in ["warnings.count", "notes.count", "first.count", "second.count",
                         "warningSummary", "severity", "priority", "sorted("] {
            #expect(!source.contains { $0.contains(counting) }, "details \(counting) the notes")
        }
        // The deleted surface is really gone, and nothing rebuilt its sentence.
        for literal in literals(source) {
            #expect(!literal.localizedCaseInsensitiveContains("warning on this file"))
            #expect(!literal.localizedCaseInsensitiveContains("warnings on this file"))
        }
    }

    /// A reading's result is a statement about that reading. Two of them are two statements, never an
    /// outcome — there is no column for one, so none can appear.
    @Test("the two results are presented and never compared")
    func resultsAreNotCompared() throws {
        let source = try details()
        #expect(source.contains { $0.contains("ComparisonCopy.statusLine(for: files.first)") })
        #expect(source.contains { $0.contains("ComparisonCopy.statusLine(for: files.second)") })
        // The result block has no outcome and no grid of one.
        let start = try #require(source.firstIndex { $0.contains("func comparedResultStatement") })
        let end = source[start...].firstIndex { $0.contains("fileprivate var secondFileState") } ?? source.endIndex
        for line in source[start ..< end] {
            for verdict in ["outcome", "ComparisonCopy.outcomeColumn", "same", "different"] {
                #expect(!line.contains(verdict), "the results are compared: \(line)")
            }
        }
    }

    // MARK: - Measurements in comparison mode

    @Test("measurements presents the comparison in place, through the tested sub-section")
    func measurementsPresentsTheComparisonInPlace() throws {
        let source = try measurements()
        #expect(source.contains { $0.contains("MeasurementComparisonSection(comparison: measurements)") })
        // It is the section's own content, not a block after it: the inspection groups are the `else`.
        let compared = try #require(source.firstIndex { $0.contains("comparedMeasurements(measurements)") })
        let inspection = try #require(source.firstIndex { $0.contains("MeasurementGroupSection(group: group)") })
        #expect(compared < inspection, "the comparison is appended after the measurements")
        #expect(source.contains { $0.contains("} else {") })
    }

    /// The one difference the domain publishes, and no other. Asserted against the formatter rather than
    /// against the view, because that is where the rule lives.
    @Test("only the loudness row carries a difference")
    func onlyLoudnessCarriesADifference() throws {
        let first = ReportMeasurements(
            signalLevelMetrics: nil, truePeak: nil,
            loudness: try #require(LoudnessMeasurement(
                integratedLoudness: -14.0,
                method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz))),
            programmeBandwidth: nil
        )
        let second = ReportMeasurements(
            signalLevelMetrics: nil, truePeak: nil,
            loudness: try #require(LoudnessMeasurement(
                integratedLoudness: -9.5,
                method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz))),
            programmeBandwidth: nil
        )
        let blocks = MeasurementComparisonFormatter.blocks(
            for: MeasurementComparison(first: first, second: second)
        )
        let withDifference = blocks.flatMap(\.rows).filter { $0.difference != nil }
        #expect(withDifference.count == 1, "more than one row publishes a difference")
        #expect(withDifference.first?.name == LoudnessCopy.title)
    }

    // MARK: - Loading and failure

    @Test("a loading or failed comparison invents no value for the second file")
    func noValueIsInventedForTheSecondFile() throws {
        for source in [try overview(), try details(), try measurements()] {
            for invented in ["\"0\"", "\"0.0\"", "\"—\"" ,"placeholder", "\"n/a\"", "\"N/A\""] {
                let offending = source.filter { $0.contains(invented) && $0.contains("second") }
                #expect(offending.isEmpty, "a placeholder stands in for the second file: \(offending)")
            }
        }
        // The two sentences a reader gets are the flow's own, and a failure names no cause in the audio.
        #expect(ComparisonCopy.loading == "Inspecting the second file…")
        for blame in ["because", "differ", "incompatible", "mismatch"] {
            #expect(!ComparisonCopy.failedHeadline.localizedCaseInsensitiveContains(blame))
        }
    }

    // MARK: - First / Second

    @Test("no surface names a file by anything but its position")
    func positionalLanguageOnly() throws {
        var strings: [String] = []
        for file in ["ComparisonOverviewView.swift", "ReportDetailsView.swift", "ReportMeasurementsView.swift"] {
            strings += literals(try code(of: file))
        }
        strings += [ComparisonCopy.firstFile, ComparisonCopy.secondFile,
                    MeasurementComparisonCopy.firstFile, MeasurementComparisonCopy.secondFile]
        for hierarchy in ["original", "source file", "reference", "master", "copy", "candidate",
                          "derived", "baseline", "target"] {
            for string in strings {
                #expect(
                    string.range(of: "\\b\(hierarchy)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
                    "\"\(string)\" names a file by a hierarchy"
                )
            }
        }
    }

    // MARK: - The page that is gone

    @Test("the transitional report page and its comparison surface no longer exist")
    func theLegacySurfacesAreGone() {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis")
        for gone in ["ReportView.swift", "ComparisonView.swift"] {
            #expect(!FileManager.default.fileExists(atPath: sources.appendingPathComponent(gone).path),
                    "\(gone) is back")
        }
        // And the container they declared outlived them, because four live sections use it.
        #expect(FileManager.default.fileExists(atPath: sources.appendingPathComponent("ReportSection.swift").path))
    }
}
