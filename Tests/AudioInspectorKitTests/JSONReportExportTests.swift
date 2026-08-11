import Foundation
import Testing

import AudioInspectorApp
import AudioInspectorDomain

/// Export tests for the JSON v1 slice (group 4). Every `InspectionReport` is built **in memory** — no
/// audio files, no AVFoundation, no filesystem, no real bundle, no real clock. The clock and generator
/// identity are injected deterministically. The encoded bytes are decoded with `JSONDecoder` into a
/// closed, typed `JSONValue` tree (see the support file) so assertions inspect the **decoded
/// structure** — real key presence, explicit `null` vs. an omitted key, and real JSON scalar types —
/// using only `Codable`, never an untyped-object serialization API and never a heterogeneous map.
@Suite("Export — JSON v1 report exporter")
struct JSONReportExportTests {

    // MARK: - Envelope

    @Test func envelopeCarriesSchemaVersionGeneratorAndExportClock() throws {
        let object = try exportValue(report(status: .completed))

        #expect(object["schemaVersion"]?.int == 1)
        // `generatedAt` is the injected export instant, formatted as ISO-8601 UTC with `Z`.
        #expect(object["generatedAt"]?.string == "2026-08-03T12:00:00Z")
        let generator = try #require(object["generator"])
        #expect(generator["name"]?.string == "Audio Inspector")
        #expect(generator["version"]?.string == "0.1.0")
    }

    @Test func generatedAtIsEvaluatedPerExportNotAtInspection() throws {
        // Two exports of the *same* report with two clocks → two distinct `generatedAt` values,
        // proving the clock is read on each `export` (not baked into the report).
        let subject = report(status: .completed)
        let first = try exportValue(subject, now: date("2026-08-03T12:00:00Z"))
        let second = try exportValue(subject, now: date("2026-08-03T15:30:45Z"))
        #expect(first["generatedAt"]?.string == "2026-08-03T12:00:00Z")
        #expect(second["generatedAt"]?.string == "2026-08-03T15:30:45Z")
    }

