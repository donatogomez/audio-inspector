import AVFoundation
import AudioInspectorDomain
@testable import AudioInspectorMedia
import CryptoKit
import Foundation
import Testing

// The MP3 row of the group-0 acceptance matrix — the one case macOS cannot produce for itself.
//
// **This is local evidence, and it is explicitly NOT CI coverage.** `.github/workflows/ci.yml` runs on
// `macos-26` and installs no FFmpeg, so this suite skips on every CI run. A skip proves nothing and
// must never be counted as a passing row: the change's task 0.6 says so, `design.md` §9 says so, and
// the spike report says so in stronger terms still. Nothing may cite a skipped run as MP3 support.
//
// FFmpeg is used **only** to produce a fixture, never to decode one and never to establish a fact:
// every assertion below is about what the production adapter did with the file. macOS has an MP3
// decoder but no MP3 encoder — `afconvert -f 'MPG3' -d '.mp3'` fails with
// `ExtAudioFileSetProperty ('cfmt') failed ('fmt?')` — so the fixture has to come from somewhere, and
// FFmpeg is already a declared dev/test-only dependency (ADR-0003). It becomes neither a production
// nor a CI dependency here, and no audio binary enters the repository: the file is generated into a
// temporary directory and removed with it.

// MARK: - Locating the tool

/// The FFmpeg command line, if this machine has one.
///
/// Locating it is a filesystem lookup rather than a process launch, because the result gates the suite
/// and is evaluated while the tests are being collected.
enum FFmpegTool {
    /// The first executable `ffmpeg` on `PATH`, falling back to the two locations Homebrew uses.
    static let executable: URL? = {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let searched = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        return searched
            .map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    static var isAvailable: Bool { executable != nil }

    /// What went wrong, kept separate from the adapter's error space — this is the harness failing,
    /// not the code under test, and the two must never be confused for one another.
    struct Failure: Error, CustomStringConvertible {
        let arguments: [String]
        let status: Int32
        let output: String

        var description: String {
            "ffmpeg \(arguments.joined(separator: " ")) exited \(status):\n\(output)"
        }
    }

    /// Runs FFmpeg with a **separated argument vector** — never a shell string, so nothing in a path
    /// can be interpreted as a command. Throws on a non-zero exit: a fixture that was not produced is
    /// a failure of this test, never a reason to skip it.
    @discardableResult
    static func run(_ arguments: [String]) throws -> String {
        guard let executable else {
            throw Failure(arguments: arguments, status: -1, output: "no ffmpeg on this machine")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw Failure(arguments: arguments, status: process.terminationStatus, output: output)
        }
        return output
    }

    /// The exact build in use, recorded with the evidence so a later run can be compared against it.
    static func versionLine() throws -> String {
        let output = try run(["-hide_banner", "-nostdin", "-version"])
        return output.split(separator: "\n").first.map(String.init) ?? "unknown"
    }
}

// MARK: - The MP3 row

@Suite(
    "Media — MP3 waveform generation (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.isAvailable,
        "FFmpeg is not installed on this machine, so no MP3 fixture can be produced. This suite is SKIPPED, and a skipped run is NOT evidence of MP3 support — task 0.6 stays open."
    )
)
struct MP3WaveformEvidenceTests {

    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture",
            fileExtension: "mp3",
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func generator(
        for url: URL,
        chunkFrames: AVAudioFrameCount = AVFoundationWaveformGenerator.defaultChunkFrames
    ) -> AVFoundationWaveformGenerator {
        AVFoundationWaveformGenerator(chunkFrames: chunkFrames, resolveURL: { _ in url })
    }

