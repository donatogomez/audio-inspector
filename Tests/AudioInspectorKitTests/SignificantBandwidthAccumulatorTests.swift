import AVFoundation
import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
import Foundation
import Testing

// Group 3: the production accumulator, against the targets group 2 already pinned.
//
// **The expected values are not new.** They are group 2's, measured with the reference implementation
// before this type existed, and they are not widened here. Where a number differs, the accumulator is
// wrong — that is the whole point of having settled them first.

// MARK: - Driving the production type

private func measure(
    fileAt url: URL, chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames
) async throws -> SignificantBandwidth? {
    let decoder = AVFoundationAudioDecoder(resolveURL: { _ in url })
    let file = AudioFileReference(
        displayName: url.lastPathComponent, fileExtension: url.pathExtension,
        sizeBytes: nil, modifiedAt: nil,
        source: .userSelectedLocalFile(displayName: url.lastPathComponent, locationDisclosure: .omitted)
    )
    var accumulator: SignificantBandwidthAccumulator?
    _ = try await decoder.decode(file, chunkFrames: chunkFrames) { stream, chunk in
        if accumulator == nil {
            accumulator = SignificantBandwidthAccumulator(
                sampleRate: stream.sampleRate, channelCount: stream.channelCount
            )
        }
        accumulator?.accumulate(chunk)
        return .continue
    }
    return accumulator?.finish()
}

private func programme(to edge: Double, level: Float = 0.01) -> AudioFixtureSignal {
    .tones(highest: edge, spacing: 500, lowest: 500, perComponentAmplitude: level)
}

private func highBand(relativeDB: Double, programmeLevel: Float = 0.01) -> AudioFixtureSignal {
    .tones(
        highest: 20_000, spacing: 500, lowest: 19_000,
        perComponentAmplitude: programmeLevel * Float(pow(10.0, relativeDB / 20))
    )
}

private func write(
    _ signal: AudioFixtureSignal, name: String, sampleRate: Double = 48_000,
    channels: AVAudioChannelCount = 1, seconds: Double = 1, in directory: URL
) throws -> URL {
    try writeAudioFixture(
        AudioFixtureSpec(
            name: name, format: .wavFloat, signal: signal, sampleRate: sampleRate,
            channels: channels, frames: AVAudioFrameCount(sampleRate * seconds)
        ),
        in: directory
    )
}

/// Group 2's contract, unchanged: one-sided upward, within the Hann skirt's reach.
private func expectEdge(
    _ channel: SignificantBandwidth.Channel?, at edge: Double, _ comment: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let reading = try #require(channel, comment, sourceLocation: sourceLocation)
    let error = reading.frequency - edge
    #expect(error >= -reading.resolution, "\(comment): read \(reading.frequency) Hz for a \(edge) Hz edge", sourceLocation: sourceLocation)
    #expect(error <= 5 * reading.resolution, "\(comment): read \(reading.frequency) Hz, \(error / reading.resolution) resolutions above \(edge)", sourceLocation: sourceLocation)
}

// MARK: - Equivalence with the targets group 2 settled

@Suite("Analysis — significant bandwidth accumulator reproduces group 2's targets")
struct SignificantBandwidthEquivalenceTests {

