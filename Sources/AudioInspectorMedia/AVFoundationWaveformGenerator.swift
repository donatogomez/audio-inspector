import AVFoundation
import Foundation

import AudioInspectorDomain

/// The native (AVFoundation) implementation of the domain port `WaveformGenerating`.
///
/// It opens the selected file, verifies that its decoded form can be reduced correctly, reads it once
/// in bounded chunks, and folds each chunk into `WaveformEnvelopeAccumulator` — the domain's rules for
/// what a bucket contains. The loop, the buffer and the chunk size live here; the arithmetic does not
/// (ADR-0015 decision 7).
///
/// Boundary (ADR-0011): this type lives in `AudioInspectorMedia`, the only target allowed to import
/// AVFoundation, and returns **only** domain value types. No `AVAudioFile`, `AVAudioPCMBuffer`,
/// `AVAudioFormat`, `NSError`, `AVError` or `OSStatus` crosses the port; Apple errors are caught here
/// and mapped onto stable `WaveformErrorCode` values. No path, URL or Apple message reaches a message.
///
/// The file is opened **read-only**: nothing here writes, renames, moves or truncates it.
public struct AVFoundationWaveformGenerator: WaveformGenerating {
    /// Frames requested per read.
    ///
    /// 4 096 is four AAC packets (1 024 frames each, measured in the spike) and 32 KB of float32
    /// stereo, so a read is substantial enough to amortise its own cost while the buffer stays small
    /// enough to be irrelevant beside the envelope. It is a starting point, not a tuned constant, and
    /// it is declared once so no call site repeats the literal.
    public static let defaultChunkFrames: AVAudioFrameCount = 4_096

    /// Resolves the file URL to open for a domain reference.
    ///
    /// The domain `AudioFileReference` intentionally carries **no** URL/path/bookmark (ADR-0010); the
    /// composition root supplies the security-scoped URL for the duration of one operation. The
    /// default returns `nil`, so without a resolver generation fails as an access error rather than
    /// silently succeeding. No registry, no singleton, no stored URL, no bookmark.
    private let resolveURL: @Sendable (AudioFileReference) -> URL?
    private let chunkFrames: AVAudioFrameCount
    private let maximumBucketCount: Int

    /// Minimal initializer — no singletons, no shared or mutable state, no caches.
    public init(
        chunkFrames: AVAudioFrameCount = AVFoundationWaveformGenerator.defaultChunkFrames,
        maximumBucketCount: Int = WaveformBucketMapping.defaultMaximumBucketCount,
        resolveURL: @escaping @Sendable (AudioFileReference) -> URL? = { _ in nil }
    ) {
        self.chunkFrames = chunkFrames
        self.maximumBucketCount = maximumBucketCount
        self.resolveURL = resolveURL
    }

    public func makeWaveform(for file: AudioFileReference) async throws(WaveformError) -> WaveformEnvelope? {
        guard let url = resolveURL(file) else {
            throw WaveformError(
                code: .fileAccessDenied,
                message: "No accessible file location was provided for the waveform."
            )
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            // The Apple error is inspected nowhere and forwarded nowhere (ADR-0011 §5).
            throw WaveformError(code: .fileOpenFailed, message: "The file could not be opened for reading.")
        }

        let format = audioFile.processingFormat
        try Self.verifyReducible(format)

        // An unusable frame count is an **absence**, not a failure: the file opened and simply offered
        // nothing to size an envelope against. A count of zero is different again — that is a file with
        // no frames, and its envelope is a complete answer with no buckets.
        guard let frameCount = Self.usableFrameCount(audioFile.length, maximumBucketCount: maximumBucketCount) else {
            return nil
        }
        let channelCount = Int(format.channelCount)
        guard var accumulator = WaveformEnvelopeAccumulator(
            totalFrameCount: frameCount,
            channelCount: channelCount,
            maximumBucketCount: maximumBucketCount
        ) else {
            throw WaveformError(
                code: .invalidConfiguration,
                message: "A \(frameCount)-frame, \(channelCount)-channel file cannot be reduced at this resolution."
            )
        }
        if frameCount == 0 {
            return try accumulator.finished()
        }

        try await Self.read(audioFile, frameCount: frameCount, chunkFrames: chunkFrames, into: &accumulator)
        return try accumulator.finished()
    }
}

// MARK: - Format verification

