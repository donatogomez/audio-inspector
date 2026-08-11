/// Basic, metadata-level technical properties of an audio file — **no DSP**. Each field is a
/// `Property`, so availability/certainty is explicit per field.
///
/// Numeric conventions (kept as simple standard-library types; no units library yet):
/// - `duration`: seconds (`Double`)
/// - `sampleRate`: hertz (`Int`)
/// - `channelCount`: a count (`Int`)
/// - `bitDepth`: bits (`Int`)
/// - `declaredBitrate` / `estimatedBitrate` / `averageFileBitrate`: bits per second (`Int`)
/// - `container` / `codec`: identifier tokens (`String`), kept as `String` **deliberately** — the
///   value space is open-ended and detection-dependent, so they are not modelled as enums for this
///   slice. Normalization (e.g. lowercasing, canonical spelling) is the responsibility of the future
///   reading infrastructure (`AudioInspectorMedia`), not the domain type.
///
/// `container` lives here because it is an **extracted technical property** (it can be unavailable/
/// uncertain/failed), not descriptive file metadata.
///
/// `declaredBitrate`, `estimatedBitrate` and `averageFileBitrate` are three **separate, never-merged**
/// facts (ADR-0018): a value the container/codec itself declares, the framework's own track-level
/// estimate, and a value **calculated from the file's total size and its duration** — the whole file,
/// not the audio payload, so it always includes any container overhead (headers, metadata, embedded
/// artwork) and is therefore never reported as `available`, only ever `unavailable` or `uncertain`.
public struct TechnicalProperties: Sendable, Equatable {
    public var container: Property<String>
    public var duration: Property<Double>
    public var sampleRate: Property<Int>
    public var channelCount: Property<Int>
    public var bitDepth: Property<Int>
    public var codec: Property<String>
    public var declaredBitrate: Property<Int>
    public var estimatedBitrate: Property<Int>
    public var averageFileBitrate: Property<Int>

    /// Defaults every field to `.unavailable(reason: nil)` so callers set only what they could read.
    public init(
        container: Property<String> = .unavailable(reason: nil),
        duration: Property<Double> = .unavailable(reason: nil),
        sampleRate: Property<Int> = .unavailable(reason: nil),
        channelCount: Property<Int> = .unavailable(reason: nil),
        bitDepth: Property<Int> = .unavailable(reason: nil),
        codec: Property<String> = .unavailable(reason: nil),
        declaredBitrate: Property<Int> = .unavailable(reason: nil),
        estimatedBitrate: Property<Int> = .unavailable(reason: nil),
        averageFileBitrate: Property<Int> = .unavailable(reason: nil)
    ) {
        self.container = container
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.codec = codec
        self.declaredBitrate = declaredBitrate
        self.estimatedBitrate = estimatedBitrate
        self.averageFileBitrate = averageFileBitrate
    }
}