    @Test(
        "a known spectral edge, at every rate",
        arguments: [44_100.0, 48_000, 88_200, 96_000, 192_000], [8_000.0, 12_000, 16_000, 20_000]
    )
    func knownEdge(sampleRate: Double, edge: Double) async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(programme(to: edge), name: "edge-\(Int(sampleRate))-\(Int(edge))", sampleRate: sampleRate, in: directory)
            let measurement = try #require(try await measure(fileAt: url))
            #expect(measurement.method.identifier == SignificantBandwidthMethod.v1)
            #expect(measurement.method.sampleRate == sampleRate)
            #expect(abs(measurement.method.windowSeconds - SignificantBandwidthAccumulator.targetWindowSeconds) < 0.001)
            try expectEdge(measurement.overall, at: edge, "\(Int(sampleRate)) Hz, edge \(Int(edge)) Hz")
        }
    }

    @Test("a high band inside the threshold is kept, one below it is not", arguments: [-30.0, -40, -60, -70])
    func threshold(relativeDB: Double) async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.sum([programme(to: 16_000), highBand(relativeDB: relativeDB)]), name: "thr-\(Int(-relativeDB))", in: directory)
            let measurement = try #require(try await measure(fileAt: url))
            try expectEdge(measurement.overall, at: relativeDB >= -40 ? 20_000 : 16_000, "a band \(Int(relativeDB)) dB down")
        }
    }

    @Test("persistence: a quarter of the file is kept, a twentieth is not", arguments: [0.05, 0.25, 1.0])
    func persistence(share: Double) async throws {
        try await withTemporaryDirectory { directory in
            let frames = 48_000, on = Int(Double(frames) * share)
            let url = try write(
                .sum([
                    programme(to: 16_000),
                    .enveloped(highBand(relativeDB: -30), segments: [.init(amplitude: 1, frames: on), .init(amplitude: 0, frames: frames - on)], rampFrames: 256),
                ]),
                name: "pers-\(Int(share * 100))", in: directory
            )
            let measurement = try #require(try await measure(fileAt: url))
            try expectEdge(measurement.overall, at: share >= 0.25 ? 20_000 : 16_000, "a band present \(Int(share * 100)) % of the file")
        }
    }

    /// The declared 60 dB budget and its declared cost, both directions.
    @Test("the programme budget measures a passage inside it and not one below", arguments: [-50.0, -60, -70, -80])
    func budget(down: Double) async throws {
        try await withTemporaryDirectory { directory in
            let half = 24_000, gain = Float(pow(10.0, down / 20))
            let url = try write(
                .sum([
                    .enveloped(programme(to: 16_000), segments: [.init(amplitude: 1, frames: half)], rampFrames: 256),
                    .enveloped(
                        .sum([programme(to: 16_000, level: 0.01 * gain), highBand(relativeDB: -30, programmeLevel: 0.01 * gain)]),
                        segments: [.init(amplitude: 0, frames: half), .init(amplitude: 1, frames: half)], rampFrames: 256
                    ),
                ]),
                name: "budget-\(Int(-down))", in: directory
            )
            let measurement = try #require(try await measure(fileAt: url))
            try expectEdge(measurement.overall, at: down >= -60 ? 20_000 : 16_000, "a passage \(Int(down)) dB below the programme")
        }
    }

    @Test("every lossless container reads the same bin", arguments: [AudioFixtureFormat.wav, .wavFloat, .aiff, .alac, .flac])
    func containers(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let signal = AudioFixtureSignal.sum([programme(to: 16_000), highBand(relativeDB: -30)])
            let reference = try #require(try await measure(fileAt: try writeAudioFixture(
                AudioFixtureSpec(name: "c-ref", format: .wavFloat, signal: signal, sampleRate: 48_000, channels: 1, frames: 48_000), in: directory
            ))?.overall)
            let candidate = try #require(try await measure(fileAt: try writeAudioFixture(
                AudioFixtureSpec(name: "c-\(format.fileExtension)", format: format, signal: signal, sampleRate: 48_000, channels: 1, frames: 48_000), in: directory
            ))?.overall)
            #expect(candidate == reference, "\(format) read \(candidate.frequency) where float WAV read \(reference.frequency)")
        }
    }
}

// MARK: - Silence, edges and the absence of a clamp

@Suite("Analysis — significant bandwidth: silence, absence and file edges")
struct SignificantBandwidthSilenceTests {

