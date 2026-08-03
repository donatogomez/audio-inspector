import Foundation

import AudioInspectorApp
import AudioInspectorDomain

// Shared, deterministic helpers for the JSON v1 export tests. No files, no real clock, no real
// bundle: a fixed generator identity and a fixed export instant are injected, and reports are built
// entirely in memory. Only the exporter's **public** API is used (no `@testable`) — the DTOs, mapper,
// and encoder stay internal and are verified through the decoded JSON.
//
// The encoded bytes are inspected **exclusively via `Codable`**: they are decoded with `JSONDecoder`
// into `JSONValue`, a closed, typed JSON tree — no untyped-object serialization API, no heterogeneous
// dictionaries, no `Any` casts. `JSONValue` distinguishes an absent key, a key present with `null`,
// and a real scalar (string / int / double) structurally, without depending on textual key order.

// MARK: - JSONValue — a closed, typed, `Decodable` JSON tree

/// A complete, closed model of a JSON value, decoded with `JSONDecoder` only. `Equatable` gives
/// order-independent structural comparison (dictionaries compare regardless of key order).
enum JSONValue: Decodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    private struct AnyKey: CodingKey {
        let stringValue: String
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue _: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var object: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
        } else if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(array)
        } else {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() {
                self = .null
            } else if let value = try? single.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? single.decode(Int.self) {
                self = .int(value)
            } else if let value = try? single.decode(Double.self) {
                self = .double(value)
            } else {
                self = .string(try single.decode(String.self))
            }
        }
    }
}

extension JSONValue {
    /// Child by key — `nil` when this is not an object or the key is **absent**. A key present with a
    /// JSON `null` returns `.some(.null)`, so absence and explicit-null stay distinguishable.
    subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    /// The object's key set, or `nil` when this is not an object.
    var keys: Set<String>? {
        guard case let .object(object) = self else { return nil }
        return Set(object.keys)
    }

    var array: [JSONValue]? {
        guard case let .array(array) = self else { return nil }
        return array
    }

    var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var int: Int? {
        guard case let .int(value) = self else { return nil }
        return value
    }

    var double: Double? {
        switch self {
        case let .double(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }

    var isNull: Bool { self == .null }

    var isNumber: Bool {
        switch self {
        case .int, .double: true
        default: false
        }
    }

    var isString: Bool {
        guard case .string = self else { return false }
        return true
    }
}

// MARK: - Fixtures & builders

/// A fixed generator identity — decouples the tests from the real app bundle.
let fixedGenerator = ReportGenerator(name: "Audio Inspector", version: "0.1.0")

/// A fixed export instant used unless a test injects its own clock.
let fixedNow = date("2026-08-03T12:00:00Z")

/// Parses an ISO-8601 UTC string into a `Date` (test input only).
func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso)!
}

/// A safe in-memory file reference mirroring the canonical partial example's descriptive metadata.
func makeReference(modifiedAt: Date? = date("2026-06-12T09:03:00Z")) -> AudioFileReference {
    AudioFileReference(
        displayName: "interview-side-a.m4a",
        fileExtension: "m4a",
        sizeBytes: 8_421_376,
        modifiedAt: modifiedAt,
        source: .userSelectedLocalFile(displayName: "interview-side-a.m4a", locationDisclosure: .omitted)
    )
}

/// Every technical property cleanly `available` — a valid `completed` shape.
func allAvailableProperties() -> TechnicalProperties {
    TechnicalProperties(
        container: .available("wav"),
        duration: .available(10.5),
        sampleRate: .available(44_100),
        channelCount: .available(2),
        bitDepth: .available(16),
        codec: .available("pcm"),
        declaredBitrate: .available(1_411_200),
        estimatedBitrate: .available(1_411_200)
    )
}

/// Builds an in-memory report from parts; defaults cover the common `completed`/`partial` shapes.
func report(
    properties: TechnicalProperties = allAvailableProperties(),
    warnings: [InspectionWarning] = [],
    status: InspectionStatus
) -> InspectionReport {
    InspectionReport(file: makeReference(), properties: properties, warnings: warnings, status: status)
}

// MARK: - Export & decode (Codable-only)

/// Exports a report to raw JSON bytes with the injected clock/generator.
func exportData(
    _ report: InspectionReport,
    now: Date = fixedNow,
    generator: ReportGenerator = fixedGenerator
) throws -> Data {
    try JSONReportExporter(generator: generator, now: { now }).export(report)
}

/// Exports and decodes into a typed `JSONValue` tree (via `JSONDecoder`) for structural assertions.
func exportValue(
    _ report: InspectionReport,
    now: Date = fixedNow,
    generator: ReportGenerator = fixedGenerator
) throws -> JSONValue {
    let data = try exportData(report, now: now, generator: generator)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

/// Decodes a JSON string literal (canonical-example fixtures) into a `JSONValue` tree.
func decodeValue(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

/// Every object key appearing anywhere in a decoded JSON tree (for structural privacy checks).
func allKeys(_ value: JSONValue) -> Set<String> {
    switch value {
    case let .object(object):
        return object.reduce(into: Set(object.keys)) { keys, entry in
            keys.formUnion(allKeys(entry.value))
        }
    case let .array(array):
        return array.reduce(into: Set<String>()) { keys, element in
            keys.formUnion(allKeys(element))
        }
    default:
        return []
    }
}
