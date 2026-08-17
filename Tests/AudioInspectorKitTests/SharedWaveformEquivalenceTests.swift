import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

// **The envelope the shared read produces is the envelope the file's own read produced.**
//
// `SharedWaveformConsumerTests` proved the consumer behaves — that it fails alone, that it is absent
// rather than failed when the file offers nothing to size against, that cancellation reaches it. This
// suite answers a narrower and harder question: is the *result* the same one, everywhere the contract
// says it must be?
//
// The oracle is the legacy `AVFoundationWaveformGenerator`, on the same file, through the real
// adapters. That is the only reason it still exists (`share-waveform-pcm-read`, task 3.2), and it is
// why retiring it is deferred until this evidence is recorded.
//
// **The expectation is the whole `WaveformEnvelope`, compared with `==`.** Not bucket counts, not
// sampled values, and no tolerance: sharing a read changes how samples arrive, never what is computed
// from them. Individual fields are asserted only where a diagnosis needs them.

@Suite("App — the shared waveform equals the file's own read")
struct SharedWaveformEquivalenceTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    /// Both envelopes for one file, produced the two ways, at the same resolution and chunk size.
    private func bothEnvelopes(
        at url: URL, chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames,
        maximumBucketCount: Int = WaveformBucketMapping.defaultMaximumBucketCount
    ) async throws -> (legacy: WaveformEnvelope, shared: WaveformEnvelope) {
        let legacy = try #require(
            try await AVFoundationWaveformGenerator(
                chunkFrames: AVAudioFrameCount(chunkFrames), maximumBucketCount: maximumBucketCount,
                resolveURL: { _ in url }
            ).makeWaveform(for: reference()),
            "the legacy oracle produced nothing to compare against"
        )
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: AVFoundationAudioDecoder(resolveURL: { _ in url }),
            chunkFrames: chunkFrames, maximumBucketCount: maximumBucketCount
        ).run(for: reference())
        guard case let .available(shared) = outcome.waveform else {
            Issue.record("the shared read produced \(outcome.waveform)")
            throw EquivalenceUnavailable()
        }
        return (legacy, shared)
    }

    private struct EquivalenceUnavailable: Error {}

    private func write(
        _ format: AudioFixtureFormat, _ signal: AudioFixtureSignal,
        channels: AVAudioChannelCount = 2, frames: AVAudioFrameCount = 44_101,
        named name: String = "equivalence", in directory: URL
    ) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(name: name, format: format, signal: signal, channels: channels, frames: frames),
            in: directory
        )
    }

    // MARK: - The matrix

    /// Container × channel count × signal, at the resolution and chunk size production uses.
    ///
    /// `44 101` frames is the project's prime fixture length: it leaves a **short final chunk at every
    /// chunk size above one**, and it is not a multiple of any chunk size a caller would pick, so the
    /// two cases task 4.1 names last are properties of every row here rather than of one special case.
    @Test(
        "the whole envelope is identical, container by container",
        arguments: [
            (AudioFixtureFormat.wav, 1 as AVAudioChannelCount, AudioFixtureSignal.sine(frequency: 440, amplitude: 0.5)),
            (.wav, 2, .sine(frequency: 440, amplitude: 0.5)),
            (.wav, 4, .perChannelSine(frequencies: [220, 440, 880, 1_760], amplitude: 0.4)),
            (.wav, 2, .silence),
            (.wav, 2, .impulse(amplitude: 0.9, frameIndex: 30_000)),
            (.wav, 2, .oppositePolarity(frequency: 440, amplitude: 0.5)),
            (.flac, 1, .sine(frequency: 440, amplitude: 0.5)),
            (.flac, 2, .sine(frequency: 440, amplitude: 0.5)),
            (.flac, 2, .silence),
            (.flac, 2, .oppositePolarity(frequency: 440, amplitude: 0.5)),
            (.aiff, 2, .sine(frequency: 440, amplitude: 0.5)),
            (.alac, 2, .sine(frequency: 440, amplitude: 0.5)),
            (.aac, 2, .perChannelSine(frequencies: [440, 997], amplitude: 0.5)),
            (.wavFloat, 2, .sine(frequency: 440, amplitude: 0.5)),
        ]
    )
    func theWholeEnvelopeIsIdentical(
        format: AudioFixtureFormat, channels: AVAudioChannelCount, signal: AudioFixtureSignal
    ) async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(format, signal, channels: channels, in: directory)
            let (legacy, shared) = try await bothEnvelopes(at: url)
            #expect(shared == legacy, "\(format)/\(channels)ch: the shared envelope is not the file's own")
        }
    }

    // MARK: - Silence, and why it is not the same thing as an empty file

    /// A file of real frames that are all zero: **buckets exist and hold zero**, which is a measurement,
    /// not an absence. Kept apart from the zero-frame case below on purpose — the two are different
    /// answers and the reduction must not collapse them.
    @Test("silence reduces to real buckets of zero, identically through both paths")
    func silenceIsMeasuredNotAbsent() async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.wav, .silence, in: directory)
            let (legacy, shared) = try await bothEnvelopes(at: url)

            #expect(shared == legacy)
            #expect(!shared.buckets.isEmpty, "silence produced no buckets, which is an absence, not silence")
            #expect(shared.frameCount == 44_101)
            #expect(shared.buckets.allSatisfy { $0.minimum == 0 && $0.maximum == 0 })
        }
    }

    /// A file with **no frames at all**: a complete answer with no buckets, and the same one either way.
    /// The distinction this pins is the one the port's documentation exists for — an empty envelope is
    /// not an absent one.
    @Test("a file with no frames yields the same empty envelope through both paths")
    func zeroFramesAgree() async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.wav, .silence, frames: 0, named: "empty", in: directory)
            let (legacy, shared) = try await bothEnvelopes(at: url)

            #expect(shared == legacy)
            #expect(shared.buckets.isEmpty)
            #expect(shared.frameCount == 0)
        }
    }

    // MARK: - Amplitude beyond full scale, through a real container

    /// **A sample beyond `1.0` is a fact about the file, and both paths report it.**
    ///
    /// Every other writable container here quantises to 16-bit integer and clamps, which is why this is
    /// the one case that needs 32-bit float WAV: without it the rule could only be checked against the
    /// reduction in isolation, and task 4.1 asks for it against the pre-change behaviour.
    @Test("a peak above full scale survives both paths, unclamped and identical")
    func peakAboveFullScaleAgrees() async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(
                .wavFloat, .sine(frequency: 440, amplitude: 2.5), named: "beyond-full-scale", in: directory
            )
            let (legacy, shared) = try await bothEnvelopes(at: url)

            #expect(shared == legacy)
            #expect(shared.buckets.contains { $0.maximum > 1 }, "the shared read clamped a sample beyond full scale")
            #expect(legacy.buckets.contains { $0.maximum > 1 }, "the fixture did not carry a sample beyond full scale")
            #expect(shared.buckets.contains { $0.minimum < -1 })
        }
    }

    // MARK: - A very short file

    /// Fewer frames than the bucket cap, so the mapping's `min(totalFrameCount, maximumBucketCount)`
    /// branch is the one under test and every bucket holds exactly one frame.
    @Test("a file shorter than the bucket cap agrees, bucket for bucket", arguments: [1, 2, 7, 512])
    func aVeryShortFileAgrees(frames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(
                .wav, .sine(frequency: 440, amplitude: 0.5),
                frames: AVAudioFrameCount(frames), named: "short-\(frames)", in: directory
            )
            let (legacy, shared) = try await bothEnvelopes(at: url)

            #expect(shared == legacy)
            #expect(shared.buckets.count == frames, "a file of \(frames) frames produced \(shared.buckets.count) buckets")
        }
    }

    // MARK: - Chunk size

    /// The reduction's own order- and size-independence, observed through both paths at once: the two
    /// must agree with each other **and** the shared one must not depend on the chunk size.
    @Test(
        "the envelope is identical whatever the chunk size, and matches the file's own read",
        arguments: [1, 3, 127, 512, 2_048, 4_096, 8_192, 65_536, 200_000]
    )
    func chunkSizeChangesNothing(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.flac, .sine(frequency: 440, amplitude: 0.5), in: directory)
            let (legacy, shared) = try await bothEnvelopes(at: url, chunkFrames: chunkFrames)
            #expect(shared == legacy, "chunk size \(chunkFrames) changed the envelope")
        }
    }

    // MARK: - Resolution

    /// **The bucket mapping is a function of the file and the resolution, never of the transport.**
    ///
    /// One bucket, an odd small number, production's own cap, and a cap larger than the file has frames
    /// — the last being the branch where a bucket holds a single frame and nothing may be left uncovered.
    @Test(
        "the envelope is identical at every resolution, including one larger than the file",
        arguments: [1, 7, 333, 2_048, 100_000]
    )
    func resolutionChangesNothing(maximumBucketCount: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.wav, .sine(frequency: 440, amplitude: 0.5), in: directory)
            let (legacy, shared) = try await bothEnvelopes(at: url, maximumBucketCount: maximumBucketCount)

            #expect(shared == legacy, "resolution \(maximumBucketCount) changed the envelope")
            #expect(shared.buckets.count == min(44_101, maximumBucketCount))
            #expect(shared.frameCount == 44_101, "the frame count is the file's, not the resolution's")
        }
    }

    /// The last bucket is closed over the last frame, at a resolution that does not divide the file.
    /// A reduction that dropped the tail would still produce the right *number* of buckets, so this
    /// asserts the content rather than the shape — against the oracle, and against a signal whose end
    /// is recognisable.
    @Test("the final frames reach the final bucket")
    func theTailIsNotLost() async throws {
        try await withTemporaryDirectory { directory in
            // Silence everywhere except the very last frame, so only a reduction that reaches the end
            // can produce a non-zero final bucket.
            let url = try write(
                .wavFloat, .impulse(amplitude: 0.75, frameIndex: 44_100),
                frames: 44_101, named: "tail", in: directory
            )
            let (legacy, shared) = try await bothEnvelopes(at: url, maximumBucketCount: 333)

            #expect(shared == legacy)
            let last = try #require(shared.buckets.last)
            #expect(last.maximum > 0.7, "the last frame did not reach the last bucket: \(last)")
            #expect(shared.buckets.dropLast().allSatisfy { $0.minimum == 0 && $0.maximum == 0 })
        }
    }
}
