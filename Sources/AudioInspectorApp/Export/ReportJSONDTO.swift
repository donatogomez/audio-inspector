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
/// `inspectionStatus.error`. Both fields are always present, so the synthesized encoding is correct.
struct CodeMessageDTO: Encodable {
    let code: String
    let message: String
}

/// The `generator` envelope object. Both fields always present.
struct GeneratorDTO: Encodable {
    let name: String
    let version: String
}

/// The safe `source` object. All three fields always present; carries no path/URL/bookmark by shape.
struct SourceDTO: Encodable {
    let kind: String
    let displayName: String
    let locationDisclosure: String
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

/// The top-level envelope. Every field is always present, so the synthesized encoding is correct.
struct ReportEnvelopeDTO: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let generator: GeneratorDTO
    let inspectedFile: InspectedFileDTO
    let technicalProperties: TechnicalPropertiesDTO
    let warnings: [WarningDTO]
    let inspectionStatus: InspectionStatusDTO
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