    /// **This test is what stands between the method and an epsilon.** A window of zeros transforms to
    /// magnitude exactly zero, so it carries no peak, is not an observation, and needs no absolute rule
    /// to exclude it. Any clamp in the transform path makes this test fail — which is the point.
    @Test("digital silence is an absence, not a reading")
    func digitalSilence() async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.silence, name: "silence", in: directory)
            let measurement = try await measure(fileAt: url)
            #expect(measurement?.overall == nil, "silence produced \(String(describing: measurement?.overall))")
            #expect(measurement?.channels.first.flatMap { $0 } == nil)
        }
    }

    @Test("a file holding no audio yields no measurement")
    func noFrames() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "empty", format: .wav, signal: .silence, sampleRate: 48_000, channels: 1, frames: 0),
                in: directory
            )
            #expect(try await measure(fileAt: url)?.overall == nil)
        }
    }

    /// The final incomplete window is discarded, never zero-padded, so a file shorter than one window
    /// produces nothing at all rather than something padded.
    @Test("a file shorter than one window yields no measurement", arguments: [1, 1_000, 2_047])
    func shorterThanAWindow(frames: AVAudioFrameCount) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "short-\(frames)", format: .wavFloat, signal: .sine(frequency: 1_000, amplitude: 0.5), sampleRate: 48_000, channels: 1, frames: frames),
                in: directory
            )
            #expect(try await measure(fileAt: url)?.overall == nil)
        }
    }

    @Test("exactly one window produces a measurement")
    func exactlyOneWindow() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "one", format: .wavFloat, signal: .sine(frequency: 1_000, amplitude: 0.5), sampleRate: 48_000, channels: 1, frames: 2_048),
                in: directory
            )
            try expectEdge(try await measure(fileAt: url)?.overall, at: 1_000, "a single window")
        }
    }

    /// A prime frame count leaves a short final chunk at every chunk size above one.
    @Test("a short final chunk changes nothing")
    func shortFinalChunk() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "prime", format: .wavFloat,
                    signal: .sum([programme(to: 16_000), highBand(relativeDB: -30)]),
                    sampleRate: 48_000, channels: 1, frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )
            let a = try #require(try await measure(fileAt: url, chunkFrames: 4_096))
            let b = try #require(try await measure(fileAt: url, chunkFrames: 997))
            #expect(a == b)
        }
    }
}

// MARK: - Chunk independence

@Suite("Analysis — significant bandwidth is independent of chunk size")
struct SignificantBandwidthChunkIndependenceTests {

    /// The port's own contract: "the result of any correct consumer must not depend on this value".
    /// Exact equality, no tolerance — the windows are cut from frame zero at a fixed stride, so a chunk
    /// boundary has nowhere to enter the arithmetic.
    @Test(
        "the same file measures identically at every chunk size",
        arguments: [1, 3, 127, 512, 4_096, 65_536, 1 << 20],
        [48_000.0, 192_000.0]
    )
    func chunkSizes(chunkFrames: Int, sampleRate: Double) async throws {
        try await withTemporaryDirectory { directory in
            for (name, signal, seconds) in cases {
                let url = try write(signal, name: "\(name)-\(Int(sampleRate))", sampleRate: sampleRate, seconds: seconds, in: directory)
                let whole = try await measure(fileAt: url, chunkFrames: 1 << 22)
                let chunked = try await measure(fileAt: url, chunkFrames: chunkFrames)
                #expect(chunked == whole, "\(name) at \(Int(sampleRate)) Hz differs at \(chunkFrames)-frame chunks")
            }
        }
    }

    /// A hard edge, a weak persistent band, a file sitting on the budget boundary, and silence.
    private var cases: [(String, AudioFixtureSignal, Double)] {
        let half = 12_000
        return [
            ("edge", programme(to: 16_000), 0.5),
            ("weak-band", .sum([programme(to: 16_000), highBand(relativeDB: -40)]), 0.5),
            ("budget-boundary", .sum([
                .enveloped(programme(to: 16_000), segments: [.init(amplitude: 1, frames: half)], rampFrames: 256),
                .enveloped(
                    .sum([
                        programme(to: 16_000, level: 0.01 * Float(pow(10.0, -60.0 / 20))),
                        highBand(relativeDB: -30, programmeLevel: 0.01 * Float(pow(10.0, -60.0 / 20))),
                    ]),
                    segments: [.init(amplitude: 0, frames: half), .init(amplitude: 1, frames: half)], rampFrames: 256
                ),
            ]), 0.5),
            ("silence", .silence, 0.5),
        ]
    }
}