    private func sha256(of url: URL) throws -> String {
        try SHA256.hash(data: Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// The source is **ours**: written by the same deterministic fixture writer every other row uses,
    /// so the audio FFmpeg encodes is a pure function of parameters in this repository rather than
    /// anything FFmpeg invented. A prime frame count leaves a short final chunk at every chunk size
    /// above one, and the two channels carry different frequencies so they are not copies.
    private var source: AudioFixtureSpec {
        AudioFixtureSpec(
            name: "mp3-source",
            format: .wav,
            signal: .perChannelSine(frequencies: [440, 660], amplitude: 0.5),
            sampleRate: 44_100,
            channels: 2,
            frames: framesWithShortFinalChunkAtAnyChunkSize
        )
    }

    /// Encodes the source to MP3 with pinned, explicit parameters and returns where it landed.
    ///
    /// Constant bitrate, the sample rate and channel count carried through unchanged, and metadata
    /// stripped, so the file is described entirely by this call.
    private func encodeMP3(from wav: URL, in directory: URL) throws -> URL {
        let mp3 = directory.appendingPathComponent("mp3-fixture.mp3")
        try FFmpegTool.run([
            "-hide_banner", "-nostdin", "-y",
            "-i", wav.path,
            "-map_metadata", "-1",
            "-c:a", "libmp3lame",
            "-b:a", "192k",
            "-ar", "44100",
            "-ac", "2",
            mp3.path,
        ])
        return mp3
    }

    // MARK: The evidence

    /// The whole MP3 case in one run: encode, decode with the **production** adapter, and assert what
    /// the envelope must satisfy — plus that the file came back byte-identical.
    ///
    /// Decoded samples are deliberately **not** compared against the source: MP3 is lossy, so any such
    /// comparison would be asserting the encoder's psychoacoustics. What is compared instead is
    /// structural — the shape of the envelope — and the file against itself at different chunk sizes.
    @Test("a real MP3 decodes through the production adapter into a coherent envelope")
    func mp3DecodesToACoherentEnvelope() async throws {
        try await withTemporaryDirectory { directory in
            let ffmpegVersion = try FFmpegTool.versionLine()

            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = try encodeMP3(from: wav, in: directory)

            let digestBefore = try sha256(of: mp3)
            let sizeBefore = try #require(
                try FileManager.default.attributesOfItem(atPath: mp3.path)[.size] as? Int
            )

            // The production adapter, with its production chunk size. Not a harness, not a copy.
            let envelope = try #require(
                await generator(for: mp3).makeWaveform(for: reference()),
                "the adapter reported an absence for a decodable MP3"
            )

            // Shape.
            #expect(envelope.frameCount > 0)
            #expect(envelope.channelCount == 2)
            #expect(!envelope.buckets.isEmpty)
            #expect(envelope.buckets.count <= WaveformBucketMapping.defaultMaximumBucketCount)
            #expect(envelope.buckets.count == min(2_048, envelope.frameCount))

            // Every bucket is describable: finite, ordered. The domain type refuses anything else, so
            // this asserts that the adapter never had to invent a value to keep going.
            for bucket in envelope.buckets {
                #expect(bucket.minimum.isFinite && bucket.maximum.isFinite)
                #expect(bucket.minimum <= bucket.maximum)
            }

            // The signal survived: a lossy encoder changes the samples, but it does not flatten a
            // half-scale tone into silence.
            #expect(envelope.buckets.contains { $0.maximum > 0.3 })
            #expect(envelope.buckets.contains { $0.minimum < -0.3 })

            // The source is untouched — the adapter only reads.
            #expect(try sha256(of: mp3) == digestBefore)
            #expect(try FileManager.default.attributesOfItem(atPath: mp3.path)[.size] as? Int == sizeBefore)

            // Nothing was written outside the temporary directory this test owns.
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(contents == ["mp3-fixture.mp3", "mp3-source.wav"])

            // Recorded so the run that closed task 0.6 can be compared against a later one. The
            // decoded length is *observed*, never asserted equal to the source: an encoder is entitled
            // to its own delay and padding, and forcing the two to match would be asserting a property
            // of LAME rather than of the adapter.
            print("""
            MP3 evidence (local, not CI coverage)
              ffmpeg:            \(ffmpegVersion)
              encoder:           libmp3lame, CBR 192k, 44100 Hz, 2 ch, metadata stripped
              source frames:     \(source.frames) @ \(Int(source.sampleRate)) Hz, 2 ch
              mp3 sha256:        \(digestBefore)
              mp3 size:          \(sizeBefore) bytes
              decoded frames:    \(envelope.frameCount)
              buckets:           \(envelope.buckets.count)
            """)
        }
    }

