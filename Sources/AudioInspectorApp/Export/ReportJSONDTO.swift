import Foundation

// The wire DTOs for `schemaVersion` 1 (docs/json-schema-v1.md). They are `Encodable` only (export is
// one-directional — no decoder), and they are the export layer's private business: the domain never
// conforms to `Encodable` (ADR-0009). Null-vs-absence is controlled explicitly where the schema
// requires an explicit `null` rather than an omitted key — Swift's synthesized `Encodable` would
// otherwise omit `nil` optionals, which is wrong for the schema's nullable fields.

/// A closed, typed JSON scalar. The value space of the v1 contract is exactly these three; encoding
/// each through a single-value container yields a **real** JSON scalar (a number is a number, never a
/// quoted string). `Double.nan`/`±infinity` are rejected by `JSONEncoder`'s default non-conforming
/// float strategy, so a non-representable value fails encoding instead of emitting a fiction.
enum JSONScalar: Encodable {
    case string(String)
    case int(Int)
    case double(Double)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        }
    }
}

/// A stable `{ code, message }` object — the shape shared by a property `failed` error and a global
/// `inspectionStatus.error`. Both fields are always present. `CodingKeys` pins the wire names so a
/// Swift property rename can never silently change the contract.
struct CodeMessageDTO: Encodable {
    let code: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case code, message
    }
}

/// The `generator` envelope object. Both fields always present; wire names pinned by `CodingKeys`.
struct GeneratorDTO: Encodable {
    let name: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case name, version
    }
}

/// The safe `source` object. All three fields always present; carries no path/URL/bookmark by shape.
/// Wire names pinned by `CodingKeys`.
struct SourceDTO: Encodable {
    let kind: String
    let displayName: String
    let locationDisclosure: String

    enum CodingKeys: String, CodingKey {
        case kind, displayName, locationDisclosure
    }
}

/// `inspectedFile`. `fileExtension`/`sizeBytes`/`modifiedAt` are schema-nullable and MUST appear as
/// explicit `null` when absent (the global-failure example shows `"modifiedAt": null`), so this type
/// encodes them by hand rather than relying on synthesized omit-on-nil. `modifiedAt` is a `Date` so
/// the encoder's ISO-8601 strategy formats it centrally. There is no `path` field by construction.
struct InspectedFileDTO: Encodable {
    let name: String
    let fileExtension: String?
    let sizeBytes: Int?
    let modifiedAt: Date?
    let source: SourceDTO

    private enum CodingKeys: String, CodingKey {
        case name, fileExtension, sizeBytes, modifiedAt, source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        // Schema-nullable → explicit `null`, never an omitted key.
        try encodeExplicit(fileExtension, forKey: .fileExtension, into: &container)
        try encodeExplicit(sizeBytes, forKey: .sizeBytes, into: &container)
        try encodeExplicit(modifiedAt, forKey: .modifiedAt, into: &container)
        try container.encode(source, forKey: .source)
    }
}

/// A single technical property in flat wire form: `{ state, value?, unit?, reason?, error? }`.
/// `value` is always present (explicit `null` when there is none); `unit`/`reason`/`error` are
/// omitted when absent (schema-optional, marked `?`).
struct PropertyDTO: Encodable {
    let state: String
    let value: JSONScalar?
    let unit: String?
    let reason: String?
    let error: CodeMessageDTO?