// `internal` so the package's test target can drive these decisions with controlled inputs, without
// needing a file that this platform may be unable to produce. No Apple type crosses the port.
extension AVFoundationWaveformGenerator {
    /// Refuses any decoded layout the reading loop could not interpret correctly.
    ///
    /// This is not defensive habit. `AVAudioBuffer.h` states that on an **interleaved** buffer the
    /// per-channel pointers "refer into the same chunk of interleaved samples, each offset by 1 frame",
    /// with `stride` equal to the channel count. Reading one of those as a contiguous run would take
    /// samples from every channel, cover a fraction of the frames, and produce a **wrong envelope while
    /// tripping none of the reduction's invariants** — the values are finite, the frame range fits, and
    /// every bucket receives samples. The spike measured planar for the five formats it could write;
    /// five files are not an API guarantee, and this is the only place the mistake can be caught.
    static func verifyReducible(_ format: AVAudioFormat) throws(WaveformError) {
        guard format.channelCount >= 1 else {
            throw WaveformError(code: .unsupportedProcessingFormat, message: "The file decodes to no channels.")
        }
        guard format.commonFormat == .pcmFormatFloat32 else {
            throw WaveformError(
                code: .unsupportedProcessingFormat,
                message: "The file does not decode to 32-bit floating-point samples."
            )
        }
        guard !format.isInterleaved else {
            throw WaveformError(
                code: .unsupportedProcessingFormat,
                message: "The file decodes to interleaved samples, which cannot be read one channel at a time."
            )
        }
        guard format.isStandard else {
            throw WaveformError(
                code: .unsupportedProcessingFormat,
                message: "The file does not decode to the native deinterleaved floating-point layout."
            )
        }
    }

    /// The frame count to build an envelope for, or `nil` when the file offers none that can be used.
    ///
    /// Zero is **usable**: it describes a file with no frames. Negative is not, and neither is a count
    /// so large that the bucket mapping could not be computed for it.
    static func usableFrameCount(_ length: AVAudioFramePosition, maximumBucketCount: Int) -> Int? {
        guard length >= 0, let frameCount = Int(exactly: length) else { return nil }
        guard WaveformBucketMapping(totalFrameCount: frameCount, maximumBucketCount: maximumBucketCount) != nil
        else { return nil }
        return frameCount
    }
}

// MARK: - The reading loop

private extension AVFoundationWaveformGenerator {
    /// Reads the whole file once, in chunks, folding each into the accumulator.
    ///
    /// Two rules govern this loop and both come from measurements in
    /// `docs/spikes/2026-08-05-native-pcm-decoding-validation.md`:
    ///
    /// - **It is bounded by `framePosition < length`, never by watching for a zero-length read.** Reading
    ///   past the end threw a bridged failure carrying no `NSError` in all five formats measured, so
    ///   end-of-file is indistinguishable from a genuine error by the error value alone.
    /// - **Only `buffer.frameLength` frames are ever consumed; `frameCapacity` never is.** The region
    ///   between the two is never empty: four formats leave the previous read's samples there, and for
    ///   AAC content produced by the read path was observed even in a freshly zeroed buffer —
    ///   deterministic, derived from the audio, and about 1 % of its level. It is not noise that would
    ///   look obviously wrong; consuming it would draw something plausible and false.
    static func read(
        _ audioFile: AVAudioFile,
        frameCount: Int,
        chunkFrames: AVAudioFrameCount,
        into accumulator: inout WaveformEnvelopeAccumulator
    ) async throws(WaveformError) {
        let format = audioFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw WaveformError(code: .readFailed, message: "A reading buffer of the file's format could not be made.")
        }
        // Belt and braces beside the format check: a planar buffer reports a stride of one, and the
        // per-channel pointers below are only contiguous when it does.
        guard buffer.stride == 1 else {
            throw WaveformError(
                code: .unsupportedProcessingFormat,
                message: "The reading buffer interleaves its channels, which cannot be read one channel at a time."
            )
        }

        let channelCount = Int(format.channelCount)
        var framesRead = 0

        while framesRead < frameCount, audioFile.framePosition < audioFile.length {
            // Cancellation is observed at chunk boundaries: promptly, without abandoning a partial
            // envelope as if it were whole (`WaveformEnvelope` is only built after the loop).
            do {
                try Task.checkCancellation()
            } catch {
                throw WaveformError(code: .cancelled, message: "Waveform generation was cancelled.")
            }

            do {
                try audioFile.read(into: buffer)
            } catch {
                throw WaveformError(code: .readFailed, message: "The file could not be read to the end it declares.")
            }

            let valid = Int(buffer.frameLength)
            guard valid > 0 else {
                // The decoder stopped before the declared end without reporting a failure. Ending the
                // loop here would hand the accumulator an incomplete file and blame it for the gap.
                throw WaveformError(
                    code: .readFailed,
                    message: "The file stopped producing frames before the end it declares."
                )
            }
            guard let channelData = buffer.floatChannelData else {
                throw WaveformError(
                    code: .unsupportedProcessingFormat,
                    message: "The reading buffer exposes no floating-point samples."
                )
            }

            let usable = min(valid, frameCount - framesRead)
            for channel in 0 ..< channelCount {
                // A view over exactly the frames this read reported as valid — no copy, no `Array`, and
                // no way to reach past `frameLength`. `accumulate` is synchronous, so the pointer
                // cannot outlive the call.
                let samples = UnsafeBufferPointer(start: channelData[channel], count: usable)
                try accumulator.accumulate(samples, ofChannel: channel, startingAtFrame: framesRead)
            }
            framesRead += usable
        }

        guard framesRead == frameCount else {
            throw WaveformError(
                code: .readFailed,
                message: "The file yielded \(framesRead) of the \(frameCount) frames it declares."
            )
        }
    }
}
