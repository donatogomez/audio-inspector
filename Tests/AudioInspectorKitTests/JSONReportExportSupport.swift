import Foundation

import AudioInspectorApp
import AudioInspectorDomain

// Shared, deterministic helpers for the JSON v1 export tests. No files, no real clock, no real
// bundle: a fixed generator identity and a fixed export instant are injected, and reports are built
// entirely in memory. Only the exporter's **public** API is used (no `@testable`) — the DTOs, mapper,
// and encoder stay internal and are verified through the decoded JSON, not by reaching into them.

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

/// Exports a report to raw JSON bytes with the injected clock/generator.
func exportData(
    _ report: InspectionReport,
    now: Date = fixedNow,
    generator: ReportGenerator = fixedGenerator
) throws -> Data {
    try JSONReportExporter(generator: generator, now: { now }).export(report)
}

/// Exports and decodes to a `[String: Any]` tree so assertions inspect the real decoded structure.
func exportObject(
    _ report: InspectionReport,
    now: Date = fixedNow,
    generator: ReportGenerator = fixedGenerator
) throws -> [String: Any] {
    let data = try exportData(report, now: now, generator: generator)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

/// Every object key appearing anywhere in a decoded JSON tree (for structural privacy checks).
func allKeys(_ value: Any) -> Set<String> {
    if let dictionary = value as? [String: Any] {
        return dictionary.reduce(into: Set(dictionary.keys)) { keys, entry in
            keys.formUnion(allKeys(entry.value))
        }
    }
    if let array = value as? [Any] {
        return array.reduce(into: Set<String>()) { keys, element in
            keys.formUnion(allKeys(element))
        }
    }
    return []
}

/// Structural deep-equality over decoded JSON (`[String: Any]`, `[Any]`, `String`, number, null).
func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    if lhs is NSNull, rhs is NSNull { return true }
    if let l = lhs as? [String: Any], let r = rhs as? [String: Any] {
        guard Set(l.keys) == Set(r.keys) else { return false }
        return l.allSatisfy { key, value in r[key].map { jsonEqual(value, $0) } ?? false }
    }
    if let l = lhs as? [Any], let r = rhs as? [Any] {
        guard l.count == r.count else { return false }
        return zip(l, r).allSatisfy { jsonEqual($0, $1) }
    }
    if let l = lhs as? String, let r = rhs as? String { return l == r }
    if let l = lhs as? NSNumber, let r = rhs as? NSNumber { return l == r }
    return false
}

/// Parses a JSON string literal into a `[String: Any]` (canonical-example fixtures).
func decodeObject(_ json: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}
