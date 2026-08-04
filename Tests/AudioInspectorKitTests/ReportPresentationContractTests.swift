import Foundation
import Testing
import UniformTypeIdentifiers

import AudioInspectorDomain
@testable import FeatureAnalysis

/// The contract the report surface must keep, asserted structurally rather than row by row: no internal
/// identifier reaches the screen, technical tokens are named only when the name is certain, and nothing
/// presented characterises the file. These are the checks that catch a regression introduced by an
/// innocent-looking edit somewhere else.
@Suite("Feature — report presentation contract")
struct ReportPresentationContractTests {

    /// Deliberately hostile: every property in a different state, warnings on both a field and none,
    /// so the sweep below covers every branch that can produce text.
    private func everyStateReport() -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: "interview-side-a.m4a",
                fileExtension: "m4a",
                sizeBytes: 8_421_376,
                modifiedAt: Date(timeIntervalSince1970: 1_749_718_980),
                source: .userSelectedLocalFile(displayName: "interview-side-a.m4a", locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(
                container: .uncertain(value: "public.mpeg-4-audio", reason: "inferred from the file type"),
                duration: .available(372.51),
                sampleRate: .available(44_100),
                channelCount: .available(2),
                bitDepth: .unsupported(reason: "not defined for this codec"),
                codec: .available("aac"),
                declaredBitrate: .failed(PropertyFailure(code: .propertyReadError, message: "could not be read")),
                estimatedBitrate: .uncertain(value: 180_904, reason: "derived from size and duration")
            ),
            warnings: [
                InspectionWarning(code: .propertyUnsupported, field: "bitDepth", kind: .unsupported, message: "Not defined for this codec."),
                InspectionWarning(code: .metadataModifiedAtUnavailable, field: nil, kind: .unavailable, message: "The modification date is unknown."),
            ],
            status: .partial(message: nil)
        )
    }

    /// Every string the report can render, gathered in one place.
    private func allPresentedText(_ report: InspectionReport) -> [String] {
        let rows = ReportPropertyFormatter.displays(for: report.properties)
        let warnings = ReportPropertyFormatter.displays(for: report.warnings)
        return rows.flatMap { [$0.name, $0.value, $0.detail, $0.state.label, $0.accessibilityLabel].compactMap { $0 } }
            + warnings.flatMap { [$0.subject, $0.message, $0.accessibilityLabel].compactMap { $0 } }
            + ReportPropertyFormatter.summary(for: report).highlights
            + [ReportPropertyFormatter.summary(for: report).fileName]
            + [ReportPropertyFormatter.outcome(for: report.status, properties: rows).text]
            + ReportPropertyFormatter.groups(for: report.properties).map(\.name)
    }

    // MARK: - No internal identifier reaches the surface

    /// Stable codes and wire keys are snake_case or lowerCamelCase identifiers; neither belongs on
    /// screen. The file name is excluded because it is the user's own text, not ours.
    @Test func noPresentedTextContainsAStableCodeOrWireKey() {
        let report = everyStateReport()
        let ours = allPresentedText(report).filter { $0 != report.file.displayName }

        let codes = [
            "property_unsupported", "property_unavailable", "property_uncertain",
            "property_extraction_failed", "property_read_error",
            "metadata_size_unavailable", "metadata_modified_at_unavailable",
            "file_open_failed", "file_unreadable", "file_access_denied",
        ]
        let wireKeys = ["sampleRate", "channelCount", "bitDepth", "declaredBitrate", "estimatedBitrate", "sizeBytes", "modifiedAt"]

        for text in ours {
            #expect(!text.contains("_"), "underscored identifier surfaced: \(text)")
            for code in codes { #expect(!text.contains(code)) }
            for key in wireKeys { #expect(!text.contains(key)) }
        }
    }

    /// The domain's case names are ours, not the user's.
    @Test func noPresentedTextContainsADomainCaseName() {
        let report = everyStateReport()
        let ours = allPresentedText(report).filter { $0 != report.file.displayName }
        let caseNames = ["available", "unavailable", "unsupported", "uncertain", "completed", "partial"]

        for text in ours {
            for name in caseNames {
                #expect(!text.lowercased().contains(name), "domain case name surfaced in: \(text)")
            }
        }
    }

    @Test func theLiteralGeneralIsNeverUsedAsAWarningSubject() {
        let warnings = ReportPropertyFormatter.displays(for: everyStateReport().warnings)
        #expect(warnings.contains { $0.subject == nil }) // the fieldless warning exists…
        #expect(!warnings.contains { $0.subject == "general" }) // …and is not given an invented label
    }

    // MARK: - Names only where certain

    @Test func knownCodecTokensAreNamed() {
        #expect(ReportPropertyFormatter.codecName("lpcm") == "Linear PCM")
        #expect(ReportPropertyFormatter.codecName("aac") == "AAC")
        #expect(ReportPropertyFormatter.codecName("alac") == "Apple Lossless (ALAC)")
        #expect(ReportPropertyFormatter.codecName("LPCM") == "Linear PCM") // case-insensitive
    }

    /// An unrecognised token is shown as it is. Guessing a name would invent what the reader never
    /// established.
    @Test(arguments: ["qwer", "xyz1", "", "sowt", "ulaw"])
    func unknownCodecTokensAreShownUnchanged(token: String) {
        #expect(ReportPropertyFormatter.codecName(token) == token)
    }

    @Test func aResolvableTypeIdentifierIsNamedAndAnUnknownOneIsNot() throws {
        let identifier = "public.aiff-audio"
        let named = ReportPropertyFormatter.containerName(identifier)
        // Whatever the system calls it, it is not the identifier and carries no reverse-DNS prefix.
        #expect(named != identifier)
        #expect(!named.contains("public."))
        let systemName = try #require(UTType(identifier)?.localizedDescription)
        #expect(named == systemName)

        // An identifier the system cannot resolve is shown unchanged rather than described.
        #expect(ReportPropertyFormatter.containerName("com.example.not-a-real-type") == "com.example.not-a-real-type")
        #expect(ReportPropertyFormatter.containerName("wav") == "wav")
    }

    /// The row keeps the identifier as detail, so naming never hides the datum.
    @Test func namingAContainerPreservesItsIdentifier() throws {
        let rows = ReportPropertyFormatter.displays(for: everyStateReport().properties)
        let container = try #require(rows.first { $0.name == "Container" })

        #expect(container.value != "public.mpeg-4-audio")
        #expect(container.detail?.contains("public.mpeg-4-audio") == true)
    }

    // MARK: - The summary answers the glance question

    @Test func theSummaryLeadsWithTheFactsThatIdentifyTheFile() {
        let summary = ReportPropertyFormatter.summary(for: everyStateReport())
        #expect(summary.fileName == "interview-side-a.m4a")
        #expect(summary.highlights == ["AAC", "44.1 kHz", "Stereo", "6:13", "8.4 MB"])
    }
}
