import AudioInspectorDomain

/// A scripted, spying fake for the `WaveformGenerating` port — for tests and previews only.
///
/// It is an `actor` (not `@unchecked Sendable`, no manual locks) so its mutable spying state
/// (`callCount`, `lastFile`) is safe under Swift 6 strict concurrency, exactly like
/// `FakeAudioFilePropertyReading`.
///
/// Its three outcomes are the port's three outcomes, kept apart on purpose: an envelope, an **absence**
/// that is not a failure, and an error — which is also how cancellation arrives, carrying
/// `WaveformErrorCode.cancelled`. A caller that collapses any two of them will not be able to express
/// it here either.
public actor FakeWaveformGenerating: WaveformGenerating {
    /// What a `makeWaveform` call should do.
    public enum Outcome: Sendable {
        /// Return this envelope. An envelope with no buckets is a valid answer for a file with no
        /// frames — it is not the same as `absent`.
        case success(WaveformEnvelope)
        /// Return `nil`: the file offered nothing to size an envelope against. An absence caused by
        /// the file, never a failure and never a cancellation.
        case absent
        /// Throw this error. Use `WaveformErrorCode.cancelled` to script a cancelled generation.
        case failure(WaveformError)
    }

    private let outcome: Outcome

    /// How many times `makeWaveform(for:)` has been invoked.
    public private(set) var callCount = 0
    /// The `AudioFileReference` passed to the most recent invocation, if any.
    public private(set) var lastFile: AudioFileReference?

    public init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    /// Convenience: a fake that always returns `envelope`.
    public init(succeedingWith envelope: WaveformEnvelope) {
        self.init(.success(envelope))
    }

    /// Convenience: a fake that always fails with `error`.
    public init(failingWith error: WaveformError) {
        self.init(.failure(error))
    }

    public func makeWaveform(for file: AudioFileReference) async throws(WaveformError) -> WaveformEnvelope? {
        callCount += 1
        lastFile = file
        switch outcome {
        case let .success(envelope):
            return envelope
        case .absent:
            return nil
        case let .failure(error):
            throw error
        }
    }
}