    /// The `frameLength` invariant, over MP3 specifically.
    ///
    /// Identical envelopes across chunk sizes is something only a `frameLength`-bounded reader can
    /// achieve: the region past the reported frame count differs with the buffer's capacity, so a
    /// reader that consumed the capacity would disagree with itself here. The frame count is prime, so
    /// every one of these sizes leaves a short final chunk.
    @Test(
        "the same MP3 yields the same envelope at every chunk size",
        arguments: [AVAudioFrameCount(1), 3, 127, 1_152, 4_096]
    )
    func chunkSizeDoesNotChangeTheMP3Envelope(chunkFrames: AVAudioFrameCount) async throws {
        try await withTemporaryDirectory { directory in
            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = try encodeMP3(from: wav, in: directory)

            let whole = try #require(await generator(for: mp3, chunkFrames: 65_536).makeWaveform(for: reference()))
            let chunked = try #require(await generator(for: mp3, chunkFrames: chunkFrames).makeWaveform(for: reference()))

            #expect(chunked == whole, "chunk size \(chunkFrames) changed the MP3 envelope")
        }
    }

    /// A file named `.mp3` that is not audio is refused at the door, and the refusal names no path and
    /// no framework — MP3 uses the same error space as every other format.
    @Test("a file that is not audio is refused without disclosing a path or a framework error")
    func aFileThatIsNotAudioIsRefusedCleanly() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("not-audio.mp3")
            try Data("this is not audio".utf8).write(to: url)

            let error = await #expect(throws: WaveformError.self) {
                _ = try await generator(for: url).makeWaveform(for: reference())
            }
            #expect(error?.code == .fileOpenFailed)
            let message = try #require(error?.message)
            #expect(!message.contains("/"), "a path reached the error message")
            #expect(!message.lowercased().contains("avaudio"), "a framework name reached the error message")
            #expect(!message.contains(directory.path))
        }
    }

    /// **Observed, and different from every other format in the matrix.** MP3 is a stream of
    /// self-delimiting frames with no global header the decoder depends on, so damaging the beginning
    /// of the file does not stop it: the decoder resynchronises at the next frame boundary, reports a
    /// shorter length, and the adapter produces a complete envelope of *that* shorter file.
    ///
    /// This is recorded rather than corrected. The adapter's job is to describe what the file declares,
    /// and a file that declares fewer frames after losing some is being honest. Asserted qualitatively
    /// so the case does not become a pin on one encoder's exact framing.
    @Test("a damaged MP3 resynchronises and yields a shorter envelope rather than an error")
    func aDamagedMP3ResynchronisesRatherThanFailing() async throws {
        try await withTemporaryDirectory { directory in
            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = try encodeMP3(from: wav, in: directory)
            try corruptFixture(at: mp3, replacingBytesIn: 0 ..< 4_096, with: 0xFF)

            let envelope = try #require(
                await generator(for: mp3).makeWaveform(for: reference()),
                "a damaged MP3 that still opens should describe what is left of it"
            )
            #expect(envelope.frameCount > 0)
            #expect(envelope.frameCount < Int(source.frames), "the damaged region should be gone, not invented")
            #expect(envelope.channelCount == 2)
            #expect(envelope.buckets.count == min(2_048, envelope.frameCount))
        }
    }

    /// **The case MP3 brings that no other format in the matrix does:** its length can be *declared*
    /// by a header while the frames behind it are missing. LAME writes a Xing/Info header carrying the
    /// total duration, and CoreAudio believes it — so a truncated MP3 opens and reports the full
    /// original length.
    ///
    /// The adapter must not draw that. It reads while `framePosition < length`, finds the frames are
    /// not there, and refuses rather than presenting a partial envelope as a complete one. That is the
    /// `readFailed` path existing precisely for this, and MP3 is the format that exercises it.
    @Test("a truncated MP3 whose header still declares the full length is refused, not half-drawn")
    func aTruncatedMP3IsRefusedRatherThanHalfDrawn() async throws {
        try await withTemporaryDirectory { directory in
            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = try encodeMP3(from: wav, in: directory)
            try truncateFixture(at: mp3, toFirst: 2_000)

            let error = await #expect(throws: WaveformError.self) {
                _ = try await generator(for: mp3).makeWaveform(for: reference())
            }
            #expect(error?.code == .readFailed)
            let message = try #require(error?.message)
            #expect(!message.contains("/"), "a path reached the error message")
            #expect(!message.contains(directory.path))
        }
    }
}
