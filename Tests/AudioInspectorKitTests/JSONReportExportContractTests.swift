import Foundation
import Testing

import AudioInspectorApp
import AudioInspectorDomain

/// Contract tests pinning the exporter to the two canonical scenarios in `docs/json-schema-v1.md`:
/// a **partial** inspection and a **global failure**. Both build the domain report in memory and
/// inject the example's clock/generator, then compare the **decoded** JSON structurally — key sets,
/// states, codes, value types, and explicit `null`s — rather than by brittle string equality. Stable
/// codes and states are identity; descriptive messages are not (per the schema), so the failure case
/// asserts identity/shape instead of the example's exact prose.
@Suite("Export — JSON v1 canonical contract")
struct JSONReportExportContractTests {

    // MARK: - Partial inspection (fully reproducible → structural deep-equal)

    @Test func partialInspectionMatchesTheCanonicalExample() throws {
        let file = AudioFileReference(
            displayName: "interview-side-a.m4a",
            fileExtension: "m4a",
            sizeBytes: 8_421_376,
            modifiedAt: date("2026-06-12T09:03:00Z"),
            source: .userSelectedLocalFile(displayName: "interview-side-a.m4a", locationDisclosure: .omitted)
        )
        let properties = TechnicalProperties(
            container: .available("mpeg-4"),
            duration: .available(372.51),
            sampleRate: .available(44_100),
            channelCount: .available(2),
            bitDepth: .unsupported(reason: "AAC does not define a PCM bit depth"),
            codec: .available("aac"),
            declaredBitrate: .available(128_000),
            estimatedBitrate: .uncertain(
                value: 180_904,
                reason: "estimated as fileSize*8/duration; includes container overhead and is not read from the stream"
            )
        )
        let warnings = [
            InspectionWarning(
                code: .propertyUnsupported, field: "bitDepth", kind: .unsupported,
                message: "Bit depth is not defined for this lossy codec."
            ),
            InspectionWarning(
                code: .propertyUncertain, field: "estimatedBitrate", kind: .uncertain,
                message: "Bitrate was estimated from size and duration, not read from the stream."
            ),
        ]
        let report = InspectionReport(
            file: file,
            properties: properties,
            warnings: warnings,
            status: .partial(message: "Some properties are not exposed by this format.")
        )

        let produced = try exportObject(report, now: date("2026-07-30T16:40:00Z"))
        let expected = try decodeObject(Self.canonicalPartial)
        #expect(jsonEqual(produced, expected))
    }

    // MARK: - Global failure (structural identity; descriptive messages are not pinned)

    @Test func globalFailureMatchesTheCanonicalShape() throws {
        let file = AudioFileReference(
            displayName: "broken.wav",
            fileExtension: "wav",
            sizeBytes: 0,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "broken.wav", locationDisclosure: .omitted)
        )
        let warnings = [
            InspectionWarning(
                code: .metadataModifiedAtUnavailable, field: "modifiedAt", kind: .unavailable,
                message: "Modification date could not be read."
            ),
        ]
        let report = InspectionReport(
            file: file,
            properties: TechnicalProperties(),
            warnings: warnings,
            status: .failed(InspectionError(code: .fileOpenFailed, message: "The audio file could not be opened."))
        )

        let object = try exportObject(report, now: date("2026-07-30T16:41:00Z"))

        // Envelope.
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["generatedAt"] as? String == "2026-07-30T16:41:00Z")

        // inspectedFile — sizeBytes present as 0, modifiedAt explicit null.
        let inspected = try #require(object["inspectedFile"] as? [String: Any])
        #expect(inspected["name"] as? String == "broken.wav")
        #expect(inspected["sizeBytes"] as? Int == 0)
        #expect(inspected.keys.contains("modifiedAt"))
        #expect(inspected["modifiedAt"] is NSNull)

        // No property was inspected → empty object.
        #expect((object["technicalProperties"] as? [String: Any])?.isEmpty == true)

        // Metadata warning survives on the failure path.
        let encodedWarnings = try #require(object["warnings"] as? [[String: Any]])
        #expect(encodedWarnings.count == 1)
        #expect(encodedWarnings[0]["code"] as? String == "metadata_modified_at_unavailable")
        #expect(encodedWarnings[0]["field"] as? String == "modifiedAt")
        #expect(encodedWarnings[0]["kind"] as? String == "unavailable")

        // Global failure carries the stable error code (identity); messages stay descriptive.
        let status = try #require(object["inspectionStatus"] as? [String: Any])
        #expect(status["state"] as? String == "failed")
        let error = try #require(status["error"] as? [String: Any])
        #expect(error["code"] as? String == "file_open_failed")
        #expect(status["message"] != nil)
    }

    // The canonical partial example verbatim from docs/json-schema-v1.md.
    private static let canonicalPartial = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-30T16:40:00Z",
      "generator": { "name": "Audio Inspector", "version": "0.1.0" },
      "inspectedFile": {
        "name": "interview-side-a.m4a",
        "fileExtension": "m4a",
        "sizeBytes": 8421376,
        "modifiedAt": "2026-06-12T09:03:00Z",
        "source": {
          "kind": "userSelectedLocalFile",
          "displayName": "interview-side-a.m4a",
          "locationDisclosure": "omitted"
        }
      },
      "technicalProperties": {
        "container":       { "state": "available",   "value": "mpeg-4" },
        "duration":        { "state": "available",   "value": 372.51, "unit": "seconds" },
        "sampleRate":      { "state": "available",   "value": 44100,  "unit": "hertz" },
        "channelCount":    { "state": "available",   "value": 2 },
        "bitDepth":        { "state": "unsupported", "value": null,   "reason": "AAC does not define a PCM bit depth" },
        "codec":           { "state": "available",   "value": "aac" },
        "declaredBitrate": { "state": "available",   "value": 128000, "unit": "bitsPerSecond" },
        "estimatedBitrate":{ "state": "uncertain",   "value": 180904, "unit": "bitsPerSecond",
                             "reason": "estimated as fileSize*8/duration; includes container overhead and is not read from the stream" }
      },
      "warnings": [
        { "code": "property_unsupported", "field": "bitDepth", "kind": "unsupported",
          "message": "Bit depth is not defined for this lossy codec." },
        { "code": "property_uncertain", "field": "estimatedBitrate", "kind": "uncertain",
          "message": "Bitrate was estimated from size and duration, not read from the stream." }
      ],
      "inspectionStatus": { "state": "partial", "message": "Some properties are not exposed by this format." }
    }
    """
}
