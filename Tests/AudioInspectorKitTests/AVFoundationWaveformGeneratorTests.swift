import AVFoundation
import AudioInspectorDomain
@testable import AudioInspectorMedia
import CryptoKit
import Foundation
import Testing

// The waveform acceptance matrix, run against the **production** adapter over real files it decodes
// itself. Nothing here re-implements the reduction: every assertion is about the envelope the adapter
// returns, which is the only surface a regression could hide behind.

@Suite("Media — native waveform generation")
struct AVFoundationWaveformGeneratorTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture",
            fileExtension: nil,
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func generator(
        for url: URL,
        chunkFrames: AVAudioFrameCount = AVFoundationWaveformGenerator.defaultChunkFrames,
        maximumBucketCount: Int = WaveformBucketMapping.defaultMaximumBucketCount
    ) -> AVFoundationWaveformGenerator {
        AVFoundationWaveformGenerator(
            chunkFrames: chunkFrames,
            maximumBucketCount: maximumBucketCount,
            resolveURL: { _ in url }
        )
    }

    private func sha256(of url: URL) throws -> SHA256Digest {
        try SHA256.hash(data: Data(contentsOf: url))
    }

    // MARK: The format matrix (group 0, tasks 0.1 – 0.5)

    @Test("every natively writable format decodes to an envelope spanning the file", arguments: AudioFixtureFormat.allCases)
    func everyFormatProducesAnEnvelope(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(
                name: "matrix",
                format: format,
                signal: .sine(frequency: 440, amplitude: 0.5),
                channels: 2,
                frames: 20_000
            )
            let url = try writeAudioFixture(spec, in: directory)
            let declared = try readBackMetadata(of: url).frames

            let envelope = try #require(await generator(for: url).makeWaveform(for: reference()))

            #expect(envelope.frameCount == Int(declared), "the envelope covers what the file declares")
            #expect(envelope.channelCount == 2)
            #expect(envelope.buckets.count == min(2_048, Int(declared)))
            #expect(envelope.buckets.contains { $0.maximum > 0.3 }, "the signal survived decoding")
        }
    }

    @Test("mono and stereo files both reduce", arguments: [AVAudioChannelCount(1), AVAudioChannelCount(2)])
    func monoAndStereo(channels: AVAudioChannelCount) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "channels", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: channels, frames: 8_820
                ),
                in: directory
            )

            let envelope = try #require(await generator(for: url).makeWaveform(for: reference()))
            #expect(envelope.channelCount == Int(channels))
        }
    }

    @Test("channels in opposing polarity do not cancel")
    func oppositePolarityDoesNotCancel() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "polarity", format: .wav,
                    signal: .oppositePolarity(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 8_820
                ),
                in: directory
            )

            let envelope = try #require(await generator(for: url).makeWaveform(for: reference()))
            #expect(envelope.buckets.contains { $0.maximum > 0.4 })
            #expect(envelope.buckets.contains { $0.minimum < -0.4 })
        }
    }

    // MARK: Chunking, the short final chunk and the frameLength invariant (0.9, 0.11)

    /// The regression this suite exists for. A reader that walked `frameCapacity` would pick up the
    /// region past `frameLength`, which the spike measured as content-derived and deterministic — and
    /// **different for each capacity**. Identical envelopes across chunk sizes is therefore something
    /// only a `frameLength`-bounded reader can achieve, and it is observed purely through the public
    /// result: no hash, no private byte, nothing tied to one SDK.
    @Test(
        "the same file yields the same envelope at every chunk size",
        arguments: [AVAudioFrameCount(1), 2, 3, 7, 31, 64, 127, 1_024, 4_096]
    )
    func chunkSizeDoesNotChangeTheEnvelope(chunkFrames: AVAudioFrameCount) async throws {
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

            let whole = try #require(
                await generator(for: url, chunkFrames: 65_536).makeWaveform(for: reference())
            )
            let chunked = try #require(
                await generator(for: url, chunkFrames: chunkFrames).makeWaveform(for: reference())
            )

            #expect(chunked == whole, "chunk size \(chunkFrames) changed the envelope")
        }
    }

    /// AAC is the sharp end of the invariant: for it the region past `frameLength` is not stale caller
    /// data but content the read path produced, so a capacity-sized read yields a *different* envelope
    /// rather than merely an unstable one.
    @Test(
        "AAC with a short final chunk is unaffected by what the buffer's tail holds",
        arguments: [AVAudioFrameCount(1_024), 1_025, 4_096]
    )
    func aacShortFinalChunkIsUnaffected(chunkFrames: AVAudioFrameCount) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "aac-tail", format: .aac, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )

            let whole = try #require(
                await generator(for: url, chunkFrames: 65_536).makeWaveform(for: reference())
            )
            let chunked = try #require(
                await generator(for: url, chunkFrames: chunkFrames).makeWaveform(for: reference())
            )

            #expect(chunked == whole)
        }
    }

    @Test("the bucket cap is never exceeded, whatever the file's length")
    func bucketCapIsRespected() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "long", format: .wav, signal: .sine(frequency: 220, amplitude: 0.4),
                    channels: 2, frames: 441_000 // ten seconds
                ),
                in: directory
            )

            let envelope = try #require(await generator(for: url).makeWaveform(for: reference()))
            #expect(envelope.buckets.count == 2_048)
            #expect(envelope.frameCount == 441_000)
        }
    }

    @Test("a small bucket cap is honoured too")
    func smallBucketCapIsHonoured() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "small-cap", format: .wav, signal: .silence, frames: 5_000),
                in: directory
            )

            let envelope = try #require(
                await generator(for: url, maximumBucketCount: 7).makeWaveform(for: reference())
            )
            #expect(envelope.buckets.count == 7)
        }
    }

    // MARK: Adverse files (0.7)

    @Test("an empty file cannot be opened, and says so")
    func emptyFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeEmptyFixture(named: "empty", format: .wav, in: directory)

            let error = await #expect(throws: WaveformError.self) {
                _ = try await generator(for: url).makeWaveform(for: reference())
            }
            #expect(error?.code == .fileOpenFailed)
        }
    }

    /// Observed rather than assumed, and pinned because it is surprising: a WAV truncated past its
    /// header still **opens**, and reports a length of zero. The adapter then returns the envelope of a
    /// file with no frames — which is what the file declares. Reporting anything else would mean
    /// guessing that the declaration is a lie, and this layer does not guess.
    ///
    /// The spike saw the same shape on the property side: a truncated copy returned a duration of 0.0
    /// with no error.
    @Test("a truncated file that still opens yields the empty envelope its length declares")
    func truncatedFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "truncated", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 44_100),
                in: directory
            )
            try truncateFixture(at: url, toFirst: 2_000)

            let envelope = try #require(await generator(for: url).makeWaveform(for: reference()))
            #expect(envelope.frameCount == 0)
            #expect(envelope.buckets.isEmpty)
        }
    }

    @Test("a file whose header is corrupt cannot be opened, and says so")
    func corruptFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "corrupt", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 44_100),
                in: directory
            )
            try corruptFixture(at: url, replacingBytesIn: 0 ..< 64, with: 0xFF)

            let error = await #expect(throws: WaveformError.self) {
                _ = try await generator(for: url).makeWaveform(for: reference())
            }
            #expect(error?.code == .fileOpenFailed)
        }
    }

    @Test("a missing location is refused before anything is opened")
    func missingLocation() async throws {
        let generator = AVFoundationWaveformGenerator() // default resolver supplies nothing
        let error = await #expect(throws: WaveformError.self) {
            _ = try await generator.makeWaveform(for: reference())
        }
        #expect(error?.code == .fileAccessDenied)
    }

    @Test("a file that is not audio cannot be opened")
    func notAnAudioFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("text.wav")
            try Data("this is not audio".utf8).write(to: url)

            let error = await #expect(throws: WaveformError.self) {
                _ = try await generator(for: url).makeWaveform(for: reference())
            }
            #expect(error?.code == .fileOpenFailed)
        }
    }

    // MARK: Cancellation (0.12)

    @Test("a cancelled generation throws cancellation, never an absence or a partial envelope")
    func cancellationIsReported() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "cancellable", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 441_000
                ),
                in: directory
            )
            // A tiny chunk guarantees many boundaries, so cancellation is observed at one of them.
            let subject = generator(for: url, chunkFrames: 1)

            let task = Task { try await subject.makeWaveform(for: reference()) }
            task.cancel()

            // Cancelling before the first chunk boundary is deterministic here: at one frame per read
            // the loop cannot reach 441 000 frames before the flag is seen.
            let error = await #expect(throws: WaveformError.self) { try await task.value }
            #expect(error?.code == .cancelled)
            #expect(error?.code != .readFailed, "cancellation must not be swallowed as a generic failure")
        }
    }

    // MARK: What the suite can genuinely observe about memory (0.13)

    /// Retention is a structural property — the buffer is allocated once at the chunk size and the
    /// accumulator holds two floats per bucket — so the suite cannot measure it. What it *can* observe
    /// is that neither the reading nor the result grows with the file: a long file read one frame at a
    /// time still succeeds, and its envelope is bounded by the cap rather than by its length.
    @Test("neither the read nor the envelope grows with the file's length")
    func nothingGrowsWithTheFile() async throws {
        try await withTemporaryDirectory { directory in
            let short = try writeAudioFixture(
                AudioFixtureSpec(name: "short", format: .wav, signal: .sine(frequency: 440, amplitude: 0.4), frames: 4_410),
                in: directory
            )
            let long = try writeAudioFixture(
                AudioFixtureSpec(name: "ten-seconds", format: .wav, signal: .sine(frequency: 440, amplitude: 0.4), frames: 441_000),
                in: directory
            )

            let shortEnvelope = try #require(await generator(for: short, chunkFrames: 64).makeWaveform(for: reference()))
            let longEnvelope = try #require(await generator(for: long, chunkFrames: 64).makeWaveform(for: reference()))

            // A hundredfold more audio, read through the same 64-frame buffer, and the result is the
            // same size — the envelope is a function of the cap, not of the file.
            #expect(longEnvelope.frameCount == 100 * shortEnvelope.frameCount)
            #expect(shortEnvelope.buckets.count == 2_048)
            #expect(longEnvelope.buckets.count == 2_048)
        }
    }

    // MARK: The source is never touched (0.1 – 0.8)

    @Test("the source file is byte-identical after generating a waveform")
    func sourceIsUnchanged() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "untouched", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 44_100),
                in: directory
            )
            let before = try sha256(of: url)
            let sizeBefore = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int

            _ = try await generator(for: url).makeWaveform(for: reference())

            #expect(try sha256(of: url) == before)
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int == sizeBefore)
        }
    }
}

