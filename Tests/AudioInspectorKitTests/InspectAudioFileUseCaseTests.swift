import Foundation
import Testing

@testable import AudioInspectorDomain
import AudioInspectorTesting

/// Use-case tests for the basic-inspection slice (group 2). Everything runs against the scripted
/// `FakeAudioFilePropertyReading` — no real files, no AVFoundation, no JSON.
@Suite("Use case — InspectAudioFileUseCase")
struct InspectAudioFileUseCaseTests {

    // MARK: - Helpers

    private func makeReference(displayName: String = "clip.wav") -> AudioFileReference {
        AudioFileReference(
            displayName: displayName,
            fileExtension: "wav",
            sizeBytes: 1_024,
            modifiedAt: Date(timeIntervalSince1970: 0),
            source: .userSelectedLocalFile(displayName: displayName, locationDisclosure: .omitted)
        )
    }

    /// Every field cleanly `available` — the fully successful shape.
    private func allAvailableProperties() -> TechnicalProperties {
        TechnicalProperties(
            container: .available("wav"),
            duration: .available(10.0),
            sampleRate: .available(44_100),
            channelCount: .available(2),
            bitDepth: .available(16),
            codec: .available("pcm"),
            declaredBitrate: .available(1_411_200),
            estimatedBitrate: .available(1_411_200)
        )
    }

    // MARK: - 1. Fully successful

    @Test func successfulInspectionIsCompletedWithNoWarnings() async {
        let ref = makeReference()
        let reader = FakeAudioFilePropertyReading(succeedingWith: allAvailableProperties())
        let useCase = InspectAudioFileUseCase(reader: reader)

        let report = await useCase.execute(file: ref)

        #expect(report.status == .completed)
        #expect(report.warnings.isEmpty)
        #expect(report.file.id == ref.id)
        #expect(report.properties.sampleRate.value == 44_100)
        #expect(await reader.callCount == 1)
        #expect(await reader.lastFile?.id == ref.id)
    }

    // MARK: - 2. Unavailable

    @Test func unavailablePropertyYieldsPartialWithUnavailableWarning() async {
        var props = allAvailableProperties()
        props.bitDepth = .unavailable(reason: nil)
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())

