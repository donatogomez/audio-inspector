import AVFoundation
import Foundation

// Shared helpers for tests that need a real audio file on disk: a unique temporary directory and a
// tiny deterministic PCM WAV. Deliberately small and specific — not a fixture framework. No
// repository binaries and no copyrighted audio: every fixture is generated in-test with public
// `AVAudioFile` APIs and removed afterwards.

/// Runs `body` with a fresh temporary directory, removed on every exit path. `body` inherits the
/// caller's isolation (`#isolation`), so `@MainActor` suites can pass an isolated closure without
/// crossing an actor boundary.
func withTemporaryDirectory<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: (URL) async throws -> T
) async throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("audioinspector-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

/// Writes a tiny deterministic PCM WAV: 44 100 Hz, mono, 16-bit, 0.1 s of a low-amplitude 440 Hz
/// sine — non-trivial but small. The bytes are a pure function of these parameters, so the same call
/// always produces the same file.
func writePCMFixture(to url: URL) throws {
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
