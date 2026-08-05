import AVFoundation
import Foundation
import Testing

// Tests for the acceptance fixtures themselves.
//
// They assert that a fixture is what its specification claims — the format opens, the metadata
// matches, and the samples are the signal that was asked for. They assert **nothing** about a
// waveform, an envelope or a reduction: none of that exists yet, and inventing it here would be a
// shadow of the code the acceptance matrix is meant to test.

@Suite("Test support — audio fixtures")
struct AudioFixtureSupportTests {
    /// Sample comparisons run through a 16-bit or a lossy encoder, so they are compared with a
    /// tolerance rather than for equality. 16-bit quantisation alone is one part in 32 768.
    private let losslessTolerance: Float = 1e-4
    private let lossyTolerance: Float = 0.05

    // MARK: Every format this platform can actually write

    @Test("every declared format is generated and reads back with the specified metadata", arguments: AudioFixtureFormat.allCases)
    func formatRoundTripsItsMetadata(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(
                name: "metadata",
                format: format,
                signal: .sine(frequency: 440, amplitude: 0.25),
                sampleRate: 44_100,
                channels: 2,
                frames: 11_025
            )
            let url = try writeAudioFixture(spec, in: directory)

            let metadata = try readBackMetadata(of: url)
            #expect(metadata.sampleRate == spec.sampleRate)
            #expect(metadata.channels == spec.channels)
            #expect(metadata.frames == AVAudioFramePosition(spec.frames))
        }
    }

    @Test("a fixture keeps its channel count for mono and for stereo", arguments: [AVAudioChannelCount(1), AVAudioChannelCount(2)])
    func channelCountIsPreserved(channels: AVAudioChannelCount) async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(
                name: "channels-\(channels)",
                format: .wav,
                signal: .sine(frequency: 440, amplitude: 0.25),
                channels: channels,
                frames: 4_410
            )
            let url = try writeAudioFixture(spec, in: directory)

            #expect(try readBackMetadata(of: url).channels == channels)
        }
    }

    @Test("a long fixture is written in chunks and keeps its full frame count")
    func longFixtureKeepsItsFrameCount() async throws {
        try await withTemporaryDirectory { directory in
            // Deliberately larger than the writer's chunk, so a writer that assumed a single buffer
            // would fail here rather than in the acceptance matrix.
            let spec = AudioFixtureSpec(
                name: "long",
                format: .wav,
                signal: .sine(frequency: 220, amplitude: 0.5),
                frames: 220_500 // five seconds
            )
            let url = try writeAudioFixture(spec, in: directory)

            #expect(try readBackMetadata(of: url).frames == 220_500)
        }
    }

    // MARK: The signals carry what they promise

    @Test("silence is silent")
    func silenceIsSilent() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "silence", format: .wav, signal: .silence, frames: 4_410),
                in: directory
            )

            let samples = try readBackSamples(of: url, channel: 0, limit: 512)
            #expect(samples.count == 512)
            #expect(samples.allSatisfy { $0 == 0 })
        }
    }

    @Test("opposite polarity gives each channel the other's negative")
    func oppositePolarityChannelsAreMirrored() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "polarity",
                    format: .wav,
                    signal: .oppositePolarity(frequency: 440, amplitude: 0.5),
                    channels: 2,
                    frames: 4_410
                ),
                in: directory
            )

            let left = try readBackSamples(of: url, channel: 0, limit: 256)
            let right = try readBackSamples(of: url, channel: 1, limit: 256)
            #expect(left.count == right.count)
            for index in left.indices {
                #expect(abs(left[index] + right[index]) < losslessTolerance)
            }
            // And it is not the trivially mirrored case of two silent channels.
            #expect(left.contains { abs($0) > 0.1 })
        }
    }

    @Test("an impulse is non-zero only at its own frame")
    func impulseIsIsolated() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "impulse",
                    format: .wav,
                    signal: .impulse(amplitude: 0.75, frameIndex: 100),
                    channels: 1,
                    frames: 4_410
                ),
                in: directory
            )

            let samples = try readBackSamples(of: url, channel: 0, limit: 256)
            #expect(abs(samples[100] - 0.75) < losslessTolerance)
            for index in samples.indices where index != 100 {
                #expect(samples[index] == 0)
            }
        }
    }

    @Test("a near-full-scale sine reaches close to the nominal maximum without exceeding it")
    func nearFullScaleStaysWithinRange() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "near-full-scale",
                    format: .wav,
                    signal: .sine(frequency: 441, amplitude: 0.99),
                    channels: 1,
                    frames: 4_410
                ),
                in: directory
            )

            let samples = try readBackSamples(of: url, channel: 0, limit: 2_048)
            let peak = samples.map { abs($0) }.max() ?? 0
            #expect(peak > 0.95)
            #expect(peak <= 1.0)
        }
    }

    @Test("a lossy fixture still carries the signal it was given")
    func lossyFixtureCarriesItsSignal() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "lossy",
                    format: .aac,
                    signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 1,
                    frames: 22_050
                ),
                in: directory
            )

            // Skip the encoder's opening frames and compare the steady state, at a tolerance that
            // says "this is the signal" without pretending a lossy codec is bit-exact.
            let samples = try readBackSamples(of: url, channel: 0, limit: 8_192)
            let steadyState = samples.dropFirst(4_096)
            let peak = steadyState.map { abs($0) }.max() ?? 0
            #expect(abs(peak - 0.5) < lossyTolerance)
        }
    }

    // MARK: Determinism

    @Test("the same specification produces the same samples every time")
    func specificationIsDeterministic() async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(
                name: "determinism",
                format: .wav,
                signal: .sine(frequency: 440, amplitude: 0.25),
                channels: 2,
                frames: 8_820
            )
            let first = directory.appendingPathComponent("first.wav")
            let second = directory.appendingPathComponent("second.wav")
            try writeAudioFixture(spec, to: first)
            try writeAudioFixture(spec, to: second)

            #expect(
                try readBackSamples(of: first, channel: 0, limit: 1_024)
                    == readBackSamples(of: second, channel: 0, limit: 1_024)
            )
        }
    }

    // MARK: The short-final-chunk frame count

    @Test("the short-final-chunk frame count really is prime, so no chunk size divides it evenly")
    func shortFinalChunkFrameCountIsPrime() {
        let value = Int(framesWithShortFinalChunkAtAnyChunkSize)
        #expect(value > 1)

        var divisor = 2
        var divisors: [Int] = []
        while divisor * divisor <= value {
            if value % divisor == 0 { divisors.append(divisor) }
            divisor += 1
        }
        #expect(divisors.isEmpty, "expected no divisor, found \(divisors)")

        // The property that matters, stated directly: every chunk size from 2 up leaves a remainder,
        // so the final read is always short. Checked over the sizes the spike swept.
        for chunk in [2, 3, 7, 31, 64, 127, 1_024, 4_096] {
            #expect(value % chunk != 0)
        }
    }

    // MARK: Adverse fixtures

    @Test("a truncated fixture is a byte-exact prefix of the intact one")
    func truncationIsADeterministicPrefix() async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(name: "truncated", format: .wav, signal: .sine(frequency: 440, amplitude: 0.25), frames: 8_820)
            let url = try writeAudioFixture(spec, in: directory)
            let intact = try Data(contentsOf: url)

            try truncateFixture(at: url, toFirst: 512)

            let truncated = try Data(contentsOf: url)
            #expect(truncated.count == 512)
            #expect(truncated == intact.prefix(512))
            #expect(truncated != intact)
        }
    }

    @Test("a corrupt fixture keeps its length and differs only where it was overwritten")
    func corruptionIsBounded() async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(name: "corrupt", format: .wav, signal: .sine(frequency: 440, amplitude: 0.25), frames: 8_820)
            let url = try writeAudioFixture(spec, in: directory)
            let intact = try Data(contentsOf: url)

            let damaged = 2_000 ..< 2_100
            try corruptFixture(at: url, replacingBytesIn: damaged, with: 0xFF)

            let corrupt = try Data(contentsOf: url)
            #expect(corrupt.count == intact.count)
            #expect(corrupt != intact)
            #expect(corrupt[damaged].allSatisfy { $0 == 0xFF })
            #expect(corrupt.prefix(damaged.lowerBound) == intact.prefix(damaged.lowerBound))
            #expect(corrupt.suffix(from: damaged.upperBound) == intact.suffix(from: damaged.upperBound))
        }
    }

    @Test("an empty fixture is present and contains nothing")
    func emptyFixtureIsZeroBytes() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeEmptyFixture(named: "empty", format: .wav, in: directory)

            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try Data(contentsOf: url).isEmpty)
        }
    }

    // MARK: The temporary directory

    @Test("the temporary directory is removed after the body returns")
    func temporaryDirectoryIsCleanedUp() async throws {
        let captured = try await withTemporaryDirectory { directory -> URL in
            try writeAudioFixture(
                AudioFixtureSpec(name: "leftover", format: .wav, signal: .silence, frames: 512),
                in: directory
            )
            #expect(FileManager.default.fileExists(atPath: directory.path))
            return directory
        }

        #expect(!FileManager.default.fileExists(atPath: captured.path))
    }
}