    private enum CodingKeys: String, CodingKey {
        case state, value, unit, reason, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        // `value` is always present; explicit `null` when the state carries no value.
        if let value {
            try container.encode(value, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

/// The `technicalProperties` map. Keyed by property name, in a fixed declaration order; **empty**
/// (`{}`) when the inspection failed globally (no property was inspected). Encoded through dynamic
/// keys so the map's keys are the property names.
struct TechnicalPropertiesDTO: Encodable {
    /// Ordered `(propertyKey, property)` entries; empty iff the inspection failed globally.
    let entries: [(key: String, property: PropertyDTO)]

    private struct DynamicKey: CodingKey {
        let stringValue: String
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue _: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for entry in entries {
            try container.encode(entry.property, forKey: DynamicKey(entry.key))
        }
    }
}

/// A warning object: `{ code, field, kind, message }`. `field` is schema-nullable (`null` when the
/// warning is general), so it is encoded as explicit `null` rather than omitted.
struct WarningDTO: Encodable {
    let code: String
    let field: String?
    let kind: String
    let message: String

    private enum CodingKeys: String, CodingKey {
        case code, field, kind, message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try encodeExplicit(field, forKey: .field, into: &container)
        try container.encode(kind, forKey: .kind)
        try container.encode(message, forKey: .message)
    }
}

/// `inspectionStatus`: `{ state, message?, error? }`. `message` is present for `partial`/`failed`
/// and omitted for `completed`; `error` is present **only** for a global `failed`.
struct InspectionStatusDTO: Encodable {
    let state: String
    let message: String?
    let error: CodeMessageDTO?

    private enum CodingKeys: String, CodingKey {
        case state, message, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

/// The top-level envelope. Every field from the original v1 contract is always present;
/// `measurements` is the one **additive** exception — `nil` when no DSP measurement exists, in which
/// case the key is **omitted entirely** (Swift's synthesized `Encodable` already does this for an
/// `Optional`, unlike the explicit-`null` fields above, which are part of the original required
/// contract). A report exported with `measurements == nil` is therefore byte-identical to the
/// pre-group-6 output — the strongest form the "additive, no version bump" rule can take.
/// `CodingKeys` pins every wire name so an internal property rename can never silently change the
/// contract.
struct ReportEnvelopeDTO: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let generator: GeneratorDTO
    let inspectedFile: InspectedFileDTO
    let technicalProperties: TechnicalPropertiesDTO
    let warnings: [WarningDTO]
    let inspectionStatus: InspectionStatusDTO
    let measurements: MeasurementsDTO?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, generator, inspectedFile, technicalProperties, warnings
        case inspectionStatus, measurements
    }
}

// MARK: - `measurements` (additive, still v1) — DSP-derived, never metadata

/// The wire form of one channel's own peak/RMS/DC-offset/clipped-count. `sampleCount` travels with it
/// so a consumer can tell "not computable" (`sampleCount == 0`, the three optionals `null`) from a
/// genuinely measured, computed zero — the same distinction `SignalLevelMetrics.Channel` itself
/// preserves, carried faithfully rather than collapsed into a single missing-value convention.
///
/// `peakSample`/`rms`/`dcOffset` are the domain's own **linear** amplitude, not dBFS: the wire
/// contract exports what was measured, and a decibel conversion is a presentation concern (already
/// applied only in `FeatureAnalysis`, never here). `clippedSampleCount` has no "not computable" state
/// — counting is defined even over zero samples — so it is a plain, always-present integer.
struct SignalLevelChannelDTO: Encodable {
    let sampleCount: Int
    let peakSample: Double?
    let rms: Double?
    let dcOffset: Double?
    let clippedSampleCount: Int

    private enum CodingKeys: String, CodingKey {
        case sampleCount, peakSample, rms, dcOffset, clippedSampleCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampleCount, forKey: .sampleCount)
        try encodeExplicit(peakSample, forKey: .peakSample, into: &container)
        try encodeExplicit(rms, forKey: .rms, into: &container)
        try encodeExplicit(dcOffset, forKey: .dcOffset, into: &container)
        try container.encode(clippedSampleCount, forKey: .clippedSampleCount)
    }
}

/// The whole-file combination of every channel's own figures — `SignalLevelMetrics`'s own
/// `overall…` values, computed by a fixed formula from the per-channel data, never a second
/// measurement. Carries no `sampleCount` of its own: "not computable" here means every channel was.
struct SignalLevelOverallDTO: Encodable {
    let peakSample: Double?
    let rms: Double?
    let dcOffset: Double?
    let clippedSampleCount: Int

    private enum CodingKeys: String, CodingKey {
        case peakSample, rms, dcOffset, clippedSampleCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeExplicit(peakSample, forKey: .peakSample, into: &container)
        try encodeExplicit(rms, forKey: .rms, into: &container)
        try encodeExplicit(dcOffset, forKey: .dcOffset, into: &container)
        try container.encode(clippedSampleCount, forKey: .clippedSampleCount)
    }
}

/// `measurements.signalLevels`: the overall figures plus one entry per channel, in the stream's own
/// channel order — mirroring `SignalLevelMetrics`'s own shape exactly, with no field added or dropped.
struct SignalLevelsDTO: Encodable {
    let overall: SignalLevelOverallDTO
    let channels: [SignalLevelChannelDTO]

    enum CodingKeys: String, CodingKey {
        case overall, channels
    }
}

/// The wire form of one channel's own true peak. `sampleCount` travels with it for the same reason it
/// does under `signalLevels`: it is what lets a consumer tell **"not computable"** (`sampleCount == 0`,
/// `truePeak` `null`) from a genuinely measured, computed zero. The domain enforces that rule in both
/// directions, and this carries it faithfully rather than collapsing it into one missing-value
/// convention.
///
/// `truePeak` is the domain's own **linear** amplitude, never dBTP: the wire exports what was measured
/// in the unit it was measured in, and the decibel conversion belongs to presentation
/// (`FeatureAnalysis`, which this layer does not import). Values above `1.0` are exported exactly as
/// measured — a reconstruction that exceeds full scale is the fact this measurement exists to reveal.
struct TruePeakChannelDTO: Encodable {
    let sampleCount: Int
    let truePeak: Double?

    private enum CodingKeys: String, CodingKey {
        case sampleCount, truePeak
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampleCount, forKey: .sampleCount)
        try encodeExplicit(truePeak, forKey: .truePeak, into: &container)
    }
}

/// How the measurement was produced: the oversampling factor and the filter's stable identifier
/// (ADR-0006's "factor and filter recorded with the result", ADR-0019's decision that they live inside
/// the measurement).
///
/// **It is an identity, not a configuration.** No taps, no window, no cutoff and no coefficients: a
/// consumer is told *which* methodology ran, not how to re-run one, because a wire object carrying the
/// design would be a DSP configuration wearing a result's name. Both fields are always present — a
/// measurement that exists was produced by some method.
struct TruePeakMethodDTO: Encodable {
    let oversamplingFactor: Int
    let filter: String

