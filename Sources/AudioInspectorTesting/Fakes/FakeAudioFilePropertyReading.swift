import AudioInspectorDomain

/// A scripted, spying fake for the `AudioFilePropertyReading` port — for tests and previews only.
///
/// It is an `actor` (not `@unchecked Sendable`, no manual locks) so its mutable spying state
/// (`callCount`, `lastFile`) is safe under Swift 6 strict concurrency. A single configured `Outcome`
/// decides whether a call succeeds with scripted `TechnicalProperties` or throws a global
/// `InspectionError`.
public actor FakeAudioFilePropertyReading: AudioFilePropertyReading {
    /// What a `readProperties` call should do.
    public enum Outcome: Sendable {
        /// Return these technical properties (with whatever per-property states the test scripted).
        case success(TechnicalProperties)
        /// Throw this global inspection error (typed throw).
        case failure(InspectionError)
    }

    private let outcome: Outcome

    /// How many times `readProperties(of:)` has been invoked.
    public private(set) var callCount = 0
    /// The `AudioFileReference` passed to the most recent invocation, if any.
    public private(set) var lastFile: AudioFileReference?

    public init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    /// Convenience: a fake that always succeeds with `properties`.
    public init(succeedingWith properties: TechnicalProperties) {
        self.init(.success(properties))
    }

    /// Convenience: a fake that always fails with `error`.
    public init(failingWith error: InspectionError) {
        self.init(.failure(error))
    }

    public func readProperties(of file: AudioFileReference) async throws(InspectionError) -> TechnicalProperties {
        callCount += 1
        lastFile = file
        switch outcome {
        case let .success(properties):
            return properties
        case let .failure(error):
            throw error
        }
    }
}
