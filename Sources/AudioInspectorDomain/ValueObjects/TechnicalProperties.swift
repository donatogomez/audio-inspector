/// Basic, metadata-level technical properties of an audio file — **no DSP**. Each field is a
/// `Property`, so availability/certainty is explicit per field.
///
/// Numeric conventions (kept as simple standard-library types; no units library yet):
/// - `duration`: seconds (`Double`)
/// - `sampleRate`: hertz (`Int`)
/// - `channelCount`: a count (`Int`)
/// - `bitDepth`: bits (`Int`)
/// - `declaredBitrate` / `estimatedBitrate`: bits per second (`Int`)
/// - `container` / `codec`: lowercased identifier tokens (`String`), which are genuinely open-ended
///
/// `container` lives here because it is an **extracted technical property** (it can be unavailable/
/// uncertain/failed), not descriptive file metadata.
public struct TechnicalProperties: Sendable, Equatable {
    public var container: Property<String>
    public var duration: Property<Double>
    public var sampleRate: Property<Int>
    public var channelCount: Property<Int>
    public var bitDepth: Property<Int>
    public var codec: Property<String>
    public var declaredBitrate: Property<Int>
    public var estimatedBitrate: Property<Int>

    /// Defaults every field to `.unavailable(reason: nil)` so callers set only what they could read.
    public init(
        container: Property<String> = .unavailable(reason: nil),
        duration: Property<Double> = .unavailable(reason: nil),
        sampleRate: Property<Int> = .unavailable(reason: nil),
        channelCount: Property<Int> = .unavailable(reason: nil),
        bitDepth: Property<Int> = .unavailable(reason: nil),
        codec: Property<String> = .unavailable(reason: nil),
        declaredBitrate: Property<Int> = .unavailable(reason: nil),
        estimatedBitrate: Property<Int> = .unavailable(reason: nil)
    ) {
        self.container = container
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.codec = codec
        self.declaredBitrate = declaredBitrate
        self.estimatedBitrate = estimatedBitrate
    }
}