    @Test func envelopeNeverLeaksTheReportsEphemeralId() throws {
        let subject = report(status: .completed)
        let object = try exportValue(subject)
        // The domain `AudioFileReference.id` (a per-inspection UUID) appears nowhere in the wire form.
        #expect(!allKeys(object).contains("id"))
        let data = try exportData(subject)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains(subject.file.id.uuidString))
    }

    // MARK: - inspectedFile (nullable metadata + safe source)

    @Test func inspectedFileCarriesMetadataAndSafeSource() throws {
        let object = try exportValue(report(status: .completed))
        let file = try #require(object["inspectedFile"])

        #expect(file["name"]?.string == "interview-side-a.m4a")
        #expect(file["fileExtension"]?.string == "m4a")
        #expect(file["sizeBytes"]?.int == 8_421_376)
        #expect(file["modifiedAt"]?.string == "2026-06-12T09:03:00Z")

        let source = try #require(file["source"])
        #expect(source["kind"]?.string == "userSelectedLocalFile")
        #expect(source["displayName"]?.string == "interview-side-a.m4a")
        #expect(source["locationDisclosure"]?.string == "omitted")
    }

    @Test func nullableFileMetadataIsExplicitNullNotOmitted() throws {
        let file = AudioFileReference(
            displayName: "broken.wav",
            fileExtension: nil,
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "broken.wav", locationDisclosure: .omitted)
        )
        let subject = InspectionReport(file: file, properties: TechnicalProperties(), warnings: [], status: .completed)
        let object = try exportValue(subject)
        let inspected = try #require(object["inspectedFile"])

        // The keys are present (not omitted) and hold an explicit JSON `null`.
        for key in ["fileExtension", "sizeBytes", "modifiedAt"] {
            #expect(inspected[key] != nil, "\(key) must be present")
            #expect(inspected[key]?.isNull == true, "\(key) must be explicit null")
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
        let subject = InspectionReport(file: file, properties: allAvailableProperties(), warnings: [], status: .completed)
        let object = try exportValue(subject)

        // No location-bearing key exists anywhere in the decoded object.
        let forbidden: Set<String> = [
            "path", "url", "fileURL", "absolutePath", "bookmark", "securityScopedBookmark",
            "parentDirectory", "directory", "location", "bookmarkData",
        ]
        #expect(allKeys(object).isDisjoint(with: forbidden))

        // `inspectedFile` and `source` expose exactly the safe key sets — nothing more.
        let inspected = try #require(object["inspectedFile"])
        #expect(try #require(inspected.keys) == ["name", "fileExtension", "sizeBytes", "modifiedAt", "source"])
        let source = try #require(inspected["source"])
        #expect(try #require(source.keys) == ["kind", "displayName", "locationDisclosure"])
    }

    // MARK: - technicalProperties — states, value types, units, reasons, errors

    @Test func completedEmitsAllNinePropertyKeys() throws {
        let object = try exportValue(report(properties: allAvailableProperties(), status: .completed))
        let technicalKeys = try #require(object["technicalProperties"]?.keys)
        #expect(technicalKeys == [
            "container", "duration", "sampleRate", "channelCount",
            "bitDepth", "codec", "declaredBitrate", "estimatedBitrate", "averageFileBitrate",
        ])
    }

    @Test func availableValuesAreRealJSONScalarsWithUnits() throws {
        let object = try exportValue(report(properties: allAvailableProperties(), status: .completed))
        let technical = try #require(object["technicalProperties"])

        // String value (no unit).
        let container = try #require(technical["container"])
        #expect(container["state"]?.string == "available")
        #expect(container["value"]?.string == "wav")
        #expect(container["unit"] == nil)

        // Double value with a unit — a real JSON number, not a quoted string.
        let duration = try #require(technical["duration"])
        #expect(duration["value"]?.double == 10.5)
        #expect(duration["value"]?.isNumber == true)
        #expect(duration["unit"]?.string == "seconds")

        // Int value with a unit — a real JSON number.
        let sampleRate = try #require(technical["sampleRate"])
        #expect(sampleRate["value"]?.int == 44_100)
        #expect(sampleRate["value"]?.isNumber == true)
        #expect(sampleRate["unit"]?.string == "hertz")

        // Int value, unitless field → no `unit` key.
        let channelCount = try #require(technical["channelCount"])
        #expect(channelCount["value"]?.int == 2)
        #expect(channelCount["unit"] == nil)
    }

    @Test func unavailableUnsupportedAndFailedHaveNullValueAndTheRightShape() throws {
        var properties = allAvailableProperties()
        properties.declaredBitrate = .unavailable(reason: nil)
        properties.bitDepth = .unsupported(reason: "AAC does not define a PCM bit depth")
        properties.codec = .failed(PropertyFailure(code: .propertyReadError, message: "codec read error"))
        let object = try exportValue(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"])

        // unavailable → value explicit null, no unit/reason/error.
        let declared = try #require(technical["declaredBitrate"])
        #expect(declared["state"]?.string == "unavailable")
        #expect(declared["value"]?.isNull == true)
        #expect(try #require(declared.keys) == ["state", "value"])

        // unsupported → value null, reason present.
        let bitDepth = try #require(technical["bitDepth"])
        #expect(bitDepth["state"]?.string == "unsupported")
        #expect(bitDepth["value"]?.isNull == true)
        #expect(bitDepth["reason"]?.string == "AAC does not define a PCM bit depth")
        #expect(bitDepth["error"] == nil)

        // failed → value null, structured error (stable code + message), no reason/unit.
        let codec = try #require(technical["codec"])
        #expect(codec["state"]?.string == "failed")
        #expect(codec["value"]?.isNull == true)
        let error = try #require(codec["error"])
        #expect(error["code"]?.string == "property_read_error")
        #expect(error["message"]?.string == "codec read error")
        #expect(try #require(codec.keys) == ["state", "value", "error"])
    }

    @Test func uncertainWithValueKeepsValueUnitAndRequiredReason() throws {
        var properties = allAvailableProperties()
        properties.estimatedBitrate = .uncertain(value: 180_904, reason: "estimated from size/duration")
        let object = try exportValue(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"])

        let estimated = try #require(technical["estimatedBitrate"])
        #expect(estimated["state"]?.string == "uncertain")
        #expect(estimated["value"]?.int == 180_904)
        #expect(estimated["unit"]?.string == "bitsPerSecond")
        #expect(estimated["reason"]?.string == "estimated from size/duration")
    }

    @Test func uncertainWithoutValueHasNullValueNoUnitButKeepsReason() throws {
        var properties = allAvailableProperties()
        properties.estimatedBitrate = .uncertain(value: nil, reason: "cannot estimate")
        let object = try exportValue(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"])

        let estimated = try #require(technical["estimatedBitrate"])
        #expect(estimated["state"]?.string == "uncertain")
        #expect(estimated["value"]?.isNull == true)
        #expect(estimated["unit"] == nil) // no value → no unit to attach
        #expect(estimated["reason"]?.string == "cannot estimate")
    }

    /// `averageFileBitrate` exports under its own key, additive to the `schemaVersion` 1 object
    /// (`docs/json-schema-v1.md`), and — per ADR-0018 — is never `available`, so only its `uncertain`
    /// shape is exercised here; `declaredBitrate`/`estimatedBitrate` are unaffected by its presence.
    @Test func averageFileBitrateExportsUnderItsOwnKeyDistinctFromTheOtherTwo() throws {
        var properties = allAvailableProperties()
        properties.declaredBitrate = .unavailable(reason: nil)
        properties.estimatedBitrate = .uncertain(value: 180_904, reason: "framework estimate")
        properties.averageFileBitrate = .uncertain(
            value: 180_857,
            reason: "calculated from size and duration, includes container overhead and artwork"
        )
        let object = try exportValue(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"])

        let average = try #require(technical["averageFileBitrate"])
        #expect(average["state"]?.string == "uncertain")
        #expect(average["value"]?.int == 180_857)
        #expect(average["unit"]?.string == "bitsPerSecond")
        #expect(average["reason"]?.string == "calculated from size and duration, includes container overhead and artwork")

        // The three bitrate keys stay independent — none of this leaked into the other two.
        #expect(technical["declaredBitrate"]?["state"]?.string == "unavailable")
        #expect(technical["estimatedBitrate"]?["value"]?.int == 180_904)
    }

    @Test func averageFileBitrateAbsentIsNullValueWithReasonNoUnit() throws {
        var properties = allAvailableProperties()
        properties.averageFileBitrate = .uncertain(value: nil, reason: "size or duration not available")
        let object = try exportValue(report(properties: properties, status: .partial(message: "x")))
        let technical = try #require(object["technicalProperties"])

        let average = try #require(technical["averageFileBitrate"])
        #expect(average["state"]?.string == "uncertain")
        #expect(average["value"]?.isNull == true)
        #expect(average["unit"] == nil)
        #expect(average["reason"]?.string == "size or duration not available")
    }

    @Test func globalFailureEmitsEmptyTechnicalPropertiesObject() throws {
        // A failed status must yield `{}` — even though the report carries an all-`unavailable` set,
        // the exporter must NOT emit nine `unavailable` entries (the gate is the status).
        let error = InspectionError(code: .fileOpenFailed, message: "The audio file could not be opened.")
        let subject = InspectionReport(
            file: makeReference(),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(error)
        )
        let object = try exportValue(subject)
        // Present as an object, and empty (`{}`) — distinct from a non-object.
        #expect(try #require(object["technicalProperties"]?.keys).isEmpty)
    }

    // MARK: - warnings & status

    @Test func warningsAreCarriedFaithfullyWithStableCodesAndKinds() throws {
        let warnings = [
            InspectionWarning(code: .propertyUnsupported, field: "bitDepth", kind: .unsupported, message: "no bit depth"),
            InspectionWarning(code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable, message: "no size"),
        ]
        let object = try exportValue(report(properties: allAvailableProperties(), warnings: warnings, status: .partial(message: "x")))
        let encoded = try #require(object["warnings"]?.array)

        #expect(encoded.count == 2)
        #expect(encoded[0]["code"]?.string == "property_unsupported")
        #expect(encoded[0]["field"]?.string == "bitDepth")
        #expect(encoded[0]["kind"]?.string == "unsupported")
        #expect(encoded[0]["message"]?.string == "no bit depth")
        // A metadata warning rides through the same array unchanged.
        #expect(encoded[1]["code"]?.string == "metadata_size_unavailable")
        #expect(encoded[1]["field"]?.string == "sizeBytes")
        #expect(encoded[1]["kind"]?.string == "unavailable")
    }

    @Test func exporterAddsNoWarningsOfItsOwn() throws {
        // An empty warnings list stays empty — the exporter never derives warnings.
        let object = try exportValue(report(properties: allAvailableProperties(), warnings: [], status: .completed))
        let encoded = try #require(object["warnings"]?.array)
        #expect(encoded.isEmpty)
    }

    @Test func completedStatusHasNoMessageAndNoError() throws {
        let object = try exportValue(report(status: .completed))
        let status = try #require(object["inspectionStatus"])
        #expect(status["state"]?.string == "completed")
        #expect(status["message"] == nil)
        #expect(status["error"] == nil)
    }

    @Test func partialStatusCarriesMessageButNoError() throws {
        let object = try exportValue(report(status: .partial(message: "some properties missing")))
        let status = try #require(object["inspectionStatus"])
        #expect(status["state"]?.string == "partial")
        #expect(status["message"]?.string == "some properties missing")
        #expect(status["error"] == nil)
    }

    @Test func failedStatusCarriesStableErrorCode() throws {
        let error = InspectionError(code: .fileAccessDenied, message: "access denied")
        let subject = InspectionReport(
            file: makeReference(),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(error)
        )
        let object = try exportValue(subject)
        let status = try #require(object["inspectionStatus"])
        #expect(status["state"]?.string == "failed")
        let encodedError = try #require(status["error"])
        #expect(encodedError["code"]?.string == "file_access_denied")
        // The failed status message mirrors the error message (the domain carries a single narrative).
        #expect(status["message"]?.string == "access denied")
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
        let subject = InspectionReport(
            file: makeReference(modifiedAt: nil),
            properties: TechnicalProperties(),
            warnings: warnings,
            status: .failed(error)
        )
        let object = try exportValue(subject)

        let status = try #require(object["inspectionStatus"])
        #expect(status["state"]?.string == "failed")
        #expect(try #require(object["technicalProperties"]?.keys).isEmpty)
        let encoded = try #require(object["warnings"]?.array)
        #expect(encoded.count == 1)
        #expect(encoded[0]["code"]?.string == "metadata_modified_at_unavailable")
    }

    // MARK: - Encoding errors (non-finite values)

    @Test func nonFiniteValueFailsEncodingInsteadOfEmittingAFiction() throws {
        for badDuration in [Double.nan, .infinity, -.infinity] {
            var properties = allAvailableProperties()
            properties.duration = .available(badDuration)
            let subject = report(properties: properties, status: .completed)
            #expect(throws: (any Error).self) {
                _ = try exportData(subject)
            }
        }
    }
}
