import AVFoundation
import Foundation

import AudioInspectorDomain

/// The native (AVFoundation) implementation of the domain port `AudioDecoding`.
///
/// It opens the selected file, verifies that its decoded form can be read one channel at a time, and
/// hands the caller each chunk of PCM as it is read. It reduces nothing and interprets nothing: what a
/// consumer does with the samples is the consumer's business, which is what makes this a shared seam
/// rather than a second waveform reader (ADR-0016 decision 15).
///
/// Boundary (ADR-0011): this type lives in `AudioInspectorMedia`, the only target allowed to import
/// AVFoundation, and returns **only** domain value types. No `AVAudioFile`, `AVAudioPCMBuffer`,
/// `AVAudioFormat`, `NSError`, `AVError` or `OSStatus` crosses the port; Apple errors are caught here
/// and mapped onto stable `AudioDecodingErrorCode` values. No path, URL or Apple message reaches a
/// message.
///
/// **Nothing is stored between operations.** The file, the buffer and every pointer are created inside
/// `decode` and die with it, so there is no shared decoder state, no registry and no cache — which is
/// also why the type is an ordinary `Sendable` struct rather than an actor. Each operation is
/// independent, and cancelling one cannot affect another.
///
/// The file is opened **read-only**: nothing here writes, renames, moves or truncates it.
public struct AVFoundationAudioDecoder: AudioDecoding {
    /// Frames requested per read when a caller expresses no preference.
    ///
    /// **4 096, measured**: four AAC packets of 1 024 frames, and 32 KB of float32 stereo — substantial
    /// enough to amortise a read while the buffer stays irrelevant beside any accumulator's state.
    ///
    /// It used to be *derived* from `AVFoundationWaveformGenerator.defaultChunkFrames`, because both
    /// adapters read the same files through the same API and two drifting defaults would have made the
    /// two readers quietly incomparable. Since ADR-0021 there is only one reader, so this owns the
    /// number outright rather than borrowing it from a type production no longer uses. **The value is
    /// unchanged**, which is what keeps every existing chunking result comparable.
    public static let defaultChunkFrames = 4_096

    /// The largest read this adapter will size a buffer for, whatever a caller asks.
    ///
    /// `chunkFrames` is documented by the port as **a hint, not a contract**, and peak memory must stay
    /// a function of the chunk rather than of the file. One million frames is 4 MB per channel — far
    /// beyond any sensible request and still bounded — so an extravagant or hostile hint costs a larger
    /// read, never an allocation proportional to the caller's imagination. It also keeps the conversion
    /// to `AVAudioFrameCount` (a `UInt32`) exact, which a raw `Int` from the port would not.
    static let maximumChunkFrames = 1_048_576

    /// Resolves the file URL to open for a domain reference.
    ///
    /// The domain `AudioFileReference` intentionally carries **no** URL/path/bookmark (ADR-0010); the
    /// composition root supplies the security-scoped URL for the duration of one operation. The default
    /// returns `nil`, so without a resolver decoding fails as an access error rather than silently
    /// succeeding. No registry, no singleton, no stored URL, no bookmark — and the security scope is
    /// opened and closed by the caller that owns it, never here.
    private let resolveURL: @Sendable (AudioFileReference) -> URL?

    /// Minimal initializer — no singletons, no shared or mutable state, no caches.
    public init(resolveURL: @escaping @Sendable (AudioFileReference) -> URL? = { _ in nil }) {
        self.resolveURL = resolveURL
    }

    public func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription? {
        guard chunkFrames > 0 else {
            throw AudioDecodingError(
                code: .invalidConfiguration,
                message: "A decode must read at least one frame at a time; \(chunkFrames) was requested."
            )
        }
        guard let url = resolveURL(file) else {
            throw AudioDecodingError(
                code: .fileAccessDenied,
                message: "No accessible file location was provided for decoding."
            )
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            // The Apple error is inspected nowhere and forwarded nowhere (ADR-0011 §5).
            throw AudioDecodingError(code: .fileOpenFailed, message: "The file could not be opened for reading.")
        }

        let format = audioFile.processingFormat
        try Self.verifyReadable(format)

        // An unusable frame count is an **absence**, not a failure: the file opened and simply offered
        // no length to size an analysis against. A count of zero is different again — that is a file
        // with no frames, and its description is a complete answer.
        guard let frameCount = Self.usableFrameCount(audioFile.length) else { return nil }
        guard let stream = PCMStreamDescription(
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            frameCount: frameCount
        ) else {
            throw AudioDecodingError(
                code: .invalidStreamDescription,
                message: "The file describes a stream that cannot exist."
            )
        }

        // No frames means nothing to hand over. The callback is **not** invoked with an empty chunk:
        // a consumer folding chunks would have to special-case one that says nothing, and the
        // description already tells it there was no audio.
        guard frameCount > 0 else { return stream }

        try await Self.read(audioFile, stream: stream, chunkFrames: chunkFrames, receive: receive)
        return stream
    }
}