// MARK: - Decisions the adapter makes without a file

@Suite("Media — waveform generator format and length rules")
struct AVFoundationWaveformGeneratorRuleTests {
    @Test("the native deinterleaved float layout is accepted")
    func acceptsStandardFormat() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        #expect(format.isStandard)
        #expect(!format.isInterleaved)
        try AVFoundationWaveformGenerator.verifyReducible(format)
    }

    @Test("an interleaved layout is refused rather than read as if it were contiguous")
    func refusesInterleavedFormat() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: true)
        )
        #expect(format.isInterleaved)

        let error = #expect(throws: WaveformError.self) {
            try AVFoundationWaveformGenerator.verifyReducible(format)
        }
        #expect(error?.code == .unsupportedProcessingFormat)
    }

    @Test("a non-float layout is refused")
    func refusesNonFloatFormat() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: false)
        )
        let error = #expect(throws: WaveformError.self) {
            try AVFoundationWaveformGenerator.verifyReducible(format)
        }
        #expect(error?.code == .unsupportedProcessingFormat)
    }

    @Test("zero frames is a usable count, describing a file with no audio")
    func zeroFramesIsUsable() {
        #expect(AVFoundationWaveformGenerator.usableFrameCount(0, maximumBucketCount: 2_048) == 0)
    }

    @Test("a negative or unmappable count is not usable, and becomes an absence")
    func unusableCounts() {
        #expect(AVFoundationWaveformGenerator.usableFrameCount(-1, maximumBucketCount: 2_048) == nil)
        #expect(AVFoundationWaveformGenerator.usableFrameCount(.max, maximumBucketCount: 2_048) == nil)
    }

    @Test("an ordinary count is usable")
    func ordinaryCountIsUsable() {
        #expect(AVFoundationWaveformGenerator.usableFrameCount(44_100, maximumBucketCount: 2_048) == 44_100)
    }
}