        // `partial` carries a deterministic message (asserted once here for stability).
        #expect(report.status == .partial(message: "Some properties could not be read cleanly; see warnings for details."))
        #expect(report.warnings.count == 1)
        let warning = report.warnings[0]
        #expect(warning.code == .propertyUnavailable)
        #expect(warning.kind == .unavailable)
        #expect(warning.field == "bitDepth")
    }

    // MARK: - 3. Unsupported

    @Test func unsupportedPropertyYieldsPartialWithUnsupportedWarning() async {
        var props = allAvailableProperties()
        props.bitDepth = .unsupported(reason: "AAC has no PCM bit depth")
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 1)
        #expect(report.warnings[0].code == .propertyUnsupported)
        #expect(report.warnings[0].kind == .unsupported)
        #expect(report.warnings[0].field == "bitDepth")
    }

    // MARK: - 4. Uncertain with value (value preserved)

    @Test func uncertainWithValueYieldsWarningAndKeepsValue() async {
        var props = allAvailableProperties()
        props.estimatedBitrate = .uncertain(value: 180_904, reason: "estimated from size/duration")
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 1)
        #expect(report.warnings[0].code == .propertyUncertain)
        #expect(report.warnings[0].field == "estimatedBitrate")
        // The carried value is passed through untouched.
        #expect(report.properties.estimatedBitrate.value == 180_904)
    }

    // MARK: - 5. Uncertain without value

    @Test func uncertainWithoutValueYieldsWarning() async {
        var props = allAvailableProperties()
        props.estimatedBitrate = .uncertain(value: nil, reason: "cannot estimate")
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 1)
        #expect(report.warnings[0].code == .propertyUncertain)
        #expect(report.warnings[0].field == "estimatedBitrate")
        #expect(report.properties.estimatedBitrate.value == nil)
    }

    // MARK: - 6. Failed by property (property failure code preserved)

    @Test func failedPropertyYieldsExtractionFailedWarningAndKeepsFailureCode() async {
        var props = allAvailableProperties()
        props.codec = .failed(PropertyFailure(code: .propertyReadError, message: "codec read error"))
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 1)
        #expect(report.warnings[0].code == .propertyExtractionFailed)
        #expect(report.warnings[0].field == "codec")
        // The property-level failure is preserved verbatim in the report's properties.
        guard case let .failed(failure) = report.properties.codec else {
            Issue.record("expected codec to stay failed"); return
        }
        #expect(failure.code == .propertyReadError)
        #expect(failure.message == "codec read error")
    }

    // MARK: - 7. Multiple problematic properties (deterministic order, no duplicates)

    @Test func multipleProblematicPropertiesYieldOneWarningEachInFieldOrder() async {
        var props = allAvailableProperties()
        props.container = .unavailable(reason: nil)
        props.bitDepth = .unsupported(reason: "lossy")
        props.codec = .failed(PropertyFailure(code: .propertyReadError, message: "x"))
        props.estimatedBitrate = .uncertain(value: nil, reason: "y")
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())

        #expect(isPartial(report.status))
        // One warning per problematic property, in declared field order — no duplicates.
        #expect(report.warnings.map(\.field) == ["container", "bitDepth", "codec", "estimatedBitrate"])
        #expect(report.warnings.map(\.code) == [
            .propertyUnavailable, .propertyUnsupported, .propertyExtractionFailed, .propertyUncertain,
        ])
        #expect(Set(report.warnings.map(\.field)).count == report.warnings.count)
    }

    // MARK: - 8. Global reader failure

    @Test func globalReaderFailureYieldsFailedStatusWithSafeEmptyReport() async {
        let ref = makeReference()
        let error = InspectionError(code: .fileOpenFailed, message: "could not open")
        let reader = FakeAudioFilePropertyReading(failingWith: error)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: ref)

        // The reference is preserved; the original typed error rides in `.failed`.
        #expect(report.file.id == ref.id)
        #expect(report.status == .failed(error))
        // No warnings on a global failure; properties are the explicit all-`unavailable` set.
        #expect(report.warnings.isEmpty)
        #expect(report.properties == TechnicalProperties())
        #expect(await reader.callCount == 1)
    }

    // MARK: - 9. Reader invoked exactly once

    @Test func readerIsInvokedExactlyOnce() async {
        let reader = FakeAudioFilePropertyReading(succeedingWith: allAvailableProperties())
        _ = await InspectAudioFileUseCase(reader: reader).execute(file: makeReference())
        #expect(await reader.callCount == 1)
    }

    // MARK: - 10. Sendable (verified by compilation)

    @Test func useCaseAndFakeAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(InspectAudioFileUseCase.self)
        requireSendable(FakeAudioFilePropertyReading.self)
    }

    // MARK: - 11. Descriptive-metadata warnings (task 2.4)

    @Test func missingSizeYieldsMetadataWarningAndPartial() async {
        let ref = reference(sizeBytes: nil, modifiedAt: Date(timeIntervalSince1970: 0))
        let reader = FakeAudioFilePropertyReading(succeedingWith: allAvailableProperties())

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: ref)

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 1)
        #expect(hasWarning(report.warnings, code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable))
    }

    @Test func missingModifiedAtYieldsMetadataWarningAndPartial() async {
        let ref = reference(sizeBytes: 1_024, modifiedAt: nil)
        let reader = FakeAudioFilePropertyReading(succeedingWith: allAvailableProperties())

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: ref)

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 1)
        #expect(hasWarning(report.warnings, code: .metadataModifiedAtUnavailable, field: "modifiedAt", kind: .unavailable))
    }

    @Test func bothMetadataMissingYieldsTwoDistinctWarningsAndPartial() async {
        let ref = reference(sizeBytes: nil, modifiedAt: nil)
        let reader = FakeAudioFilePropertyReading(succeedingWith: allAvailableProperties())

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: ref)

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 2)
        #expect(hasWarning(report.warnings, code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable))
        #expect(hasWarning(report.warnings, code: .metadataModifiedAtUnavailable, field: "modifiedAt", kind: .unavailable))
        expectNoDuplicateWarnings(report.warnings)
    }

    @Test func metadataAndTechnicalWarningsCombineWithoutDuplicates() async {
        var props = allAvailableProperties()
        props.bitDepth = .unavailable(reason: nil) // one technical warning
        let ref = reference(sizeBytes: nil, modifiedAt: Date(timeIntervalSince1970: 0))
        let reader = FakeAudioFilePropertyReading(succeedingWith: props)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: ref)

        #expect(isPartial(report.status))
        #expect(report.warnings.count == 2)
        // Both a technical and a metadata warning are present — checked by identity, not by order.
        #expect(hasWarning(report.warnings, code: .propertyUnavailable, field: "bitDepth", kind: .unavailable))
        #expect(hasWarning(report.warnings, code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable))
        expectNoDuplicateWarnings(report.warnings)
    }

    @Test func globalFailureWithMissingMetadataStaysFailedButIncludesMetadataWarnings() async {
        let ref = reference(sizeBytes: nil, modifiedAt: nil)
        let error = InspectionError(code: .fileOpenFailed, message: "could not open")
        let reader = FakeAudioFilePropertyReading(failingWith: error)

        let report = await InspectAudioFileUseCase(reader: reader).execute(file: ref)

        // Status preserved as `.failed` — never recomputed to `.partial`, even with warnings present.
        #expect(report.status == .failed(error))
        // Properties stay the safe all-`unavailable` set (the exporter maps this to `{}`).
        #expect(report.properties == TechnicalProperties())
        // Metadata warnings ARE derived on the global-failure path.
        #expect(report.warnings.count == 2)
        #expect(hasWarning(report.warnings, code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable))
        #expect(hasWarning(report.warnings, code: .metadataModifiedAtUnavailable, field: "modifiedAt", kind: .unavailable))
    }

    // MARK: - Local helpers

    private func reference(sizeBytes: Int?, modifiedAt: Date?) -> AudioFileReference {
        AudioFileReference(
            displayName: "clip.wav",
            fileExtension: "wav",
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            source: .userSelectedLocalFile(displayName: "clip.wav", locationDisclosure: .omitted)
        )
    }

    private func hasWarning(_ warnings: [InspectionWarning], code: WarningCode, field: String, kind: WarningKind) -> Bool {
        warnings.contains { $0.code == code && $0.field == field && $0.kind == kind }
    }

    private func expectNoDuplicateWarnings(_ warnings: [InspectionWarning]) {
        let keys = warnings.map { "\($0.code.rawValue)|\($0.field ?? "")" }
        #expect(Set(keys).count == keys.count)
    }

    private func isPartial(_ status: InspectionStatus) -> Bool {
        if case .partial = status { return true }
        return false
    }
}
