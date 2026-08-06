import AudioInspectorDomain

/// A scripted, spying fake for the `AudioDecoding` port — for tests and previews only.
///
/// It exists so Analysis and feature tests can fold real chunks without a real file, an
/// `AVFoundation` import or a temporary directory. No media framework is reachable from here.
///
/// ## Why this one is not an actor
///
/// `FakeWaveformGenerating` and `FakeAudioFilePropertyReading` are actors, because their spying state
/// is the only mutable thing they hold and nothing else constrains them. This port is different: it
/// hands each chunk to a **synchronous, non-escaping callback that is deliberately not `@Sendable`**,
/// and an actor-isolated `decode` could not accept one — a caller's closure would have to cross into
/// the actor. The fake must therefore be exactly what the real adapter is: a `Sendable` struct whose
/// `decode` is nonisolated. Its spy is a separate `actor`, awaited before the callback is ever called,
/// so the recording is race-free without constraining the seam.
public struct FakeAudioDecoding: AudioDecoding {
    /// What a `decode` call should do.
    public enum Outcome: Sendable {
        /// Hand over `chunks` in order and return `stream`. A stream with a frame count of zero and no
        /// chunks is a valid answer for a file with no audio — it is not the same as `absent`.
        case stream(PCMStreamDescription, chunks: [PCMChunk])
        /// Return `nil`: the file exposed no usable frame count. An absence caused by the file, never a
        /// failure and never a cancellation.
        case absent
        /// Throw this error. Use `AudioDecodingErrorCode.cancelled` to script a cancelled decode.
        case failure(AudioDecodingError)
    }

    /// Records what the fake was asked to do. Separate from the fake itself so `decode` can stay
    /// nonisolated and keep accepting a non-`Sendable` callback.
    public actor Spy {
        /// How many times `decode` has been invoked.
        public private(set) var callCount = 0
        /// The `AudioFileReference` passed to the most recent invocation, if any.
        public private(set) var lastFile: AudioFileReference?
        /// The `chunkFrames` requested by the most recent invocation, if any.
        public private(set) var lastChunkFrames: Int?
        /// How many chunks the most recent invocation actually handed over before it ended — fewer than
        /// were scripted when the consumer answered `.stop`.
        public private(set) var lastDeliveredChunkCount = 0

        public init() {}

        func record(file: AudioFileReference, chunkFrames: Int) {
            callCount += 1
            lastFile = file
            lastChunkFrames = chunkFrames
            lastDeliveredChunkCount = 0
        }

        func recordDelivery(_ count: Int) {
            lastDeliveredChunkCount = count
        }
    }

    private let outcome: Outcome

    /// The recorder. Held by the caller too when it wants to assert on the calls.
    public let spy: Spy

    public init(_ outcome: Outcome, spy: Spy = Spy()) {
        self.outcome = outcome
        self.spy = spy
    }

    /// Convenience: a fake that hands over `chunks` and describes them with `stream`.
    public init(streaming stream: PCMStreamDescription, chunks: [PCMChunk], spy: Spy = Spy()) {
        self.init(.stream(stream, chunks: chunks), spy: spy)
    }

    /// Convenience: a fake that always fails with `error`.
    public init(failingWith error: AudioDecodingError, spy: Spy = Spy()) {
        self.init(.failure(error), spy: spy)
    }

    public func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription? {
        // Awaited **before** the callback is entered, so the whole delivery below stays synchronous
        // and the fake's timing matches the real adapter's: chunks arrive one after another, and the
        // call has returned by the time the caller sees the description.
        await spy.record(file: file, chunkFrames: chunkFrames)

        switch outcome {
        case let .stream(stream, chunks):
            var delivered = 0
            for chunk in chunks {
                delivered += 1
                if receive(chunk) == .stop { break }
            }
            await spy.recordDelivery(delivered)
            return stream
        case .absent:
            return nil
        case let .failure(error):
            throw error
        }
    }
}
