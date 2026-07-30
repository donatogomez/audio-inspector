import Foundation
import Testing

@testable import AudioInspectorDomain

/// Domain-model tests for the basic-inspection slice (group 1). Pure value types only — no files,
/// no JSON, no AVFoundation.
@Suite("Domain — inspection models")
struct DomainInspectionModelsTests {

    // MARK: - Property (exhaustive state/value model)

    @Test func availableCarriesItsValue() {
        let p = Property.available(44_100)
        #expect(p.value == 44_100)
    }

    @Test func unavailableAndUnsupportedCarryNoValue() {
        #expect(Property<Int>.unavailable(reason: nil).value == nil)
        #expect(Property<Int>.unsupported(reason: "AAC has no PCM bit depth").value == nil)
    }

    @Test func uncertainWithAndWithoutValue() {
        let withValue = Property.uncertain(value: 180_904, reason: "estimated from size/duration")
        let withoutValue = Property<Int>.uncertain(value: nil, reason: "unreliable")
        #expect(withValue.value == 180_904)
        #expect(withoutValue.value == nil)
        // `reason` is part of the case, so an `uncertain` without a reason cannot be constructed.
    }

    @Test func failedCarriesPropertyFailureWithStableCodeAndMessage() {
        let p = Property<Int>.failed(PropertyFailure(code: .propertyReadError, message: "boom"))
        #expect(p.value == nil)
        guard case let .failed(failure) = p else { Issue.record("expected failed"); return }
        #expect(failure.code == .propertyReadError)
        #expect(failure.message == "boom")
    }

    @Test func propertyEquality() {
        #expect(Property.available(2) == Property.available(2))
        #expect(Property.available(2) != Property.available(3))
        #expect(Property<Int>.available(2) != Property<Int>.unavailable(reason: nil))
        #expect(Property<Int>.unsupported(reason: "x") != Property<Int>.unsupported(reason: "y"))
    }

    // MARK: - Stable codes (identity must not drift)

    @Test func warningCodeRawValuesAreStable() {
        #expect(WarningCode.metadataSizeUnavailable.rawValue == "metadata_size_unavailable")
        #expect(WarningCode.metadataModifiedAtUnavailable.rawValue == "metadata_modified_at_unavailable")
        #expect(WarningCode.propertyUnavailable.rawValue == "property_unavailable")
        #expect(WarningCode.propertyUnsupported.rawValue == "property_unsupported")
        #expect(WarningCode.propertyUncertain.rawValue == "property_uncertain")
        #expect(WarningCode.propertyExtractionFailed.rawValue == "property_extraction_failed")
    }

    @Test func inspectionErrorCodeRawValuesAreStable() {
        // Global inspection errors only.
        #expect(InspectionErrorCode.fileOpenFailed.rawValue == "file_open_failed")
        #expect(InspectionErrorCode.fileUnreadable.rawValue == "file_unreadable")
        #expect(InspectionErrorCode.fileAccessDenied.rawValue == "file_access_denied")
    }

    @Test func propertyFailureCodeRawValuesAreStable() {
        // Per-property failures only — distinct code space from global inspection errors.
        #expect(PropertyFailureCode.propertyReadError.rawValue == "property_read_error")
    }

    @Test func errorIdentityIsTheCodeNotTheMessage() {
        // Same code, different messages → same code identity (messages are descriptive only).
        let a = InspectionError(code: .fileOpenFailed, message: "could not open")
        let b = InspectionError(code: .fileOpenFailed, message: "open failed")
        #expect(a.code == b.code)
        #expect(a != b) // the value still differs by message; identity for processing is `.code`
    }

    // MARK: - File source & reference (safe, no location)

    @Test func audioFileSourceIsSafeAndClosed() {
        let source = AudioFileSource.userSelectedLocalFile(displayName: "song.flac", locationDisclosure: .omitted)
        guard case let .userSelectedLocalFile(displayName, disclosure) = source else {
            Issue.record("expected userSelectedLocalFile"); return
        }
        #expect(displayName == "song.flac")
        #expect(disclosure == .omitted)
    }

