import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

enum SpikeError: Error { case bufferAllocationFailed }

/// Decode a FourCharCode (e.g. an `AudioFormatID` or media subtype) into a stable, non-localized token.
///
/// The four bytes are **big-endian** (most-significant byte = first character), matching how CoreAudio
/// packs a `FourCharCode`. A token is rendered as ASCII only when every byte is an **unambiguous
/// printable** character `0x21…0x7E` — space (`0x20`), NUL and control bytes are deliberately excluded
/// so a space-padded or partially-empty FourCC (e.g. `'aac '`, `'ms\0\0'`) can never produce a visually
/// ambiguous token; those fall back to a fixed-width uppercase hex form. This is the candidate `codec`
/// token format under evaluation (Experiment C); the final serialization is deferred to 3.2/the ADR.
func fourCCToken(_ code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF),
    ]
    let unambiguouslyPrintable = bytes.allSatisfy { $0 >= 0x21 && $0 <= 0x7E }
    if unambiguouslyPrintable {
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
    return String(format: "0x%08X", code)
}

/// A raw dump of the interesting `AudioStreamBasicDescription` fields — no interpretation yet.
func dumpASBD(_ asbd: AudioStreamBasicDescription, indent: String) {
    print("\(indent)ASBD.mSampleRate       = \(asbd.mSampleRate)")
    print("\(indent)ASBD.mFormatID         = \(fourCCToken(asbd.mFormatID)) (hex 0x\(String(asbd.mFormatID, radix: 16)))")
    print("\(indent)ASBD.mFormatFlags      = 0x\(String(asbd.mFormatFlags, radix: 16))")
    print("\(indent)ASBD.mBytesPerPacket   = \(asbd.mBytesPerPacket)")
    print("\(indent)ASBD.mFramesPerPacket  = \(asbd.mFramesPerPacket)")
    print("\(indent)ASBD.mBytesPerFrame    = \(asbd.mBytesPerFrame)")
    print("\(indent)ASBD.mChannelsPerFrame = \(asbd.mChannelsPerFrame)")
    print("\(indent)ASBD.mBitsPerChannel   = \(asbd.mBitsPerChannel)")
}

/// Generate a tiny deterministic PCM fixture (WAV or AIFF, decided by the file extension) using only
/// public `AVAudioFile` APIs. A low-amplitude sine keeps the file non-trivial but small.
func generatePCMFixture(
    at url: URL,
    sampleRate: Double,
    channels: AVAudioChannelCount,
    bitDepth: Int,
    bigEndian: Bool,
    seconds: Double
) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: bitDepth,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: bigEndian,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let format = file.processingFormat
    let frameCount = AVAudioFrameCount((sampleRate * seconds).rounded())
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw SpikeError.bufferAllocationFailed
    }
    buffer.frameLength = frameCount
    if let channelData = buffer.floatChannelData {
        for channel in 0 ..< Int(format.channelCount) {
            let frequency = 440.0 * Double(channel + 1)
            for frame in 0 ..< Int(frameCount) {
                channelData[channel][frame] = Float(0.05 * sin(2.0 * .pi * frequency * Double(frame) / sampleRate))
            }
        }
    }
    try file.write(from: buffer)
}

/// A raw, per-file diagnostic dump. It prints the crude signals only — it does NOT build any
/// `Property<Value>` (that is deliberately out of scope for the spike).
func inspect(_ url: URL, label: String) async {
    print("──────────────────────────────────────────────────────────────────────")
    print("[\(label)] \(url.lastPathComponent)")
    print("  path.extension        = \(url.pathExtension.isEmpty ? "(none)" : url.pathExtension)")

    let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    print("  URL contentType (UTI) = \(contentType?.identifier ?? "(nil)")  [extension/type-driven]")

    let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    print("  fileSize (bytes)      = \(fileSize.map(String.init) ?? "(nil)")")

    let asset = AVURLAsset(url: url)

    var durationSeconds: Double?
    do {
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        durationSeconds = duration.isValid && duration.isNumeric ? seconds : nil
        print("  duration CMTime       = value=\(duration.value) timescale=\(duration.timescale) flags(valid=\(duration.isValid), numeric=\(duration.isNumeric), indefinite=\(duration.isIndefinite))")
        print("  duration seconds      = \(durationSeconds.map { String($0) } ?? "(not numeric)")")
    } catch {
        print("  duration LOAD ERROR   = \(error)")
    }

    do {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        print("  audio tracks          = \(tracks.count)")
        for (index, track) in tracks.enumerated() {
            print("  track[\(index)] trackID=\(track.trackID)")
            do {
                let formatDescriptions = try await track.load(.formatDescriptions)
                print("    formatDescriptions  = \(formatDescriptions.count)")
                for description in formatDescriptions {
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
                    print("    mediaSubType        = \(fourCCToken(mediaSubType))")
                    if let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                        dumpASBD(asbdPointer.pointee, indent: "    ")
                    } else {
                        print("    ASBD                = (nil)")
                    }
                }
            } catch {
                print("    formatDescriptions ERROR = \(error)")
            }
            do {
                let dataRate = try await track.load(.estimatedDataRate)
                print("    estimatedDataRate   = \(dataRate) bit/s  [API name: 'estimated']")
            } catch {
                print("    estimatedDataRate ERROR = \(error)")
            }
        }
    } catch {
        print("  audio tracks LOAD ERROR = \(error)")
    }

    if let fileSize, let durationSeconds, durationSeconds > 0 {
        let candidate = Double(fileSize) * 8.0 / durationSeconds
        print("  candidate file bitrate = \(candidate) bit/s  [fileSize*8/duration — includes container overhead → uncertain]")
    } else {
        print("  candidate file bitrate = (prerequisites not met — not computed)")
    }
}
