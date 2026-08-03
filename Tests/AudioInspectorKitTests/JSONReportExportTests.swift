import Foundation
import Testing

import AudioInspectorApp
import AudioInspectorDomain

/// Export tests for the JSON v1 slice (group 4). Every `InspectionReport` is built **in memory** — no
/// audio files, no AVFoundation, no filesystem, no real bundle, no real clock. The clock and generator
/// identity are injected deterministically. The encoded bytes are decoded with `JSONSerialization`
/// (test-only) so assertions inspect the **decoded structure** — real key presence, explicit `null`
/// vs. an omitted key, and real JSON scalar types — rather than fragile substring matching.
@Suite("Export — JSON v1 report exporter")
struct JSONReportExportTests {

    // MARK: - Envelope

    @Test func envelopeCarriesSchemaVersionGeneratorAndExportClock() throws {
        let object = try exportObject(report(status: .completed))

        #expect(object["schemaVersion"] as? Int == 1)
        // `generatedAt` is the injected export instant, formatted as ISO-8601 UTC with `Z`.
        #expect(object["generatedAt"] as? String == "2026-08-03T12:00:00Z")
        let generator = try #require(object["generator"] as? [String: Any])
        #expect(generator["name"] as? String == "Audio Inspector")
        #expect(generator["version"] as? String == "0.1.0")
    }

    @Test func generatedAtIsEvaluatedPerExportNotAtInspection() throws {
        // Two exports of the *same* report with two clocks → two distinct `generatedAt` values,
        // proving the clock is read on each `export` (not baked into the report).
        let report = report(status: .completed)
        let first = try exportObject(report, now: date("2026-08-03T12:00:00Z"))
        let second = try exportObject(report, now: date("2026-08-03T15:30:45Z"))
        #expect(first["generatedAt"] as? String == "2026-08-03T12:00:00Z")
        #expect(second["generatedAt"] as? String == "2026-08-03T15:30:45Z")
    }