// MARK: - Format verification

// `internal` so the package's test target can drive these decisions with controlled inputs, without
// needing a file that this platform may be unable to produce. No Apple type crosses the port.
extension AVFoundationAudioDecoder {
    /// Refuses any decoded layout the reading loop could not interpret correctly.
    ///
    /// This is not defensive habit. `AVAudioBuffer.h` states that on an **interleaved** buffer the
    /// per-channel pointers "refer into the same chunk of interleaved samples, each offset by 1 frame",
    /// with `stride` equal to the channel count. Copying one of those as a contiguous run would take
    /// samples from every channel, cover a fraction of the frames, and produce a chunk that **passes
    /// every invariant `PCMChunk` has** — the values are finite, the channels are equal in length and
    /// the frame range fits. It would be plausible and wrong, which is the one failure mode the domain
    /// boundary cannot catch, so it is caught here instead.
    ///
    /// The spike observed planar float for the five formats it could write. Five files are not an API
    /// guarantee, and this check does not treat them as one.
    static func verifyReadable(_ format: AVAudioFormat) throws(AudioDecodingError) {
        guard format.channelCount >= 1 else {
            throw AudioDecodingError(
                code: .unsupportedProcessingFormat,
                message: "The file decodes to no channels."
            )
        }
        guard format.commonFormat == .pcmFormatFloat32 else {
            throw AudioDecodingError(
                code: .unsupportedProcessingFormat,
                message: "The file does not decode to 32-bit floating-point samples."
            )
        }
        guard !format.isInterleaved else {
            throw AudioDecodingError(
                code: .unsupportedProcessingFormat,
                message: "The file decodes to interleaved samples, which cannot be copied one channel at a time."
            )
        }
        guard format.isStandard else {
            throw AudioDecodingError(
                code: .unsupportedProcessingFormat,
                message: "The file does not decode to the native deinterleaved floating-point layout."
            )
        }
    }

    /// The frame count to decode, or `nil` when the file offers none that can be used.
    ///
    /// Zero is **usable**: it describes a file with no frames. Negative is not, and neither is a length
    /// that does not survive the conversion to `Int` exactly.
    static func usableFrameCount(_ length: AVAudioFramePosition) -> Int? {
        guard length >= 0, let frameCount = Int(exactly: length) else { return nil }
        return frameCount
    }
}

// MARK: - The reading loop

private extension AVFoundationAudioDecoder {
    /// Reads the whole file once, in chunks, handing each to `receive` before the next is read.
    ///
    /// Two rules govern this loop and both come from measurements in
    /// `docs/spikes/2026-08-05-native-pcm-decoding-validation.md`:
    ///
    /// - **It is bounded by `framePosition < length`, never by watching for a zero-length read.**
    ///   Reading past the end threw a bridged failure carrying no `NSError` in all five formats
    ///   measured, so end-of-file is indistinguishable from a genuine error by the error value alone.
    /// - **Only `buffer.frameLength` frames are ever copied; `frameCapacity` never is.** The region
    ///   between the two is never empty, and — this is the part that makes it dangerous — it is
    ///   **deterministic**. Four formats leave the previous read's samples there; for AAC, content
    ///   produced by the read path itself was observed even in a freshly zeroed buffer, derived from the
    ///   audio and at roughly 1 % of its level. Being deterministic is exactly why it cannot be caught
    ///   downstream: it is finite, it is bounded, it correlates with the signal, and a test that ran
    ///   twice would see the same wrong answer both times. `frameLength` is the only statement about
    ///   which frames the API actually decoded.
    static func read(
        _ audioFile: AVAudioFile,
        stream: PCMStreamDescription,
        chunkFrames: Int,
        receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) {
        let format = audioFile.processingFormat
        // The hint is bounded before it becomes an allocation, and the clamp is what makes the
        // conversion to `UInt32` exact rather than merely likely.
        let capacity = AVAudioFrameCount(min(chunkFrames, maximumChunkFrames))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioDecodingError(
                code: .readFailed,
                message: "A reading buffer of the file's format could not be made."
            )
        }
        // Belt and braces beside the format check: a planar buffer reports a stride of one, and the
        // per-channel copies below are only correct when it does.
        guard buffer.stride == 1 else {
            throw AudioDecodingError(
                code: .unsupportedProcessingFormat,
                message: "The reading buffer interleaves its channels, which cannot be copied one channel at a time."
            )
        }

