import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import FeatureImport
@testable import AudioInspectorApp

/// Coordinator tests with the source selector injected — the real `NSOpenPanel` is never opened. The
/// reader is either a confirming fake (deterministic unit tests) or the real AVFoundation reader over
/// a PCM fixture generated in-test (light integration). Temporary files are cleaned up with `defer`.
@MainActor
@Suite("App — source inspection coordinator")
struct SourceInspectionCoordinatorTests {

    /// Signals each read through an injected `@Sendable` callback so "invoked exactly once" is
    /// enforced by Swift Testing's `confirmation` — no shared state, no isolation assumptions.
    private struct ConfirmingReader: AudioFilePropertyReading {
        let properties: TechnicalProperties
        let onRead: @Sendable () -> Void
        func readProperties(of _: AudioFileReference) async throws(InspectionError) -> TechnicalProperties {
            onRead()
            return properties
        }
    }

    /// A reader that always fails the whole file — proves a global failure still yields a report.
    private struct FailingReader: AudioFilePropertyReading {
        let error: InspectionError
        func readProperties(of _: AudioFileReference) async throws(InspectionError) -> TechnicalProperties {
            throw error
        }
    }

    /// A reader that must never run; reaching it fails the test.
    private struct UnreachableReader: AudioFilePropertyReading {
        func readProperties(of _: AudioFileReference) async throws(InspectionError) -> TechnicalProperties {
            Issue.record("the reader must not be reached")
            return TechnicalProperties()
        }
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    // MARK: - Cancellation

    @Test func cancellingThePickerIsNeutralAndInspectsNothing() async {
        let coordinator = SourceInspectionCoordinator(
            chooseSource: { nil },
            makeReader: { _ in UnreachableReader() }
        )

        #expect(await coordinator.inspect() == .cancelled)
    }

    // MARK: - Preparation failure

    @Test func aNonFileURLCannotBePreparedForInspection() async {
        let coordinator = SourceInspectionCoordinator(
            chooseSource: { URL(string: "https://example.com/song.wav") },
            makeReader: { _ in UnreachableReader() }
        )

        #expect(await coordinator.inspect() == .preparationFailed)
    }

    // MARK: - Success

    @Test func inspectsTheSelectedFileExactlyOnceAndReturnsItsReport() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("interview-side-a.m4a")
            try Data(repeating: 0x41, count: 2_048).write(to: url)

            var outcome: SourceInspectionOutcome?
            await confirmation("reader invoked exactly once", expectedCount: 1) { confirmed in
                let coordinator = SourceInspectionCoordinator(
                    chooseSource: { url },
                    makeReader: { _ in
                        ConfirmingReader(
                            properties: TechnicalProperties(sampleRate: .available(44_100)),
                            onRead: { confirmed() }
                        )
                    }
                )
                outcome = await coordinator.inspect()
            }

            guard case let .inspected(report) = outcome else {
                Issue.record("expected an inspected outcome, got \(String(describing: outcome))"); return
            }
            // The report is built from the selected file's own metadata.
            #expect(report.file.displayName == "interview-side-a.m4a")
            #expect(report.file.fileExtension == "m4a")
            #expect(report.file.sizeBytes == 2_048)
            #expect(report.properties.sampleRate == .available(44_100))
        }
    }

    // MARK: - Global failure stays a report

    @Test func aGlobalReadFailureStillProducesAFailedReport() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("broken.wav")
            try Data("not audio".utf8).write(to: url)
            let error = InspectionError(code: .fileUnreadable, message: "unreadable")

            let coordinator = SourceInspectionCoordinator(
                chooseSource: { url },
                makeReader: { _ in FailingReader(error: error) }
            )

            guard case let .inspected(report) = await coordinator.inspect() else {
                Issue.record("a global failure must still be an inspected report"); return
            }
            #expect(report.status == .failed(error))
            #expect(report.properties == TechnicalProperties())
        }
    }

    // MARK: - Light integration (real reader over an in-test PCM fixture)

    @Test func realReaderInspectsAPCMFixtureEndToEnd() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("fixture.wav")
            try Self.writePCMFixture(to: url)

            // Default `makeReader` → the real AVFoundation reader, resolving this URL.
            let coordinator = SourceInspectionCoordinator(chooseSource: { url })

            guard case let .inspected(report) = await coordinator.inspect() else {
                Issue.record("expected an inspected outcome"); return
            }
            #expect(report.file.displayName == "fixture.wav")
            #expect(report.file.sizeBytes != nil)
            #expect(report.properties.sampleRate == .available(44_100))
            #expect(report.properties.channelCount == .available(1))
            #expect(report.properties.codec == .available("lpcm"))
        }
    }

    /// A tiny deterministic PCM WAV written with public `AVAudioFile` APIs — no repository binaries,
    /// no copyrighted audio.
    private static func writePCMFixture(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_410) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = 4_410
        if let channel = buffer.floatChannelData?[0] {
            for frame in 0 ..< Int(buffer.frameLength) {
                channel[frame] = 0.1 * sin(2.0 * .pi * 440.0 * Float(frame) / 44_100.0)
            }
        }
        try file.write(from: buffer)
    }
}