    @Test func audioFileReferenceHoldsOnlySafeMetadata() {
        let ref = AudioFileReference(
            displayName: "song.flac",
            fileExtension: "flac",
            sizeBytes: 31_457_280,
            modifiedAt: Date(timeIntervalSince1970: 0),
            source: .userSelectedLocalFile(displayName: "song.flac", locationDisclosure: .omitted)
        )
        #expect(ref.displayName == "song.flac")
        #expect(ref.fileExtension == "flac")
        #expect(ref.sizeBytes == 31_457_280)
        #expect(ref.modifiedAt == Date(timeIntervalSince1970: 0))
    }

    @Test func audioFileReferenceIdsAreEphemeralAndDistinct() {
        let source = AudioFileSource.userSelectedLocalFile(displayName: "a", locationDisclosure: .omitted)
        let a = AudioFileReference(displayName: "a", fileExtension: nil, sizeBytes: nil, modifiedAt: nil, source: source)
        let b = AudioFileReference(displayName: "a", fileExtension: nil, sizeBytes: nil, modifiedAt: nil, source: source)
        #expect(a.id != b.id) // auto-generated per instance; not a stable cross-session key
    }

    // MARK: - Technical properties (mixed states)

    @Test func technicalPropertiesDefaultToUnavailable() {
        let props = TechnicalProperties()
        #expect(props.duration.value == nil)
        #expect(props.container.value == nil)
    }

    @Test func technicalPropertiesWithMixedStates() {
        let props = TechnicalProperties(
            container: .available("mpeg-4"),
            duration: .available(372.51),
            sampleRate: .available(44_100),
            channelCount: .available(2),
            bitDepth: .unsupported(reason: "AAC does not define a PCM bit depth"),
            codec: .available("aac"),
            declaredBitrate: .available(128_000),
            estimatedBitrate: .uncertain(value: 180_904, reason: "estimated from size/duration")
        )
        #expect(props.container.value == "mpeg-4")
        #expect(props.sampleRate.value == 44_100)
        #expect(props.bitDepth.value == nil)
        #expect(props.estimatedBitrate.value == 180_904)
        #expect(props == props) // Equatable
    }

    // MARK: - Warnings

    @Test func inspectionWarningIsTyped() {
        let w = InspectionWarning(
            code: .propertyUnsupported,
            field: "bitDepth",
            kind: .unsupported,
            message: "Bit depth is not defined for this lossy codec."
        )
        #expect(w.code == .propertyUnsupported)
        #expect(w.field == "bitDepth")
        #expect(w.kind == .unsupported)
    }

    // MARK: - Inspection status

    @Test func inspectionStatusCases() {
        #expect(InspectionStatus.completed == .completed)
        #expect(InspectionStatus.partial(message: nil) != .completed)
        let failed = InspectionStatus.failed(InspectionError(code: .fileOpenFailed, message: "no"))
        guard case let .failed(error) = failed else { Issue.record("expected failed"); return }
        #expect(error.code == .fileOpenFailed)
    }

    // MARK: - Full report

    @Test func inspectionReportAggregatesDomainDataOnly() {
        let ref = AudioFileReference(
            displayName: "interview.m4a",
            fileExtension: "m4a",
            sizeBytes: 8_421_376,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "interview.m4a", locationDisclosure: .omitted)
        )
        let props = TechnicalProperties(
            container: .available("mpeg-4"),
            duration: .available(372.51),
            bitDepth: .unsupported(reason: "AAC")
        )
        let warnings = [
            InspectionWarning(code: .propertyUnsupported, field: "bitDepth", kind: .unsupported, message: "n/a"),
        ]
        let report = InspectionReport(
            file: ref,
            properties: props,
            warnings: warnings,
            status: .partial(message: "Some properties are not exposed by this format.")
        )
        #expect(report.warnings.count == 1)
        #expect(report.properties.container.value == "mpeg-4")
        #expect(report == report) // Equatable
    }

    // MARK: - Sendable (verified by compilation)

    @Test func modelsAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(Property<Int>.self)
        requireSendable(Property<String>.self)
        requireSendable(InspectionError.self)
        requireSendable(InspectionErrorCode.self)
        requireSendable(PropertyFailure.self)
        requireSendable(PropertyFailureCode.self)
        requireSendable(WarningCode.self)
        requireSendable(WarningKind.self)
        requireSendable(InspectionWarning.self)
        requireSendable(AudioFileSource.self)
        requireSendable(LocationDisclosure.self)
        requireSendable(AudioFileReference.self)
        requireSendable(TechnicalProperties.self)
        requireSendable(InspectionStatus.self)
        requireSendable(InspectionReport.self)
    }
}
