import AVFoundation
import AudioInspectorDomain
@testable import AudioInspectorMedia
import CryptoKit
import Foundation
import Testing

// The decoder acceptance matrix, run against the **production** adapter over real files it decodes
// itself. Nothing here re-implements the reading loop: every assertion is about the chunks the adapter
// hands over, which is the only surface a regression could hide behind.

@Suite("Media — native PCM decoding")
struct AVFoundationAudioDecoderTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture",
            fileExtension: nil,
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func decoder(for url: URL) -> AVFoundationAudioDecoder {
        AVFoundationAudioDecoder(resolveURL: { _ in url })
    }

    private func sha256(of url: URL) throws -> SHA256Digest {
        try SHA256.hash(data: Data(contentsOf: url))
    }

    /// Everything a decode handed over, gathered by an ordinary local accumulator. That it can be a
    /// plain `var` mutated from inside the callback — no actor, no lock, nothing to await — is the
    /// shape of the port, and every test here depends on it.
    private struct Collected {
        var chunks: [PCMChunk] = []
        var frameTotal: Int { chunks.reduce(0) { $0 + $1.frameCount } }
        var samples: [[Float]] {
            guard let channelCount = chunks.first?.channelCount else { return [] }
            return (0 ..< channelCount).map { channel in
                chunks.flatMap { $0.samples(ofChannel: channel) ?? [] }
            }
        }
    }

    private func collect(
        from url: URL,
        chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames,
        stoppingAfter stopAfter: Int? = nil
    ) async throws -> (stream: PCMStreamDescription?, collected: Collected) {
        var collected = Collected()
        let stream = try await decoder(for: url).decode(reference(), chunkFrames: chunkFrames) { chunk in
            collected.chunks.append(chunk)
            if let stopAfter, collected.chunks.count >= stopAfter { return .stop }
            return .continue
        }
        return (stream, collected)
    }

    // MARK: The format matrix (3.1)

    @Test("every natively writable format decodes to chunks spanning the file", arguments: AudioFixtureFormat.allCases)
    func everyFormatDecodes(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "matrix", format: format, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 20_000
                ),
                in: directory
            )
            let declared = try readBackMetadata(of: url)

            let (stream, collected) = try await collect(from: url)
            let description = try #require(stream)

            #expect(description.sampleRate == declared.sampleRate)
            #expect(description.channelCount == Int(declared.channels))
            #expect(description.frameCount == Int(declared.frames))
            #expect(collected.frameTotal == Int(declared.frames), "every declared frame was handed over")
            #expect(collected.chunks.allSatisfy { $0.channelCount == 2 })
            #expect(
                collected.samples[0].contains { abs($0) > 0.3 },
                "the signal survived decoding rather than arriving as silence"
            )
        }
    }

    @Test("mono and stereo files both decode", arguments: [AVAudioChannelCount(1), AVAudioChannelCount(2)])
    func monoAndStereo(channels: AVAudioChannelCount) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "channels", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: channels, frames: 5_000
                ),
                in: directory
            )

            let (stream, collected) = try await collect(from: url)
            #expect(try #require(stream).channelCount == Int(channels))
            #expect(collected.chunks.allSatisfy { $0.channelCount == Int(channels) })
        }
    }

    /// Channels are handed over separately, never mixed. A file whose channels carry different
    /// frequencies must arrive with those channels still different — a decoder that folded them would
    /// produce identical arrays.
    @Test("channels arrive apart, never combined")
    func channelsStayApart() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeFloatPCMFixture(
                AudioFixtureSpec(
                    name: "distinct", format: .wav,
                    signal: .perChannelSine(frequencies: [440, 3_000], amplitude: 0.5),
                    channels: 2, frames: 4_000
                ),
                in: directory
            )

            let (_, collected) = try await collect(from: url)
            let samples = collected.samples
            #expect(samples.count == 2)
            #expect(samples[0] != samples[1], "the two channels arrived as copies of one another")
        }
    }

    /// The samples are handed over as read, not limited: a file that genuinely exceeds full scale must
    /// arrive that way, because limiting is a concern of drawing and this port does none.
    @Test("samples beyond the nominal range survive the read unclamped")
    func valuesBeyondNominalRangeSurvive() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeFloatPCMFixture(
                AudioFixtureSpec(
                    name: "hot", format: .wav, signal: .sine(frequency: 440, amplitude: 1.5),
                    channels: 1, frames: 4_410
                ),
                in: directory
            )

            let (_, collected) = try await collect(from: url)
            #expect(
                collected.samples[0].contains { $0 > 1.0 },
                "a sample above full scale was clamped somewhere in the read"
            )
        }
    }

    // MARK: Chunking and the frameLength invariant (3.2)

    /// The regression this suite exists for. A reader that copied `frameCapacity` would pick up the
    /// region past `frameLength`, which the spike measured as content-derived, deterministic and
    /// **different for each capacity**. Identical samples across chunk sizes is therefore something
    /// only a `frameLength`-bounded reader can achieve, and it is observed purely through the chunks:
    /// no hash, no private byte, nothing tied to one SDK.
    @Test(
        "the same file yields the same samples at every chunk size",
        arguments: [1, 3, 127, 512, 4_096, 65_536]
    )
    func chunkSizeDoesNotChangeTheSamples(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            // Prime frame count: every chunk size above one leaves a short final chunk, so the region
            // past `frameLength` always exists and always differs in size.
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "chunking", format: .wav, signal: .sine(frequency: 440, amplitude: 0.6),
                    channels: 2, frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )

            let whole = try await collect(from: url, chunkFrames: 200_000)
            let chunked = try await collect(from: url, chunkFrames: chunkFrames)

            #expect(chunked.stream == whole.stream)
            #expect(chunked.collected.frameTotal == whole.collected.frameTotal)
            #expect(chunked.collected.samples == whole.collected.samples, "chunk size \(chunkFrames) changed the samples")
        }
    }

    /// AAC is the sharp end of the invariant: for it the region past `frameLength` is not stale caller
    /// data but content the read path produced, so a capacity-sized read yields *different* samples
    /// rather than merely unstable ones.
    @Test(
        "AAC with a short final chunk is unaffected by what the buffer's tail holds",
        arguments: [1_024, 1_025, 4_096]
    )
    func aacShortFinalChunkIsUnaffected(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "aac-tail", format: .aac, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )

            let whole = try await collect(from: url, chunkFrames: 200_000)
            let chunked = try await collect(from: url, chunkFrames: chunkFrames)

            #expect(chunked.collected.samples == whole.collected.samples)
        }
    }

    /// The structural promises a consumer folds against: chunks tile the file exactly once, in order,
    /// with no gap, no overlap and nothing empty.
    @Test("chunks tile the file exactly once, in order", arguments: [1, 3, 127, 512, 4_096])
    func chunksTileTheFile(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "tiling", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 9_001
                ),
                in: directory
            )

            let (stream, collected) = try await collect(from: url, chunkFrames: chunkFrames)
            let description = try #require(stream)

            #expect(collected.frameTotal == description.frameCount, "the frames add up to the declared length")
            #expect(collected.chunks.allSatisfy { $0.frameCount > 0 }, "an empty chunk was handed over")
            #expect(collected.chunks.allSatisfy { $0.channelCount == description.channelCount })
            #expect(collected.chunks.allSatisfy { $0.fits(description) })

            var expectedStart = 0
            for chunk in collected.chunks {
                #expect(chunk.startFrame == expectedStart, "a gap or an overlap between chunks")
                expectedStart += chunk.frameCount
            }
            #expect(expectedStart == description.frameCount)

            // No chunk exceeds the requested size, and only the last may be short.
            #expect(collected.chunks.allSatisfy { $0.frameCount <= chunkFrames })
            #expect(collected.chunks.dropLast().allSatisfy { $0.frameCount == chunkFrames })
        }
    }

    @Test("a chunk size larger than the file yields one chunk holding all of it")
    func aSingleChunkCanHoldTheWholeFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "single", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 1, frames: 3_000
                ),
                in: directory
            )

            let (stream, collected) = try await collect(from: url, chunkFrames: 100_000)
            let description = try #require(stream)
            #expect(collected.chunks.count == 1)
            #expect(collected.chunks[0].frameCount == description.frameCount)
            #expect(collected.chunks[0].startFrame == 0)
        }
    }

    // MARK: The port's outcomes (3.1, 3.4)

    @Test("a file with no audio is described, and the callback is never invoked")
    func zeroFramesDescribesWithoutChunks() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "silent", format: .wav, signal: .silence, channels: 1, frames: 0
                ),
                in: directory
            )

            let (stream, collected) = try await collect(from: url)
            let description = try #require(stream, "a file with no audio is a description, not an absence")
            #expect(description.frameCount == 0)
            #expect(collected.chunks.isEmpty, "a chunk saying nothing was handed over")
        }
    }

    @Test("a missing location is refused before anything is opened")
    func unresolvableReferenceIsAnError() async {
        let decoder = AVFoundationAudioDecoder()
        let error = await #expect(throws: AudioDecodingError.self) {
            try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        }
        #expect(error?.code == .fileAccessDenied)
    }

    @Test("a chunk size of zero or fewer frames is refused", arguments: [0, -1, -4_096])
    func invalidChunkSizeIsRefused(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "config", format: .wav, signal: .silence, channels: 1, frames: 100),
                in: directory
            )

            let error = await #expect(throws: AudioDecodingError.self) {
                try await decoder(for: url).decode(reference(), chunkFrames: chunkFrames) { _ in .continue }
            }
            #expect(error?.code == .invalidConfiguration)
        }
    }

    @Test("an empty file cannot be opened, and says so")
    func emptyFileIsAnOpenFailure() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeEmptyFixture(named: "empty", format: .wav, in: directory)

            let error = await #expect(throws: AudioDecodingError.self) {
                try await decoder(for: url).decode(reference(), chunkFrames: 4_096) { _ in .continue }
            }
            #expect(error?.code == .fileOpenFailed)
        }
    }

    @Test("a file whose header is corrupt cannot be opened, and says so")
    func corruptFileIsAnOpenFailure() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "corrupt", format: .wav, signal: .silence, channels: 1, frames: 1_000),
                in: directory
            )
            try corruptFixture(at: url, replacingBytesIn: 0 ..< 32, with: 0xFF)

            let error = await #expect(throws: AudioDecodingError.self) {
                try await decoder(for: url).decode(reference(), chunkFrames: 4_096) { _ in .continue }
            }
            #expect(error?.code == .fileOpenFailed)
        }
    }

    /// A truncated file is not a corrupt one: the header still parses, so it opens and declares the
    /// length its remaining data supports. What matters is that whatever it declares, it delivers —
    /// the adapter must not report a short read as a complete one.
    @Test("a truncated file that still opens delivers exactly the length it declares")
    func truncatedFileIsConsistentWithItsOwnHeader() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "truncated", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 1, frames: 10_000
                ),
                in: directory
            )
            try truncateFixture(at: url, toFirst: 4_096)

            let (stream, collected) = try await collect(from: url, chunkFrames: 256)
            let description = try #require(stream)
            #expect(collected.frameTotal == description.frameCount)
        }
    }

    @Test("a file that is not audio cannot be opened")
    func nonAudioFileIsAnOpenFailure() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("notes.wav")
            try Data("this is not audio, it is text".utf8).write(to: url)

            let error = await #expect(throws: AudioDecodingError.self) {
                try await decoder(for: url).decode(reference(), chunkFrames: 4_096) { _ in .continue }
            }
            #expect(error?.code == .fileOpenFailed)
        }
    }

    // MARK: Stopping early (3.1)

    /// `.stop` ends the read normally and early. It is not a failure, the description still comes back,
    /// and — the part that matters for a long file — nothing after the stopping chunk is read.
    @Test("stopping early ends the read normally, without reading the rest")
    func stoppingEarlyIsNotAFailure() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "stopping", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 100_000
                ),
                in: directory
            )

            let (stream, collected) = try await collect(from: url, chunkFrames: 1_024, stoppingAfter: 3)
            let description = try #require(stream, "stopping early is not an absence")

            #expect(collected.chunks.count == 3, "the read continued past the stop")
            #expect(description.frameCount == 100_000, "the description still describes the whole file")
            #expect(collected.frameTotal < description.frameCount, "and only part of it was delivered")
        }
    }

    @Test("stopping on the very first chunk is honoured")
    func stoppingImmediatelyIsHonoured() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "stop-first", format: .wav, signal: .silence, channels: 1, frames: 50_000
                ),
                in: directory
            )

            let (stream, collected) = try await collect(from: url, chunkFrames: 512, stoppingAfter: 1)
            #expect(collected.chunks.count == 1)
            #expect(try #require(stream).frameCount == 50_000)
        }
    }

    // MARK: Cancellation (3.4)

    /// Cancelled before the first boundary is reached. It proves the adapter refuses to begin, and that
    /// it says `cancelled` rather than blaming the file.
    @Test("a cancelled decode throws cancellation, never an absence or a partial answer")
    func cancellationBeforeStarting() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "cancelled", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 200_000
                ),
                in: directory
            )

            let decoder = decoder(for: url)
            let file = reference()
            let task = Task {
                try await decoder.decode(file, chunkFrames: 128) { _ in .continue }
            }
            task.cancel()

            let error = await #expect(throws: AudioDecodingError.self) { try await task.value }
            #expect(error?.code == .cancelled)
            #expect(error?.code != .readFailed, "cancellation must not be reported as a failure of the file")
        }
    }

    // MARK: The source is never touched (3.6)

    @Test("the source file is byte-identical after decoding, and no file is created beside it")
    func theSourceIsNeverModified() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "untouched", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 30_000
                ),
                in: directory
            )
            let before = try sha256(of: url)
            let attributesBefore = try FileManager.default.attributesOfItem(atPath: url.path)
            let contentsBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path)

            _ = try await collect(from: url, chunkFrames: 512)

            #expect(try sha256(of: url) == before, "the decoder modified the file it read")
            let attributesAfter = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(
                attributesBefore[.modificationDate] as? Date == attributesAfter[.modificationDate] as? Date,
                "the file's modification date changed"
            )
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
                    == contentsBefore.sorted(),
                "the decoder created or removed a file beside the source"
            )
        }
    }

    // MARK: Memory (3.1)

    /// What the suite can honestly observe: the chunks are bounded by the requested size whatever the
    /// file's length, so peak memory is a function of the chunk and not of the duration. It does not
    /// measure allocation, and does not pretend to.
    @Test("no chunk grows with the file's length")
    func chunksAreBoundedByTheRequestedSize() async throws {
        try await withTemporaryDirectory { directory in
            let short = try writeAudioFixture(
                AudioFixtureSpec(name: "short", format: .wav, signal: .silence, channels: 2, frames: 5_000),
                in: directory
            )
            let long = try writeAudioFixture(
                AudioFixtureSpec(name: "long", format: .wav, signal: .silence, channels: 2, frames: 441_000),
                in: directory
            )

            let shortRun = try await collect(from: short, chunkFrames: 1_024)
            let longRun = try await collect(from: long, chunkFrames: 1_024)

            #expect(shortRun.collected.chunks.allSatisfy { $0.frameCount <= 1_024 })
            #expect(longRun.collected.chunks.allSatisfy { $0.frameCount <= 1_024 })
            #expect(longRun.collected.frameTotal == 441_000, "the long file was still read in full")
        }
    }

    // MARK: Non-finite samples — deliberately not asserted here
    //
    // There is no test of the adapter's behaviour on a `NaN` or an infinity, because no fixture this
    // package can write produces one: `AVAudioFile` encodes what it is given, and the float PCM path
    // that would round-trip such a value writes it only if the writer is handed it — at which point the
    // test would be asserting the writer's behaviour, not the decoder's. The boundary itself is proved
    // exhaustively in `PCMDecodingContractTests`, over `PCMChunk`, where it lives; the adapter's part is
    // simply that it builds chunks through that initialiser and forwards its codes unchanged, which is
    // visible in the reading loop. Inventing adapter coverage here would assert a fixture, not a fault.
}