    enum CodingKeys: String, CodingKey {
        case oversamplingFactor, filter
    }
}

/// `measurements.truePeak`: the whole-file value, one entry per channel in the stream's own order, and
/// the method that produced them.
///
/// `overall` is a **number or an explicit `null`**, not an object — unlike `signalLevels.overall`,
/// which groups four figures. There is one number here, and wrapping it would invent a shape the
/// domain does not have. `null` means no channel carried a sample; it is never a fabricated `0`, which
/// is what a genuinely silent file reports instead.
struct TruePeakDTO: Encodable {
    let overall: Double?
    let channels: [TruePeakChannelDTO]
    let method: TruePeakMethodDTO

    private enum CodingKeys: String, CodingKey {
        case overall, channels, method
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeExplicit(overall, forKey: .overall, into: &container)
        try container.encode(channels, forKey: .channels)
        try container.encode(method, forKey: .method)
    }
}

/// How an integrated loudness was produced: which algorithm, and where the K-weighting filter's
/// coefficients came from (ADR-0006's "the constants are recorded with the result", ADR-0022 §3).
///
/// **Two identities, and neither is a conformance level.** They record *which* methodology ran, which
/// is a fact; whether that amounts to conformance is a judgement no document is in a position to make.
/// There is deliberately no `compliant`, `conformant`, `certified` or "EBU Mode" field, and no target
/// level: a target is a delivery requirement someone imposes on a file, never a property the file has.
///
/// `weighting` is the one field that varies per file while everything else stays fixed — the published
/// tables are defined at 48 kHz alone, and every other rate uses coefficients derived to reproduce that
/// response. Both fields are always present; a measurement that exists was produced by some method, and
/// both are read from the measurement's own record rather than inferred from a sample rate.
struct LoudnessMethodDTO: Encodable {
    let algorithm: String
    let weighting: String

    enum CodingKeys: String, CodingKey {
        case algorithm, weighting
    }
}

/// `measurements.integratedLoudness`: the programme's gated loudness and the method that produced it.
///
/// **The key names the quantity, not the family.** It is not `loudness`, because integrated loudness is
/// one of four quantities that word covers — momentary, short-term and loudness range are different
/// measurements, each needing its own stated reduction before it would mean anything in a static
/// report. Each would arrive as its own sibling here, carrying its own `method`, exactly as this one
/// does. A `loudness` object holding a single `method` would imply that method covered them all — the
/// same reason `truePeak.method` is not hoisted to `measurements` level.
///
/// **`value` is LUFS, and this is deliberately not the rule true peak follows.** That measurement
/// exports linear amplitude because dBTP is a *presentation* of a linear peak; here the logarithmic
/// quantity **is** the normative one (ADR-0022 §5), so exporting energy would invent a unit the standard
/// does not use. It is the unrounded `Double` the accumulator produced: the screen's one decimal is a
/// display precision, never the datum. There is no unit string — this contract states the unit, the
/// document does not.
///
/// It is a **number, never `null`**: absence is the whole key being omitted. There is no per-channel
/// array, because the channels are combined before this quantity exists.
struct IntegratedLoudnessDTO: Encodable {
    let value: Double
    let method: LoudnessMethodDTO

    enum CodingKeys: String, CodingKey {
        case value, method
    }
}

/// One reading: the centre of the highest bin that met the criterion, and the width of a bin.
///
/// **Both are hertz, both are the domain's own unrounded `Double`.** The screen rounds to a step no
/// finer than the resolution — `16.1 kHz` for the value below — because a displayed digit must
/// correspond to a distinction the analysis can make. That is a display rule, and the datum is what
/// travels here: `16101.5625`, not `16100`, and never a kilohertz string.
///
/// **`resolution` is a bin width, not an uncertainty.** It is a separate field for the same reason the
/// surface gives it a separate row: `frequency ± resolution` would claim the true value lies in an
/// interval, which this measurement does not claim, and the reading is biased one way — upward, by the
/// analysis window's leakage — so a symmetric interval would be wrong in shape as well as in kind.
/// There is no `±` on the wire because there is no interval to express.
struct ProgrammeBandwidthReadingDTO: Encodable {
    let frequency: Double
    let resolution: Double

