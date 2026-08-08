import Foundation
import Testing

@testable import AudioInspectorApp
import AudioInspectorDomain
@testable import FeatureImport

/// **The export is untouched by comparing.** A file's `schemaVersion` 1 document must be the same
/// bytes whether or not a comparison is on screen — and must never gain a field, a key, or a second
/// inspected file because one exists.
///
/// The strongest evidence is structural and needs no test at all: `ReportExporting.export` takes an
/// `InspectionReport` and nothing else, so a comparison has no parameter to arrive through. What these
/// tests add is the half that structure cannot give — that the *flow* does not quietly hand the
/// exporter a different report once a comparison exists.
///
/// The bytes are compared as `Data`, not as decoded structures: a structural comparison would pass a
/// document that gained a key encoded differently, and byte identity is what the task asks for. The
/// clock and the generator are injected fixed, exactly as every other export test does.
@MainActor
@Suite("Export — a comparison cannot alter an inspection's JSON")
struct ExportComparisonIsolationTests {

    // MARK: Harness

    private func inspectionReport(_ name: String, sampleRate: Int = 44_100) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 2_048,
                modifiedAt: date("2026-06-12T09:03:00Z"),
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: allAvailableProperties(),
            warnings: [],
            status: .completed
        )
    }

    /// A second file whose inspection failed globally, and which therefore carries warnings and a
    /// failed status — the richest thing a comparison could leak into the first file's document.
    private func failedReport(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "flac",
                sizeBytes: nil,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [
                InspectionWarning(
                    code: .metadataSizeUnavailable,
                    field: "sizeBytes",
                    kind: .unavailable,
                    message: "File size in bytes is not available for this file."
                ),
            ],
            status: .failed(InspectionError(code: .fileUnreadable, message: "could not be opened"))
        )
    }

    /// Drives the real flow to a report, then optionally to a settled comparison, and returns the
    /// report the flow is holding — which is the value the composition root hands the exporter.
    private func reportHeldByTheFlow(
        primary: InspectionReport,
        comparingAgainst second: InspectionReport?
    ) async -> InspectionReport? {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(primary)])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()

        if let second {
            let secondAction = ImportFlowComparisonTests.ControllableAction(delivering: [.report(second)])
            let comparing = Task { await flow.compare(using: secondAction.run) }
            await secondAction.waitUntilStarted()
            secondAction.finish(.inspected(second, waveform: .unavailable, spectrogram: .unavailable))
            await comparing.value
        }

        action.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable))
        await running.value

        guard case let .report(presentation) = flow.state else { return nil }
        return presentation.report
    }

    // MARK: The byte-identity claim

    /// **The main assertion.** The same file, exported alone and exported while a comparison against a
    /// second file is on screen, produces identical bytes.
    @Test("a file's JSON is byte-identical with and without a comparison on screen")
    func theJSONIsByteIdenticalWithAndWithoutAComparison() async throws {
        let primary = inspectionReport("a.wav")
        let second = inspectionReport("b.wav", sampleRate: 96_000)

        let alone = try #require(await reportHeldByTheFlow(primary: primary, comparingAgainst: nil))
        let whileComparing = try #require(
            await reportHeldByTheFlow(primary: primary, comparingAgainst: second)
        )

        let withoutComparison = try exportData(alone)
        let withComparison = try exportData(whileComparing)

        #expect(withoutComparison == withComparison)
        #expect(!withoutComparison.isEmpty)
    }

    /// The same, with the second file carrying everything a comparison could plausibly leak: a failed
    /// status, warnings of its own, a different extension, and an absent size.
    @Test("a failed second file changes not one byte of the first file's document")
    func aFailedSecondFileChangesNothing() async throws {
        let primary = inspectionReport("a.wav")

        let alone = try #require(await reportHeldByTheFlow(primary: primary, comparingAgainst: nil))
        let whileComparing = try #require(
            await reportHeldByTheFlow(primary: primary, comparingAgainst: failedReport("broken.flac"))
        )

        #expect(try exportData(alone) == exportData(whileComparing))
    }

    /// **The positive control, kept permanently.** Byte identity means nothing unless the same
    /// comparison can also fail — so a report that genuinely differs is shown to produce different
    /// bytes through the identical path.
    @Test("the byte comparison detects a report that really differs")
    func theByteComparisonHasTeeth() throws {
        var altered = allAvailableProperties()
        altered.sampleRate = .available(48_000)

        let original = try exportData(inspectionReport("a.wav"))
        let different = try exportData(
            InspectionReport(
                file: inspectionReport("a.wav").file,
                properties: altered,
                warnings: [],
                status: .completed
            )
        )

        #expect(original != different)
    }

    // MARK: The document's shape

    /// **No comparison concept enters the document.** Checked over the tree's **keys**, never its
    /// values: a codec or a container is a string the user's file chose, and scanning values would
    /// report a false positive on a file legitimately named `different.wav`.
    @Test("no comparison key appears anywhere in the document")
    func noComparisonKeyAppears() async throws {
        let primary = inspectionReport("different.wav")
        let whileComparing = try #require(
            await reportHeldByTheFlow(
                primary: primary,
                comparingAgainst: inspectionReport("same.wav", sampleRate: 22_050)
            )
        )

        let keys = try allKeys(exportValue(whileComparing))
        let forbidden = [
            "comparison", "comparisons", "compared", "firstFile", "secondFile", "first", "second",
            "same", "different", "incomparable", "winner", "preferred", "score", "similarity",
            "differences", "differenceCount", "allSame", "isIdentical", "matches",
        ]

        for key in forbidden {
            #expect(!keys.contains(key), "the document gained a \"\(key)\" key")
        }

        // And the value-level false positive the key-only scan exists to avoid is genuinely present,
        // so the check above is not passing merely because the words are absent from the document.
        let value = try exportValue(whileComparing)
        #expect(value["inspectedFile"]?["name"]?.string == "different.wav")
    }

    /// **The document still describes one file.** ADR-0017 promises `schemaVersion` 1 never gains a
    /// second inspected file; this is that promise, asserted.
    @Test("the document carries exactly one inspected file, as an object")
    func theDocumentCarriesOneInspectedFile() async throws {
        let primary = inspectionReport("a.wav")
        let whileComparing = try #require(
            await reportHeldByTheFlow(primary: primary, comparingAgainst: inspectionReport("b.wav"))
        )
        let value = try exportValue(whileComparing)

        // Present, and an object rather than a collection.
        let inspectedFile = try #require(value["inspectedFile"])
        #expect(inspectedFile.keys != nil, "inspectedFile must be an object")
        #expect(inspectedFile.array == nil, "inspectedFile must not be a collection of files")
        #expect(inspectedFile["name"]?.string == "a.wav")

        // No sibling naming a second one, under any plausible spelling.
        let top = try #require(value.keys)
        for key in ["inspectedFiles", "secondInspectedFile", "files", "comparedFile", "otherFile"] {
            #expect(!top.contains(key), "the envelope gained a \"\(key)\" key")
        }

        // The top level is exactly the v1 envelope, so nothing was added at all.
        #expect(top == [
            "schemaVersion", "generatedAt", "generator",
            "inspectedFile", "technicalProperties", "warnings", "inspectionStatus",
        ])
    }

    /// Dismissing a comparison, like never having one, leaves the document identical — the same
    /// assertion from the other side, and the one that would catch a flow that mutated the report on
    /// the way in and restored it imperfectly on the way out.
    @Test("a dismissed comparison leaves the document identical")
    func aDismissedComparisonLeavesTheDocumentIdentical() async throws {
        let primary = inspectionReport("a.wav")
        let alone = try #require(await reportHeldByTheFlow(primary: primary, comparingAgainst: nil))

        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(primary)])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()

        let second = inspectionReport("b.wav", sampleRate: 96_000)
        let secondAction = ImportFlowComparisonTests.ControllableAction(delivering: [.report(second)])
        let comparing = Task { await flow.compare(using: secondAction.run) }
        await secondAction.waitUntilStarted()
        secondAction.finish(.inspected(second, waveform: .unavailable, spectrogram: .unavailable))
        await comparing.value

        flow.dismissComparison()

        action.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable))
        await running.value

        guard case let .report(presentation) = flow.state else {
            Issue.record("expected a report")
            return
        }
        #expect(try exportData(alone) == exportData(presentation.report))
    }
}