// MARK: - Decisions the adapter makes without a file

@Suite("Media — decoder format and length rules")
struct AVFoundationAudioDecoderRuleTests {
    private func format(
        sampleRate: Double = 44_100,
        channels: AVAudioChannelCount = 2,
        interleaved: Bool = false
    ) -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: channels, interleaved: interleaved
        )!
    }

    @Test("the native deinterleaved float layout is accepted")
    func nativePlanarFloatIsAccepted() throws {
        try AVFoundationAudioDecoder.verifyReadable(format())
    }

    /// The one mistake the domain boundary cannot catch: an interleaved buffer copied as a contiguous
    /// run yields a chunk with equal-length channels, finite samples and a fitting frame range — every
    /// invariant satisfied, every sample from the wrong place.
    @Test("an interleaved layout is refused rather than copied as if it were contiguous")
    func interleavedIsRefused() {
        let error = #expect(throws: AudioDecodingError.self) {
            try AVFoundationAudioDecoder.verifyReadable(format(interleaved: true))
        }
        #expect(error?.code == .unsupportedProcessingFormat)
    }

    @Test("a non-float layout is refused")
    func nonFloatIsRefused() throws {
        let int16 = try #require(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: false
        ))
        let error = #expect(throws: AudioDecodingError.self) {
            try AVFoundationAudioDecoder.verifyReadable(int16)
        }
        #expect(error?.code == .unsupportedProcessingFormat)
    }

    @Test("zero frames is a usable count, describing a file with no audio")
    func zeroFramesIsUsable() {
        #expect(AVFoundationAudioDecoder.usableFrameCount(0) == 0)
    }

    @Test("a negative length is not usable, and becomes an absence", arguments: [AVAudioFramePosition(-1), -44_100])
    func negativeLengthIsAnAbsence(length: AVAudioFramePosition) {
        #expect(AVFoundationAudioDecoder.usableFrameCount(length) == nil)
    }

    @Test("an ordinary length is usable")
    func ordinaryLengthIsUsable() {
        #expect(AVFoundationAudioDecoder.usableFrameCount(441_000) == 441_000)
    }

    /// The default is the waveform adapter's, deliberately: both read the same files through the same
    /// API, and two independently drifting defaults would make the two readers quietly incomparable.
    @Test("the default chunk size is the one the waveform adapter measured")
    func defaultChunkSizeIsShared() {
        #expect(AVFoundationAudioDecoder.defaultChunkFrames == Int(AVFoundationWaveformGenerator.defaultChunkFrames))
        #expect(AVFoundationAudioDecoder.defaultChunkFrames == 4_096)
    }
}
