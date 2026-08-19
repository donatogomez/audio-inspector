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
    /// 32-bit **floating-point** WAV. The only writable container here that round-trips a sample beyond
    /// full scale: every other one quantises to 16-bit integer and clamps it. It exists so the
    /// "amplitude above 1.0 is reported, never clamped" rule can be proved through a real file rather
    /// than only against the reduction in isolation.
    case wavFloat
    case aiff
    case alac
    case flac
    case aac

    var fileExtension: String {
        switch self {
        case .wav, .wavFloat: "wav"
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
        case .wavFloat:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
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

/// One constant-amplitude region of a `segmentedSine`, measured in frames so a duration is exact
/// rather than rounded twice.
struct AudioFixtureSegment: Equatable {
    var amplitude: Float
    var frames: Int
}

/// The content written into a fixture: a pure function of `(channel, frame)`, so the same
/// specification always produces the same samples.
///
/// `Sendable` is stated rather than inferred: the composite cases below are `indirect`, and an
/// indirect enum loses the implicit conformance even though every payload here is a value type and
/// nothing is ever mutated after construction.
enum AudioFixtureSignal: Sendable {
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
    /// One sine at a fixed frequency whose **amplitude** steps at segment boundaries, identical in
    /// every channel. Frames past the last segment are silent.
    ///
    /// The phase is taken from the **absolute** frame index rather than restarted per segment, so the
    /// tone is continuous and only its envelope changes. That matters for a level-based measurement:
    /// restarting the phase would inject a step whose broadband energy is not part of the signal the
    /// segments describe.
    case segmentedSine(frequency: Double, segments: [AudioFixtureSegment])
    /// Several signals added together, sample by sample.
    ///
    /// The one primitive `bandLimitedTones` cannot express on its own: a programme *and* a second band
    /// at a different level, which is what a level-relative measurement has to be shown to separate.
    /// Nothing is normalised — the caller is responsible for the parts staying inside full scale — so
    /// the level of each part remains exactly what its own case says it is.
    indirect case sum([AudioFixtureSignal])
    /// Another signal scaled by a piecewise-constant envelope, silent past the last segment, with a
    /// raised-cosine ramp of `rampFrames` at each boundary.
    ///
    /// `segmentedSine` already does this for one sine; this does it for anything, which is what turns
    /// "a band at −30 dB" into "a band at −30 dB present for 10 % of the file". The envelope multiplies
    /// the inner signal rather than re-deriving it, so the inner phase stays continuous.
    ///
    /// **The ramp is not decoration.** An amplitude step is a broadband event: measured, a hard gate on
    /// a 16 kHz-limited comb put energy in every bin of the four windows straddling the boundary, which
    /// is enough to move a bandwidth reading to Nyquist whenever the eligible-window count is small.
    /// That energy is not part of the signal the segments describe. `rampFrames: 0` keeps the hard step
    /// for callers that want it.
    indirect case enveloped(AudioFixtureSignal, segments: [AudioFixtureSegment], rampFrames: Int)

    /// A comb whose **individual components** carry a stated amplitude.
    ///
    /// `bandLimitedTones` divides its amplitude between the components so a dense comb stays inside
    /// full scale, which means two combs of different widths at the same `amplitude` do **not** sit at
    /// the same per-bin level. A measurement that thresholds bins needs the per-bin figure, so this
    /// states that instead and lets the case do the arithmetic.
    static func tones(
        highest: Double, spacing: Double, lowest: Double, perComponentAmplitude: Float
    ) -> AudioFixtureSignal {
        let probe = AudioFixtureSignal.bandLimitedTones(
            highest: highest, spacing: spacing, lowest: lowest, amplitude: 1
        )
        let count = max(probe.toneFrequencies.count, 1)
        return .bandLimitedTones(
            highest: highest, spacing: spacing, lowest: lowest,
            amplitude: perComponentAmplitude * Float(count)
        )
    }

    /// A comb attenuated above `knee` at a stated slope — a graded roll-off rather than a cliff.
    ///
    /// Built as a `sum` of sines rather than a new case, because the only thing it needs that
    /// `bandLimitedTones` lacks is a per-component amplitude, and `sum` already provides that.
    static func slopedTones(
        highest: Double, spacing: Double, lowest: Double, perComponentAmplitude: Float,
        knee: Double, dBPerOctave: Double
    ) -> AudioFixtureSignal {
        var parts: [AudioFixtureSignal] = []
        var frequency = lowest
        while frequency <= highest {
            let attenuation = frequency <= knee ? 0 : dBPerOctave * log2(frequency / knee)
            parts.append(.sine(
                frequency: frequency,
                amplitude: perComponentAmplitude * Float(pow(10.0, -attenuation / 20.0))
            ))
            frequency += spacing
        }
        return .sum(parts)
    }

    /// The envelope's value at `frame`, ramps included. Zero past the last segment.
    static func envelopeAmplitude(
        at frame: Int, segments: [AudioFixtureSegment], rampFrames: Int
    ) -> Float {
        var start = 0
        for (index, segment) in segments.enumerated() {
            let end = start + segment.frames
            if frame < end {
                guard rampFrames > 0 else { return segment.amplitude }
                let before = index > 0 ? segments[index - 1].amplitude : 0
                let after = index + 1 < segments.count ? segments[index + 1].amplitude : 0
                if frame - start < rampFrames {
                    let position = Double(frame - start) / Double(rampFrames)
                    let weight = Float(0.5 - 0.5 * cos(Double.pi * position))
                    return before + (segment.amplitude - before) * weight
                }
                if end - frame <= rampFrames {
                    let position = Double(end - frame) / Double(rampFrames)
                    let weight = Float(0.5 - 0.5 * cos(Double.pi * position))
                    return after + (segment.amplitude - after) * weight
                }
                return segment.amplitude
            }
            start = end
        }
        return 0
    }

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

    /// `count` samples of one channel starting at `startFrame`, in one call.
    ///
    /// **Exactly equal to calling `sample(channel:frame:sampleRate:)` for each frame** — the arithmetic
    /// is the same expression, and `AudioFixtureSupportTests` asserts the equality rather than trusting
    /// this sentence. It exists only because the per-sample entry point costs about **3.8 µs** in an
    /// unoptimised build (measured: 36.9 s for the 4 800 000 stereo frames of EBU Tech 3341 test 4),
    /// which is enough to make the loudness suites unusable. The cost is Swift's, not the arithmetic's:
    /// the enum's associated array is retained and released once per sample, and hoisting it out of the
    /// loop is the whole optimisation.
    func samples(channel: Int, from startFrame: Int, count: Int, sampleRate: Double) -> [Float] {
        switch self {
        case let .sum(parts):
            // Each part gets the same hoisting the whole expression does, so a programme built from
            // three combs costs three fast passes rather than one slow one per sample.
            var output = [Float](repeating: 0, count: count)
            for part in parts {
                let partial = part.samples(channel: channel, from: startFrame, count: count, sampleRate: sampleRate)
                for index in 0 ..< count { output[index] += partial[index] }
            }
            return output
        case let .enveloped(inner, segments, rampFrames):
            var output = inner.samples(channel: channel, from: startFrame, count: count, sampleRate: sampleRate)
            for index in 0 ..< count {
                output[index] *= Self.envelopeAmplitude(
                    at: startFrame + index, segments: segments, rampFrames: rampFrames
                )
            }
            return output
        case let .bandLimitedTones(_, _, _, amplitude):
            // `toneFrequencies` rebuilds an array from the enum's payload, and reading it per sample is
            // the same retain/release cost the segmented case was written to avoid.
            let frequencies = toneFrequencies
            guard !frequencies.isEmpty else { return [Float](repeating: 0, count: count) }
            // The expression is `amplitude * Float(total) / Float(count)`, associated exactly as
            // `sample(channel:frame:sampleRate:)` writes it: `(a / c) * t` is not bit-identical to
            // `a * t / c`, and `AudioFixtureSupportTests` asserts the two entry points agree.
            let divisor = Float(frequencies.count)
            var output = [Float](repeating: 0, count: count)
            for index in 0 ..< count {
                let frame = Double(startFrame + index)
                var total = 0.0
                for frequency in frequencies { total += sin(2.0 * Double.pi * frequency * frame / sampleRate) }
                output[index] = amplitude * Float(total) / divisor
            }
            return output
        case .segmentedSine:
            break
        default:
            return (0 ..< count).map {
                sample(channel: channel, frame: startFrame + $0, sampleRate: sampleRate)
            }
        }
        guard case let .segmentedSine(frequency, segments) = self else { return [] }
        var output = [Float](repeating: 0, count: count)
        let end = startFrame + count
        output.withUnsafeMutableBufferPointer { buffer in
            var segmentStart = 0
            for segment in segments {
                let segmentEnd = segmentStart + segment.frames
                let lower = max(startFrame, segmentStart)
                let upper = min(end, segmentEnd)
                if lower < upper {
                    let amplitude = segment.amplitude
                    for frame in lower ..< upper {
                        buffer[frame - startFrame] = amplitude
                            * Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
                    }
                }
                segmentStart = segmentEnd
            }
        }
        return output
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
        case let .segmentedSine(frequency, segments):
            {
                var start = 0
                for segment in segments {
                    if frame < start + segment.frames {
                        return segment.amplitude
                            * Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
                    }
                    start += segment.frames
                }
                return 0
            }()
        case let .oppositePolarity(frequency, amplitude):
            (channel.isMultiple(of: 2) ? 1 : -1)
                * amplitude * Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
        case let .impulse(amplitude, frameIndex):
            frame == frameIndex ? amplitude : 0
        case let .sum(parts):
            parts.reduce(0) { $0 + $1.sample(channel: channel, frame: frame, sampleRate: sampleRate) }
        case let .enveloped(inner, segments, rampFrames):
            Self.envelopeAmplitude(at: frame, segments: segments, rampFrames: rampFrames)
                * inner.sample(channel: channel, frame: frame, sampleRate: sampleRate)
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