    @Test func envelopeNeverLeaksTheReportsEphemeralId() throws {
        let report = report(status: .completed)
        let object = try exportObject(report)
        // The domain `AudioFileReference.id` (a per-inspection UUID) appears nowhere in the wire form.
        #expect(!allKeys(object).contains("id"))
        let data = try exportData(report)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains(report.file.id.uuidString))
    }

    // MARK: - inspectedFile (nullable metadata + safe source)

    @Test func inspectedFileCarriesMetadataAndSafeSource() throws {
        let object = try exportObject(report(status: .completed))
        let file = try #require(object["inspectedFile"] as? [String: Any])

        #expect(file["name"] as? String == "interview-side-a.m4a")
        #expect(file["fileExtension"] as? String == "m4a")
        #expect(file["sizeBytes"] as? Int == 8_421_376)
        #expect(file["modifiedAt"] as? String == "2026-06-12T09:03:00Z")

        let source = try #require(file["source"] as? [String: Any])
        #expect(source["kind"] as? String == "userSelectedLocalFile")
        #expect(source["displayName"] as? String == "interview-side-a.m4a")
        #expect(source["locationDisclosure"] as? String == "omitted")
    }

    @Test func nullableFileMetadataIsExplicitNullNotOmitted() throws {
        let file = AudioFileReference(
            displayName: "broken.wav",
            fileExtension: nil,
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "broken.wav", locationDisclosure: .omitted)
        )
        let report = InspectionReport(file: file, properties: TechnicalProperties(), warnings: [], status: .completed)
        let object = try exportObject(report)
        let inspected = try #require(object["inspectedFile"] as? [String: Any])

        // The keys are present (not omitted) and hold an explicit JSON `null`.
        for key in ["fileExtension", "sizeBytes", "modifiedAt"] {
            #expect(inspected.keys.contains(key), "\(key) must be present")
            #expect(inspected[key] is NSNull, "\(key) must be explicit null")
        }
    }

    // MARK: - Privacy (structural, not textual)

    @Test func exportDisclosesNoLocationByShape() throws {
        // A report whose display name deliberately *looks* like a path — the safe DTO shape must still
        // never surface a path/url/bookmark key or the parent directory.
        let file = AudioFileReference(
            displayName: "song.flac",
            fileExtension: "flac",
            sizeBytes: 1,
            modifiedAt: date("2026-01-01T00:00:00Z"),
            source: .userSelectedLocalFile(displayName: "song.flac", locationDisclosure: .omitted)
        )
        let report = InspectionReport(file: file, properties: allAvailableProperties(), warnings: [], status: .completed)
        let object = try exportObject(report)

        // No location-bearing key exists anywhere in the decoded object.
        let forbidden: Set<String> = [
            "path", "url", "fileURL", "absolutePath", "bookmark", "securityScopedBookmark",
            "parentDirectory", "directory", "location", "bookmarkData",
        ]
        #expect(allKeys(object).isDisjoint(with: forbidden))

        // `inspectedFile` and `source` expose exactly the safe key sets — nothing more.
        let inspected = try #require(object["inspectedFile"] as? [String: Any])
        #expect(Set(inspected.keys) == ["name", "fileExtension", "sizeBytes", "modifiedAt", "source"])
        let source = try #require(inspected["source"] as? [String: Any])
        #expect(Set(source.keys) == ["kind", "displayName", "locationDisclosure"])
    }

    // MARK: - technicalProperties — states, value types, units, reasons, errors

    @Test func completedEmitsAllEightPropertyKeys() throws {
        let object = try exportObject(report(properties: allAvailableProperties(), status: .completed))
        let technical = try #require(object["technicalProperties"] as? [String: Any])
        #expect(Set(technical.keys) == [
            "container", "duration", "sampleRate", "channelCount",
            "bitDepth", "codec", "declaredBitrate", "estimatedBitrate",
        ])
    }

    @Test func availableValuesAreRealJSONScalarsWithUnits() throws {
        let object = try exportObject(report(properties: allAvailableProperties(), status: .completed))
        let technical = try #require(object["technicalProperties"] as? [String: Any])

        // String value (no unit).
        let container = try #require(technical["container"] as? [String: Any])
        #expect(container["state"] as? String == "available")
        #expect(container["value"] as? String == "wav")
        #expect(container["unit"] == nil)

        // Double value with a unit — a real JSON number, not a quoted string.
        let duration = try #require(technical["duration"] as? [String: Any])
        #expect(duration["value"] as? Double == 10.5)
        #expect(!(duration["value"] is String))
        #expect(duration["unit"] as? String == "seconds")

        // Int value with a unit — a real JSON number.
        let sampleRate = try #require(technical["sampleRate"] as? [String: Any])
        #expect(sampleRate["value"] as? Int == 44_100)
        #expect(!(sampleRate["value"] is String))
        #expect(sampleRate["unit"] as? String == "hertz")

        // Int value, unitless field → no `unit` key.
        let channelCount = try #require(technical["channelCount"] as? [String: Any])
        #expect(channelCount["value"] as? Int == 2)
        #expect(channelCount["unit"] == nil)
    }

    @Test func unavailableUnsupportedAndFailedHaveNullValueAndTheRightShape() throws {
        var properties = allAvailableProperties()
        properties.declaredBitrate = .unavailable(reason: nil)
        properties.bitDepth = .unsupported(reason: "AAC does not define a PCM bit depth")
        properties.codec = .failed(PropertyFailure(code: .propertyReadError, message: "codec read error"))
        let object = try exportObject(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"] as? [String: Any])

        // unavailable → value explicit null, no unit/reason/error.
        let declared = try #require(technical["declaredBitrate"] as? [String: Any])
        #expect(declared["state"] as? String == "unavailable")
        #expect(declared["value"] is NSNull)
        #expect(Set(declared.keys) == ["state", "value"])

        // unsupported → value null, reason present.
        let bitDepth = try #require(technical["bitDepth"] as? [String: Any])
        #expect(bitDepth["state"] as? String == "unsupported")
        #expect(bitDepth["value"] is NSNull)
        #expect(bitDepth["reason"] as? String == "AAC does not define a PCM bit depth")
        #expect(bitDepth["error"] == nil)

        // failed → value null, structured error (stable code + message), no reason/unit.
        let codec = try #require(technical["codec"] as? [String: Any])
        #expect(codec["state"] as? String == "failed")
        #expect(codec["value"] is NSNull)
        let error = try #require(codec["error"] as? [String: Any])
        #expect(error["code"] as? String == "property_read_error")
        #expect(error["message"] as? String == "codec read error")
        #expect(Set(codec.keys) == ["state", "value", "error"])
    }

    @Test func uncertainWithValueKeepsValueUnitAndRequiredReason() throws {
        var properties = allAvailableProperties()
        properties.estimatedBitrate = .uncertain(value: 180_904, reason: "estimated from size/duration")
        let object = try exportObject(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"] as? [String: Any])

        let estimated = try #require(technical["estimatedBitrate"] as? [String: Any])
        #expect(estimated["state"] as? String == "uncertain")
        #expect(estimated["value"] as? Int == 180_904)
        #expect(estimated["unit"] as? String == "bitsPerSecond")
        #expect(estimated["reason"] as? String == "estimated from size/duration")
    }

    @Test func uncertainWithoutValueHasNullValueNoUnitButKeepsReason() throws {
        var properties = allAvailableProperties()
        properties.estimatedBitrate = .uncertain(value: nil, reason: "cannot estimate")
        let object = try exportObject(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"] as? [String: Any])

        let estimated = try #require(technical["estimatedBitrate"] as? [String: Any])
        #expect(estimated["state"] as? String == "uncertain")
        #expect(estimated["value"] is NSNull)
        #expect(estimated["unit"] == nil) // no value → no unit to attach
        #expect(estimated["reason"] as? String == "cannot estimate")
    }

    @Test func globalFailureEmitsEmptyTechnicalPropertiesObject() throws {
        // A failed status must yield `{}` — even though the report carries an all-`unavailable` set,
        // the exporter must NOT emit eight `unavailable` entries (the gate is the status).
        let error = InspectionError(code: .fileOpenFailed, message: "The audio file could not be opened.")
        let report = InspectionReport(
            file: makeReference(),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(error)
        )
        let object = try exportObject(report)
        let technical = try #require(object["technicalProperties"] as? [String: Any])
        #expect(technical.isEmpty)
    }

    // MARK: - warnings & status

    @Test func warningsAreCarriedFaithfullyWithStableCodesAndKinds() throws {
        let warnings = [
            InspectionWarning(code: .propertyUnsupported, field: "bitDepth", kind: .unsupported, message: "no bit depth"),
            InspectionWarning(code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable, message: "no size"),
        ]
        let object = try exportObject(report(properties: allAvailableProperties(), warnings: warnings, status: .partial(message: "x")))
        let encoded = try #require(object["warnings"] as? [[String: Any]])

        #expect(encoded.count == 2)
        #expect(encoded[0]["code"] as? String == "property_unsupported")
        #expect(encoded[0]["field"] as? String == "bitDepth")
        #expect(encoded[0]["kind"] as? String == "unsupported")
        #expect(encoded[0]["message"] as? String == "no bit depth")
        // A metadata warning rides through the same array unchanged.
        #expect(encoded[1]["code"] as? String == "metadata_size_unavailable")
        #expect(encoded[1]["field"] as? String == "sizeBytes")
        #expect(encoded[1]["kind"] as? String == "unavailable")
    }

    @Test func exporterAddsNoWarningsOfItsOwn() throws {
        // An empty warnings list stays empty — the exporter never derives warnings.
        let object = try exportObject(report(properties: allAvailableProperties(), warnings: [], status: .completed))
        let encoded = try #require(object["warnings"] as? [Any])
        #expect(encoded.isEmpty)
    }

    @Test func completedStatusHasNoMessageAndNoError() throws {
        let object = try exportObject(report(status: .completed))
        let status = try #require(object["inspectionStatus"] as? [String: Any])
        #expect(status["state"] as? String == "completed")
        #expect(status["message"] == nil)
        #expect(status["error"] == nil)
    }

    @Test func partialStatusCarriesMessageButNoError() throws {
        let object = try exportObject(report(status: .partial(message: "some properties missing")))
        let status = try #require(object["inspectionStatus"] as? [String: Any])
        #expect(status["state"] as? String == "partial")
        #expect(status["message"] as? String == "some properties missing")
        #expect(status["error"] == nil)
    }

    @Test func failedStatusCarriesStableErrorCode() throws {
        let error = InspectionError(code: .fileAccessDenied, message: "access denied")
        let report = InspectionReport(
            file: makeReference(),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(error)
        )
        let object = try exportObject(report)
        let status = try #require(object["inspectionStatus"] as? [String: Any])
        #expect(status["state"] as? String == "failed")
        let encodedError = try #require(status["error"] as? [String: Any])
        #expect(encodedError["code"] as? String == "file_access_denied")
        #expect(status["message"] != nil)
    }

    @Test func globalFailureWithMetadataWarningsStaysFailedAndKeepsWarnings() throws {
        // The use case may attach metadata warnings on a global failure; the exporter must keep the
        // `failed` status AND those warnings, never recomputing to `partial` or dropping them.
        let warnings = [
            InspectionWarning(
                code: .metadataModifiedAtUnavailable,
                field: "modifiedAt",
                kind: .unavailable,
                message: "Modification date could not be read."
            ),
        ]
        let error = InspectionError(code: .fileOpenFailed, message: "The audio file could not be opened.")
        let report = InspectionReport(
            file: makeReference(modifiedAt: nil),
            properties: TechnicalProperties(),
            warnings: warnings,
            status: .failed(error)
        )
        let object = try exportObject(report)

        let status = try #require(object["inspectionStatus"] as? [String: Any])
        #expect(status["state"] as? String == "failed")
        #expect((object["technicalProperties"] as? [String: Any])?.isEmpty == true)
        let encoded = try #require(object["warnings"] as? [[String: Any]])
        #expect(encoded.count == 1)
        #expect(encoded[0]["code"] as? String == "metadata_modified_at_unavailable")
    }

    // MARK: - Encoding errors (non-finite values)

    @Test func nonFiniteValueFailsEncodingInsteadOfEmittingAFiction() throws {
        for badDuration in [Double.nan, .infinity, -.infinity] {
            var properties = allAvailableProperties()
            properties.duration = .available(badDuration)
            let report = report(properties: properties, status: .completed)
            #expect(throws: (any Error).self) {
                _ = try exportData(report)
            }
        }
    }
}
