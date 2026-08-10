import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import AudioInspectorMedia
import AudioInspectorDomain

/// Task 3.7 — the **minimal integration** coverage for `AVFoundationAudioFilePropertyReader`.
///
/// A tiny deterministic PCM fixture is generated **in-test** with public `AVAudioFile` APIs, written to
/// a unique temporary directory, inspected through the real reader, and deleted via `defer`. No audio
/// binary enters the repo, no network, no copyrighted material (a low-amplitude synthetic sine). The
/// remaining tests cover the deterministic **global-throw** paths (a missing resolved URL, a missing
/// file, unreadable non-audio bytes). Formats macOS can read but not reliably generate in CI (lossy,
/// FLAC/ALAC) are intentionally out of scope here — validated by spike 0031, not a CI codec matrix.
@Suite("Media — AVFoundation reader integration (in-test PCM fixture)")
struct AVFoundationPropertyReaderIntegrationTests {

    // MARK: - Fixture spec

    /// A deterministic PCM fixture recipe. `Sendable` so it can drive a parameterized test.
    struct FixtureSpec: Sendable {
        let fileExtension: String
        let sampleRate: Double
        let channels: AVAudioChannelCount
        let bitDepth: Int
        let bigEndian: Bool
        let seconds: Double
        /// The extension-derived UTI the `container` mapper is expected to surface (as `uncertain`).
        let expectedContainerUTI: String

        static let wav = FixtureSpec(
            fileExtension: "wav",
            sampleRate: 44_100,
            channels: 2,
            bitDepth: 16,
            bigEndian: false,
            seconds: 0.25,
            expectedContainerUTI: UTType.wav.identifier
        )

        static let aiff = FixtureSpec(
            fileExtension: "aiff",
            sampleRate: 22_050,
            channels: 1,
            bitDepth: 16,
            bigEndian: true,
            seconds: 0.5,
            expectedContainerUTI: UTType.aiff.identifier
        )
    }

    // MARK: - Happy path: a PCM fixture maps into domain properties

    @Test(arguments: [FixtureSpec.wav, FixtureSpec.aiff])
    func pcmFixtureIsInspectedIntoDomainProperties(spec: FixtureSpec) async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("fixture.\(spec.fileExtension)")
            try writePCMFixture(spec, to: url)

            let reader = AVFoundationAudioFilePropertyReader { _ in url }
            let properties = try await reader.readProperties(of: Self.makeReference(spec.fileExtension))

            // Reliable stream facts from the ASBD.
            #expect(properties.sampleRate == .available(Int(spec.sampleRate)))
            #expect(properties.channelCount == .available(Int(spec.channels)))
            #expect(properties.bitDepth == .available(spec.bitDepth))
            #expect(properties.codec == .available("lpcm"))

            // A positive, finite duration.
            guard case let .available(seconds) = properties.duration else {
                Issue.record("expected an available duration, got \(properties.duration)"); return
            }
            #expect(seconds > 0)

            // `container` is extension-inferred → uncertain, carrying the (non-localized) UTI.
            guard case let .uncertain(containerUTI, _) = properties.container else {
                Issue.record("expected an uncertain container, got \(properties.container)"); return
            }
            #expect(containerUTI == spec.expectedContainerUTI)

            // Bitrate policy for PCM: no declared source; the estimate is always uncertain; the
            // calculated average is uncertain-without-a-value here because the fixture reference below
            // carries no `sizeBytes` (a real file's own size threads through separately — see the pure
            // mapping tests in `AVFoundationPropertyMappingTests` for the computed-value cases).
            guard case .unavailable = properties.declaredBitrate else {
                Issue.record("expected an unavailable declaredBitrate, got \(properties.declaredBitrate)"); return
            }
            guard case .uncertain = properties.estimatedBitrate else {
                Issue.record("expected an uncertain estimatedBitrate, got \(properties.estimatedBitrate)"); return
            }
            guard case let .uncertain(value, _) = properties.averageFileBitrate else {
                Issue.record("expected an uncertain averageFileBitrate, got \(properties.averageFileBitrate)"); return
            }
            #expect(value == nil) // no sizeBytes in this fixture's reference
        }
    }

    // MARK: - Deterministic global-throw paths

    @Test func absentResolvedURLThrowsFileAccessDenied() async {
        let reader = AVFoundationAudioFilePropertyReader() // default resolver yields no URL
        do {
            _ = try await reader.readProperties(of: Self.makeReference("wav"))
            Issue.record("expected a global InspectionError when no URL is resolvable")
        } catch {
            // Outside the temp-dir closure, the typed throw makes `error` an `InspectionError` directly.
            #expect(error.code == .fileAccessDenied)
        }
    }

    @Test func missingFileThrowsFileOpenFailed() async throws {
        try await withTemporaryDirectory { directory in
            let missing = directory.appendingPathComponent("does-not-exist.wav")
            let reader = AVFoundationAudioFilePropertyReader { _ in missing }
            do {
                _ = try await reader.readProperties(of: Self.makeReference("wav"))
                Issue.record("expected a global InspectionError for a missing file")
            } catch {
                #expect((error as? InspectionError)?.code == .fileOpenFailed)
            }
        }
    }

    @Test func unreadableNonAudioFileThrowsAGlobalInspectionError() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("not-audio.wav")
            try Data("this is plain text, not audio".utf8).write(to: url)

            let reader = AVFoundationAudioFilePropertyReader { _ in url }
            do {
                _ = try await reader.readProperties(of: Self.makeReference("wav"))
                Issue.record("expected a global InspectionError for unreadable media")
            } catch {
                // The exact code is SDK-dependent (spike 0031 caveat), so only a global throw carrying a
                // known global code is asserted here; the code *mapping* is covered deterministically by
                // the in-memory `globalError(from:)` suite.
                let globalCodes: [InspectionErrorCode] = [.fileOpenFailed, .fileUnreadable, .fileAccessDenied]
                let code = (error as? InspectionError)?.code
                #expect(code.map(globalCodes.contains) == true)
            }
        }
    }

    // MARK: - Fixture generation & temp-dir lifecycle (public APIs only; no repo binaries)

    private func makePCMSettings(_ spec: FixtureSpec) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: spec.sampleRate,
            AVNumberOfChannelsKey: spec.channels,
            AVLinearPCMBitDepthKey: spec.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: spec.bigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Writes a small deterministic PCM fixture (WAV or AIFF, decided by the extension) — a low-amplitude
    /// sine, non-trivial but tiny. Public `AVAudioFile`/`AVAudioPCMBuffer` only; no force-unwrap.
    private func writePCMFixture(_ spec: FixtureSpec, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: makePCMSettings(spec))
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount((spec.sampleRate * spec.seconds).rounded())
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for channel in 0 ..< Int(format.channelCount) {
                let frequency = 440.0 * Double(channel + 1)
                for frame in 0 ..< Int(frameCount) {
                    channelData[channel][frame] = Float(0.05 * sin(2.0 * .pi * frequency * Double(frame) / spec.sampleRate))
                }
            }
        }
        try file.write(from: buffer)
    }

    /// Runs `body` with a fresh unique temporary directory that is always removed afterwards.
    private func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audioinspector-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    private static func makeReference(_ fileExtension: String) -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture.\(fileExtension)",
            fileExtension: fileExtension,
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture.\(fileExtension)", locationDisclosure: .omitted)
        )
    }
}
