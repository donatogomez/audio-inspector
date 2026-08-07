import AVFoundation
import Foundation

// Deterministic audio fixtures for the waveform acceptance matrix (change
// `add-waveform-visualization`, group 0).
//
// Everything here describes and produces **files**. Nothing here reads samples to derive a result:
// there is no reduction, no envelope and no reference implementation of the future adapter — that
// would be a shadow of the code under test. The only read-back is `readBackMetadata`, which exists to
// prove a fixture is what it claims to be.
//
// No audio binary enters the repository: every fixture is generated into a caller-owned temporary
// directory and removed with it.

// MARK: - Formats

/// The container and codec a fixture is written in.
///
/// **MP3 is deliberately absent.** CoreAudio lists `MPG3` among its file formats but provides no
/// encoder for it: `afconvert -f 'MPG3' -d '.mp3'` fails with
/// `ExtAudioFileSetProperty ('cfmt') failed ('fmt?')`, and `AVAudioFile(forWriting:)` has no encoder
/// to reach either. An MP3 fixture therefore cannot be produced natively, and this type must not
/// pretend otherwise — see the change's task 0.6 for how that gap is closed.
enum AudioFixtureFormat: CaseIterable {
    case wav
    case aiff
    case alac
    case flac
    case aac

    var fileExtension: String {
        switch self {
        case .wav: "wav"
        case .aiff: "aiff"
        case .alac, .aac: "m4a"
        case .flac: "flac"
        }
    }

    func settings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        var settings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channels),
        ]
        switch self {
        case .wav:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        case .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = true
        case .alac:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 16
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 128_000
        }
        return settings
    }
}

// MARK: - Signals

/// The content written into a fixture: a pure function of `(channel, frame)`, so the same
/// specification always produces the same samples.
enum AudioFixtureSignal {
    /// Every sample zero.
    case silence
    /// A sine of the given frequency and amplitude, identical in every channel.
    case sine(frequency: Double, amplitude: Float)
    /// The same sine in every channel, with the sign flipped on odd channels — the case an averaging
    /// reduction would cancel to a flat line.
    case oppositePolarity(frequency: Double, amplitude: Float)
    /// A single non-zero frame at `frameIndex`, silence everywhere else.
    case impulse(amplitude: Float, frameIndex: Int)
    /// A different frequency in each channel, cycling if there are more channels than frequencies.
    /// Unlike `sine`, the channels are not copies of one another, so a codec that folded them together
    /// would not reproduce the source — useful where the encoder is outside our control.
    case perChannelSine(frequencies: [Double], amplitude: Float)
    /// A comb of sines from `lowest` up to `highest`, spaced by `spacing`, with the topmost component
    /// sitting **exactly** at `highest`.
    ///
    /// A band-limited source with a known edge, built without filtering anything: the file simply
    /// contains no component above `highest`, so the edge is a property of the specification rather
    /// than of a filter this package would have to implement and then trust. The total amplitude is
    /// divided between the components, so a dense comb stays inside full scale.
    case bandLimitedTones(highest: Double, spacing: Double, lowest: Double, amplitude: Float)

    /// The components of a `bandLimitedTones` signal, highest first.
    var toneFrequencies: [Double] {
        guard case let .bandLimitedTones(highest, spacing, lowest, _) = self else { return [] }
        var frequencies: [Double] = []
        var frequency = highest
        while frequency >= lowest {
            frequencies.append(frequency)
            frequency -= spacing
        }
        return frequencies
    }

    func sample(channel: Int, frame: Int, sampleRate: Double) -> Float {
        switch self {
        case .silence:
            0
        case let .bandLimitedTones(_, _, _, amplitude):
            {
                let frequencies = toneFrequencies
                guard !frequencies.isEmpty else { return 0 }
                let total = frequencies.reduce(0.0) { sum, frequency in
                    sum + sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate)
                }
                return amplitude * Float(total) / Float(frequencies.count)
            }()
        case let .perChannelSine(frequencies, amplitude):
            amplitude * Float(sin(
                2.0 * Double.pi * frequencies[channel % frequencies.count] * Double(frame) / sampleRate
            ))
        case let .sine(frequency, amplitude):
            amplitude * Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
        case let .oppositePolarity(frequency, amplitude):
            (channel.isMultiple(of: 2) ? 1 : -1)
                * amplitude * Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
        case let .impulse(amplitude, frameIndex):
            frame == frameIndex ? amplitude : 0
        }
    }
}

// MARK: - Specification

/// A frame count that leaves a **short final chunk at every chunk size above one**, because it is
/// prime and therefore divisible by nothing in between.
///
/// This exists because of a trap the spike walked into: 44 100 = 2²·3²·5²·7², so reading it at
/// capacities 1, 2, 3 or 7 produces no partial chunk at all and the region past `frameLength` is
/// never even exercised (see `docs/spikes/2026-08-05-native-pcm-decoding-validation.md`, gate 2.75).
/// A fixture sized like this cannot hide that case. `AudioFixtureSupportTests` verifies the primality
/// rather than trusting the comment.
let framesWithShortFinalChunkAtAnyChunkSize: AVAudioFrameCount = 44_101

/// A fixture, fully specified. Two specs that compare equal describe the same audio.
struct AudioFixtureSpec {
    var name: String
    var format: AudioFixtureFormat
    var signal: AudioFixtureSignal
    var sampleRate: Double = 44_100
    var channels: AVAudioChannelCount = 2
    var frames: AVAudioFrameCount = 44_100

    var fileName: String { "\(name).\(format.fileExtension)" }
}

