import AVFoundation
import Foundation

/// A fixture to be produced with public `AVAudioFile` writing APIs. The settings are the only thing
/// that differs between formats, so a generation failure points at the format, not at the harness.
struct FixtureSpec {
    let name: String
    let fileExtension: String
    let settings: [String: Any]
}

/// Deterministic fixture generation. Everything is written into a caller-owned temporary directory
/// and nothing is committed: the signal is a pure function of the parameters below, so the same call
/// always produces the same samples.
///
/// **Writing and reading are separate claims.** A format that writes may still fail to read, and a
/// format that fails to write says nothing about whether the decoder exists. The two are recorded in
/// different fields for exactly that reason.
enum FixtureFactory {
    static let sampleRate = 44100.0
    static let channels: AVAudioChannelCount = 2
    static let frames: AVAudioFrameCount = 44100 // exactly 1.0 s at 44 100 Hz

    /// The five natively-writable target formats. MP3 is absent on purpose: macOS has an MP3 decoder
    /// but no MP3 encoder, so it cannot appear here and is validated manually with FFmpeg instead.
    static func specs() -> [FixtureSpec] {
        [
            FixtureSpec(
                name: "WAV",
                fileExtension: "wav",
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: Int(channels),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ]
            ),
            FixtureSpec(
                name: "AIFF",
                fileExtension: "aiff",
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: Int(channels),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: true,
                ]
            ),
            FixtureSpec(
                name: "ALAC",
                fileExtension: "m4a",
                settings: [
                    AVFormatIDKey: kAudioFormatAppleLossless,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: Int(channels),
                    AVEncoderBitDepthHintKey: 16,
                ]
            ),
            FixtureSpec(
                name: "FLAC",
                fileExtension: "flac",
                settings: [
                    AVFormatIDKey: kAudioFormatFLAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: Int(channels),
                ]
            ),
            FixtureSpec(
                name: "AAC",
                fileExtension: "m4a",
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: Int(channels),
                    AVEncoderBitRateKey: 128_000,
                ]
            ),
        ]
    }

    /// Writes one fixture. Returns the frames handed to the writer — **not** a claim about how many
    /// frames the resulting file contains, which is what experiment B measures independently.
    static func write(_ spec: FixtureSpec, to url: URL) throws -> Int64 {
        let file = try AVAudioFile(forWriting: url, settings: spec.settings)
        let format = file.processingFormat

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw SpikeError("AVAudioPCMBuffer(pcmFormat:frameCapacity:) returned nil for \(spec.name)")
        }
        buffer.frameLength = frames

        guard let channelData = buffer.floatChannelData else {
            throw SpikeError("processingFormat for \(spec.name) exposes no floatChannelData (commonFormat = \(format.commonFormat.rawValue))")
        }

        // Deterministic: channel 0 at 440 Hz, channel 1 at 660 Hz, amplitude 0.25. Distinct per
        // channel so a later multichannel or phase experiment can tell the channels apart.
        let channelCount = Int(format.channelCount)
        for channel in 0 ..< channelCount {
            let frequency = channel == 0 ? 440.0 : 660.0
            let samples = channelData[channel]
            for frame in 0 ..< Int(frames) {
                samples[frame] = Float(0.25 * sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
            }
        }

        try file.write(from: buffer)
        return Int64(frames)
    }
}

// MARK: - Gate 2 fixtures

extension FixtureFactory {
    // MARK: D — multichannel

    /// Channels for the multichannel fixture. Four, so "at least three" is met with room to see an
    /// ordering error rather than just a count error.
    static let multichannelChannels: AVAudioChannelCount = 4

    /// Frames for the multichannel fixture: long enough to need several chunks at 4 096.
    static let multichannelFrames: AVAudioFrameCount = 10000

    /// The deterministic value written to channel `channel`, every frame: 0.1, 0.2, 0.3, 0.4.
    ///
    /// A constant per channel is chosen on purpose. It makes the three failures D looks for
    /// trivially visible and quantifiable: **mixing** shows as a value that is none of the four,
    /// **duplication** as two channels reading the same constant, and **loss** as a channel reading
    /// zero or missing. What it deliberately does *not* test is frame ordering **within** a channel —
    /// that is not what D is for, and no conclusion about it may be drawn here.
    static func multichannelValue(channel: Int) -> Float {
        Float(0.1 * Double(channel + 1))
    }

    /// Settings for the multichannel fixture, optionally carrying an explicit channel layout.
    /// Both variants are attempted and both outcomes are recorded — a format that needs a layout is
    /// an observation, not a workaround to hide.
    static func multichannelSettings(withLayout: Bool) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(multichannelChannels),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        if withLayout {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Quadraphonic
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        return settings
    }

    /// Writes the multichannel fixture. Returns the frames handed to the writer.
    static func writeMultichannel(to url: URL, withLayout: Bool) throws -> Int64 {
        let file = try AVAudioFile(forWriting: url, settings: multichannelSettings(withLayout: withLayout))
        let format = file.processingFormat

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: multichannelFrames) else {
            throw SpikeError("AVAudioPCMBuffer returned nil for the multichannel processing format")
        }
        buffer.frameLength = multichannelFrames