    enum CodingKeys: String, CodingKey {
        case frequency, resolution
    }
}

/// How a programme bandwidth was produced (ADR-0006's "the constants are recorded with the result",
/// ADR-0023).
///
/// **One versioned identifier plus the transform's own geometry, and nothing reconstructed.** The
/// identifier stands for the whole rule set — the −50 dB intra-window prominence threshold, the 10 %
/// persistence criterion and the 60 dB programme budget — which is why those constants are not
/// duplicated here as fields: they are not independently variable, and emitting them as data would
/// invite a consumer to believe some other combination was possible. `windowFrames`, `hopFrames` and
/// `sampleRate` are part of the identity rather than of the geometry alone: the persistence criterion
/// counts windows, so what a window *is* changes what the number means, and the window is fixed in
/// time rather than in samples.
///
/// Every field is read from the measurement's **own** recorded method. Nothing here branches on a
/// sample rate to decide what to name — a document that inferred the method could describe one that
/// never ran.
struct ProgrammeBandwidthMethodDTO: Encodable {
    let identifier: String
    let windowFrames: Int
    let hopFrames: Int
    let sampleRate: Double

    enum CodingKeys: String, CodingKey {
        case identifier, windowFrames, hopFrames, sampleRate
    }
}

/// `measurements.programmeBandwidth`: how far up the programme reaches persistently, per channel and
/// overall, with the method that produced it.
///
/// **The key names the measurement, not an inference.** It is not `cutoff`, `frequencyLimit` or
/// `effectiveSampleRate`: the first two assert a filter nobody observed, and the third asserts the file
/// should have been stored differently. It is not `significantBandwidth` either — that is the domain
/// type's name, and the product's name is the one a document should carry.
///
/// **Nothing here is a verdict.** There is no comparison against the declared sample rate, no
/// confidence, no flag, no codec, and nothing describing what the value might imply about how the file
/// was made. ADR-0023 §1 forbids that reading and this contract does not provide the fields to express
/// it.
///
/// `channels` is one entry per channel **in the stream's own order, and `null` where that channel
/// carried nothing meeting the criterion** — the position is the channel index, so an entry cannot be
/// dropped without renumbering the rest. No layout is named anywhere: the pipeline reads channel counts
/// and never labels. `overall` is the highest of the per-channel readings, a summary of the facts
/// beside it rather than a separate measurement, which is why it repeats a reading rather than
/// combining them.
struct ProgrammeBandwidthDTO: Encodable {
    let overall: ProgrammeBandwidthReadingDTO?
    let channels: [ProgrammeBandwidthReadingDTO?]
    let method: ProgrammeBandwidthMethodDTO

    private enum CodingKeys: String, CodingKey {
        case overall, channels, method
    }

    /// `overall` is written explicitly as `null` when there is no reading, rather than omitted, so a
    /// consumer never has to tell "no reading" from "this document predates the field". In production
    /// it is never `null`: the Feature collapses a measurement carrying no reading to no key at all,
    /// exactly as it does for an absent loudness.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeExplicit(overall, forKey: .overall, into: &container)
        try container.encode(channels, forKey: .channels)
        try container.encode(method, forKey: .method)
    }
}

/// The `measurements` object itself. A struct rather than `SignalLevelsDTO` directly at the top level,
/// so a further measurement adds a sibling key rather than replacing this one or forcing a new
/// top-level field — which is exactly what `truePeak`, and then `integratedLoudness`, did.
///
/// **Every key is optional and each is omitted when its measurement does not exist**, so all eight
/// combinations are representable and none is faked: any one alone (signal levels alone stays
/// byte-identical to before true peak existed), any pair, all three, or — when none exists — no
/// `measurements` object at all. There is deliberately **no aggregate**: nothing here says "the
/// measurements succeeded", because nothing downstream should be able to ask a question about them
/// together.
struct MeasurementsDTO: Encodable {
    let signalLevels: SignalLevelsDTO?
    let truePeak: TruePeakDTO?
    let integratedLoudness: IntegratedLoudnessDTO?
    let programmeBandwidth: ProgrammeBandwidthDTO?

    enum CodingKeys: String, CodingKey {
        case signalLevels, truePeak, integratedLoudness, programmeBandwidth
    }
}

/// Encodes an optional as an **explicit `null`** when it is `nil` (instead of omitting the key), for
/// the schema's nullable fields. `Date` values are formatted by the encoder's date strategy.
private func encodeExplicit<Key, Value: Encodable>(
    _ value: Value?,
    forKey key: Key,
    into container: inout KeyedEncodingContainer<Key>
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}