/// What a written fixture reports about itself when opened again. Metadata only — no samples.
struct AudioFixtureMetadata: Equatable {
    var sampleRate: Double
    var channels: AVAudioChannelCount
    var frames: AVAudioFramePosition
}

// MARK: - Writing

/// Frames handed to the writer per call. Writing in chunks rather than one buffer keeps a long
/// fixture from allocating a buffer proportional to its duration, and exercises the multi-write path.
private let fixtureWriteChunk: AVAudioFrameCount = 4_096

enum AudioFixtureError: Error, CustomStringConvertible {
    case bufferAllocationFailed
    case processingFormatIsNotFloat

    var description: String {
        switch self {
        case .bufferAllocationFailed: "AVAudioPCMBuffer(pcmFormat:frameCapacity:) returned nil"
        case .processingFormatIsNotFloat: "the writer's processing format exposes no floatChannelData"
        }
    }
}

/// Writes `spec` into `directory` under its own file name, and returns the URL.
@discardableResult
func writeAudioFixture(_ spec: AudioFixtureSpec, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(spec.fileName)
    try writeAudioFixture(spec, to: url)
    return url
}

/// Writes `spec` at exactly `url`, for callers that already own the destination.
func writeAudioFixture(_ spec: AudioFixtureSpec, to url: URL) throws {
    try writeAudioFixture(spec, to: url, settings: spec.format.settings(sampleRate: spec.sampleRate, channels: spec.channels))
}

/// Writes `spec` as **32-bit float PCM**, whatever `spec.format` says, and returns the URL.
///
/// It exists for one criterion the integer formats cannot express: a sample beyond the nominal
/// `[-1, 1]`. A 16-bit integer container has no representation for one, so the value is limited on the
/// way in and a test written over it would assert the writer's clipping rather than the reduction's
/// honesty. Native float PCM round-trips such values exactly — the spike measured `-1.5 … +1.5` with a
/// maximum absolute error of 0.0.
///
/// It is deliberately **not** a case of `AudioFixtureFormat`: that enum is the group-0 acceptance
/// matrix, one row per format the product claims to decode, and adding a row to it would silently
/// change what the matrix asserts. This is a fixture for a property, not a format the product supports.
@discardableResult
func writeFloatPCMFixture(_ spec: AudioFixtureSpec, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("\(spec.name).wav")
    try writeAudioFixture(spec, to: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: spec.sampleRate,
        AVNumberOfChannelsKey: Int(spec.channels),
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
    ])
    return url
}

private func writeAudioFixture(_ spec: AudioFixtureSpec, to url: URL, settings: [String: Any]) throws {
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let format = file.processingFormat

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: fixtureWriteChunk) else {
        throw AudioFixtureError.bufferAllocationFailed
    }

    var written: AVAudioFrameCount = 0
    while written < spec.frames {
        let count = min(fixtureWriteChunk, spec.frames - written)
        buffer.frameLength = count

        guard let channelData = buffer.floatChannelData else {
            throw AudioFixtureError.processingFormatIsNotFloat
        }
        for channel in 0 ..< Int(format.channelCount) {
            let samples = channelData[channel]
            for offset in 0 ..< Int(count) {
                samples[offset] = spec.signal.sample(
                    channel: channel,
                    frame: Int(written) + offset,
                    sampleRate: spec.sampleRate
                )
            }
        }

        try file.write(from: buffer)
        written += count
    }
}

/// Opens a written fixture and reports what it says about itself.
///
/// This verifies the **fixture**, not a decoder: it reads no samples and computes nothing from them.
func readBackMetadata(of url: URL) throws -> AudioFixtureMetadata {
    let file = try AVAudioFile(forReading: url)
    return AudioFixtureMetadata(
        sampleRate: file.processingFormat.sampleRate,
        channels: file.processingFormat.channelCount,
        frames: file.length
    )
}

/// Reads one channel's samples back, for asserting that a fixture contains the signal it specifies.
///
/// Bounded by `frameLength` on every read, like the future adapter must be — reading the buffer's
/// capacity would pick up samples the API did not report (see ADR-0015).
func readBackSamples(of url: URL, channel: Int, limit: Int) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: fixtureWriteChunk) else {
        throw AudioFixtureError.bufferAllocationFailed
    }

    var samples: [Float] = []
    while file.framePosition < file.length, samples.count < limit {
        try file.read(into: buffer)
        let valid = Int(buffer.frameLength)
        if valid == 0 { break }
        guard let channelData = buffer.floatChannelData else {
            throw AudioFixtureError.processingFormatIsNotFloat
        }
        let source = channelData[channel]
        for offset in 0 ..< valid where samples.count < limit {
            samples.append(source[offset])
        }
    }
    return samples
}

// MARK: - Adverse fixtures

/// Keeps the first `byteCount` bytes and discards the rest. The result is a deterministic prefix of
/// the intact file — a truncation, not a random mutation.
func truncateFixture(at url: URL, toFirst byteCount: Int) throws {
    let data = try Data(contentsOf: url)
    try data.prefix(byteCount).write(to: url)
}

/// Overwrites `range` with `byte`, leaving the file's length unchanged. Both the range and the
/// replacement are the caller's, so a corrupt fixture is reproducible byte for byte.
func corruptFixture(at url: URL, replacingBytesIn range: Range<Int>, with byte: UInt8) throws {
    var data = try Data(contentsOf: url)
    let clamped = range.clamped(to: 0 ..< data.count)
    for index in clamped { data[index] = byte }
    try data.write(to: url)
}

/// A zero-byte file carrying an audio extension: present, named plausibly, and containing nothing.
@discardableResult
func writeEmptyFixture(named name: String, format: AudioFixtureFormat, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("\(name).\(format.fileExtension)")
    try Data().write(to: url)
    return url
}