        guard let channelData = buffer.floatChannelData else {
            throw SpikeError("multichannel processingFormat exposes no floatChannelData (commonFormat = \(format.commonFormat.rawValue))")
        }

        for channel in 0 ..< Int(format.channelCount) {
            let value = multichannelValue(channel: channel)
            let samples = channelData[channel]
            for frame in 0 ..< Int(multichannelFrames) {
                samples[frame] = value
            }
        }

        try file.write(from: buffer)
        return Int64(multichannelFrames)
    }

    // MARK: E — values inside and outside the nominal range

    /// The exact values required, in order. Every one is written literally; none is scaled or nudged.
    static let rangePattern: [Float] = [-1.5, -1.0, -0.25, 0.0, 0.25, 1.0, 1.5]

    /// Four cycles of the pattern, so a per-frame comparison stays small enough to print in full.
    static let rangeFrames: AVAudioFrameCount = 28

    /// Channel 0 walks the pattern forwards; channel 1 walks it backwards, so the two channels are
    /// distinguishable and both signs are exercised at both ends of the buffer.
    static func rangeValue(channel: Int, frame: Int) -> Float {
        let index = frame % rangePattern.count
        return channel == 0 ? rangePattern[index] : rangePattern[rangePattern.count - 1 - index]
    }

    /// **Native float PCM**, 32-bit, so the file format itself can represent values beyond ±1. If it
    /// could not, the case is recorded as *not tested* rather than routed around.
    static func rangeSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }

    // MARK: C7 — two AAC files of identical structure and different content

    /// The two signals used by C7. Same sample rate, channel count and frame count; only the audio
    /// differs, so content is the single variable.
    enum AACContent {
        case alpha // 440 Hz / 660 Hz at 0.25
        case beta // 1000 Hz / 1500 Hz at 0.50

        func sample(channel: Int, frame: Int, sampleRate: Double) -> Float {
            let (frequency, amplitude): (Double, Double) = switch self {
            case .alpha: (channel == 0 ? 440.0 : 660.0, 0.25)
            case .beta: (channel == 0 ? 1000.0 : 1500.0, 0.50)
            }
            return Float(amplitude * sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate))
        }
    }

    static func writeAAC(to url: URL, content: AACContent) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderBitRateKey: 128_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw SpikeError("AVAudioPCMBuffer returned nil for the AAC processing format")
        }
        buffer.frameLength = frames

        guard let channelData = buffer.floatChannelData else {
            throw SpikeError("AAC processingFormat exposes no floatChannelData")
        }

        for channel in 0 ..< Int(format.channelCount) {
            let samples = channelData[channel]
            for frame in 0 ..< Int(frames) {
                samples[frame] = content.sample(channel: channel, frame: frame, sampleRate: sampleRate)
            }
        }

        try file.write(from: buffer)
    }

    static func writeRange(to url: URL) throws -> Int64 {
        let file = try AVAudioFile(forWriting: url, settings: rangeSettings())
        let format = file.processingFormat

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: rangeFrames) else {
            throw SpikeError("AVAudioPCMBuffer returned nil for the float range processing format")
        }
        buffer.frameLength = rangeFrames

        guard let channelData = buffer.floatChannelData else {
            throw SpikeError("float range processingFormat exposes no floatChannelData (commonFormat = \(format.commonFormat.rawValue))")
        }

        for channel in 0 ..< Int(format.channelCount) {
            let samples = channelData[channel]
            for frame in 0 ..< Int(rangeFrames) {
                samples[frame] = rangeValue(channel: channel, frame: frame)
            }
        }

        try file.write(from: buffer)
        return Int64(rangeFrames)
    }
}

/// A spike-local error. Nothing here maps to a domain error: this package defines no domain type.
struct SpikeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

// MARK: - Description helpers

enum Describe {
    /// FourCC as ASCII when all four bytes are unambiguously printable (`0x21`–`0x7E`, so space, NUL
    /// and control bytes are excluded), otherwise a fixed-width hex fallback. Same rule as spike 0031.
    static func fourCC(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let printable = bytes.allSatisfy { $0 >= 0x21 && $0 <= 0x7E }
        guard printable, let ascii = String(bytes: bytes, encoding: .ascii) else {
            return String(format: "0x%08X", code)
        }
        return "'\(ascii)'"
    }

    static func commonFormat(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .otherFormat: "other"
        case .pcmFormatFloat32: "float32"
        case .pcmFormatFloat64: "float64"
        case .pcmFormatInt16: "int16"
        case .pcmFormatInt32: "int32"
        @unknown default: "unknown(\(format.rawValue))"
        }
    }

    static func format(_ format: AVAudioFormat) -> String {
        let asbd = format.streamDescription.pointee
        return "\(fourCC(asbd.mFormatID)) \(commonFormat(format.commonFormat)) "
            + "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch, "
            + "\(asbd.mBitsPerChannel) bits/ch, \(asbd.mFramesPerPacket) frames/packet"
    }

    /// Errors are recorded verbatim — domain, code and description. No SDK code table is built from
    /// them (ADR-0011: classify by scope, never by numeric code).
    static func error(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}