        let channelCount = stream.channelCount
        var framesDelivered = 0

        while framesDelivered < stream.frameCount, audioFile.framePosition < audioFile.length {
            // Cancellation is observed at chunk boundaries: promptly, and as its own outcome rather
            // than as an absence or a defect of the file.
            do {
                try Task.checkCancellation()
            } catch {
                throw AudioDecodingError(code: .cancelled, message: "Decoding was cancelled.")
            }

            do {
                try audioFile.read(into: buffer, frameCount: capacity)
            } catch {
                throw AudioDecodingError(
                    code: .readFailed,
                    message: "The file could not be read to the end it declares."
                )
            }

            let valid = Int(buffer.frameLength)
            guard valid > 0 else {
                // The decoder stopped before the declared end without reporting a failure. Ending the
                // loop here would hand the consumer a short file and call it complete.
                throw AudioDecodingError(
                    code: .readFailed,
                    message: "The file stopped producing frames before the end it declares."
                )
            }
            guard let channelData = buffer.floatChannelData else {
                throw AudioDecodingError(
                    code: .unsupportedProcessingFormat,
                    message: "The reading buffer exposes no floating-point samples."
                )
            }

            var channels: [[Float]] = []
            channels.reserveCapacity(channelCount)
            for channel in 0 ..< channelCount {
                // Exactly the frames the read reported, copied — **not** `min(valid, remaining)`. That
                // clamp is the obvious way to write this loop and it is a mistake: it silently discards
                // anything a decoder hands over beyond the declared length, so a file that over-reads
                // and a file that reads correctly become the same result. It also makes the bound below
                // unreachable, which is how a wrong bound stops being observable at all — measured, not
                // theorised: with the clamp in place, replacing `frameLength` with `frameCapacity`
                // changes nothing this suite can see.
                //
                // The chunk owns its samples, so no pointer outlives this iteration and no consumer
                // inherits a lifetime to respect.
                //
                // Copied through an explicit `update(from:count:)` rather than
                // `Array(UnsafeBufferPointer(...))`: for a trivial element both are a memory copy once
                // the optimiser has specialised the generic initialiser, but an unoptimised build does
                // not specialise it and walks the buffer one element at a time through an iterator.
                // This runs on every sample of every channel, so the difference is measurable in the
                // build a developer actually runs.
                var samples = [Float](repeating: 0, count: valid)
                samples.withUnsafeMutableBufferPointer { destination in
                    if let base = destination.baseAddress {
                        base.update(from: channelData[channel], count: valid)
                    }
                }
                channels.append(samples)
            }

            // The domain decides whether this is a possible run of audio — finiteness included. There
            // is deliberately no second finiteness check here: two boundaries enforcing one rule is one
            // boundary too many, and the codes below are the domain's own, forwarded unchanged.
            let chunk = try PCMChunk(startFrame: framesDelivered, channels: channels)

            // A chunk that does not fit the stream it came from is a fault of **this reader**, not of
            // the chunk: `invalidChunk` says the parts do not describe a possible run of audio, and
            // these do — equal channels, a non-negative start, finite samples. What is wrong is the
            // relationship between two things only this loop holds at once, so it is reported as what
            // it is: the file did not read the way it declared itself.
            //
            // This is also the bound that makes `frameLength` observable. Consume the buffer's capacity
            // instead and the final read overruns the declared length, which arrives here rather than
            // being quietly trimmed away.
            guard chunk.fits(stream) else {
                throw AudioDecodingError(
                    code: .readFailed,
                    message: "The file yielded frames beyond the \(stream.frameCount) it declares."
                )
            }

            framesDelivered += valid
            if receive(stream, chunk) == .stop { return }
        }

        // Coverage is only a promise when the read was allowed to finish. A consumer that answered
        // `.stop` has already returned above, so reaching here means the loop ended on its own — and
        // then a short read is a fault rather than a choice.
        guard framesDelivered == stream.frameCount else {
            throw AudioDecodingError(
                code: .readFailed,
                message: "The file yielded \(framesDelivered) of the \(stream.frameCount) frames it declares."
            )
        }
    }
}
