import Darwin
import Foundation

import AudioInspectorDomain

// The measuring instruments group 9 uses, and **the limits of each one**, in one place.
//
// Two are needed rather than one because neither is sufficient alone, and their blind spots do not
// overlap:
//
// - `RetainedGraph` walks the object graph a value really keeps alive and counts the payload buffers
//   it reaches, deduplicated by their storage address. It is **exact** and deterministic, and it can
//   name what it found. It cannot see inside a closure's captures or an opaque runtime box, so a
//   buffer captured by an escaping closure would be invisible to it.
// - `ProcessFootprint` reads the process's own physical footprint from the kernel. It sees
//   *everything*, closures included, and it is the only one of the two that can observe memory that
//   was allocated and then released. It is **process-wide and noisy**, so nothing may be attributed
//   to a value from a single reading: only a differential between two runs of the same code, taken
//   several times, says anything at all.
//
// A claim made by only one of them is reported as what that instrument can support, never more.

// MARK: - The process's own footprint

/// The process's physical footprint, as the kernel reports it — the same number Xcode's memory gauge
/// shows.
///
/// `phys_footprint` rather than `resident_size`: resident size counts pages shared with other
/// processes and lags behind `madvise`, while the footprint is the accounting the system itself uses
/// for a process's memory. Large allocations — a 2 MiB `[Float]` is far above the allocator's large
/// threshold — are mapped and unmapped directly, so freeing one is visible here.
enum ProcessFootprint {
    /// The current footprint in bytes, or `nil` when the kernel declines to answer.
    static func current() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint)
    }
}

/// One differential measurement: the same scenario run twice, once with the property under test and
/// once without, repeated, so a median can be taken and the spread reported rather than hidden.
struct FootprintSample {
    /// Every observed delta, in bytes, in the order it was taken.
    let deltas: [Int]

    var median: Int {
        let sorted = deltas.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    var minimum: Int { deltas.min() ?? 0 }
    var maximum: Int { deltas.max() ?? 0 }

    /// The reading as it goes into the record: the median, and the spread that qualifies it.
    var description: String {
        "median \(MiB.text(median))  range \(MiB.text(minimum))…\(MiB.text(maximum))  n=\(deltas.count)"
    }
}

/// Bytes as MiB, to three decimals, so a record states what was read rather than a rounded story.
enum MiB {
    static func text(_ bytes: Int) -> String {
        String(format: "%.3f MiB (%d B)", Double(bytes) / 1_048_576, bytes)
    }
}

/// Measures the footprint of a **ramp**: `batches` batches of `count` scenarios, **none of which is
/// ever released**, with a reading taken across each batch.
///
/// ## Why nothing may be released
///
/// Measured by building one scenario, reading, and releasing it, this instrument reads **zero** — for
/// both states, and sometimes below zero. That is the allocator, not the flow: a 2 MiB buffer is a
/// large allocation, the allocator keeps freed large regions in a cache, and every run after the
/// first is served from pages already counted in the process's footprint. A before/after pair around
/// a scenario that releases its predecessor therefore measures **reuse** and calls it retention.
///
/// A ramp cannot be served that way. Every batch is held for the whole measurement, so each one must
/// be given pages the process did not have, and the reading is a slope rather than a difference
/// against a high-water mark. A warm-up batch is built **and kept** for the same reason: releasing it
/// would prime exactly the cache this is written to defeat.
///
/// The value is process-wide. **Nothing here attributes it to anything on its own** — only the
/// difference between two ramps of the same shape, differing in one property, says anything, and the
/// spread is reported beside the median so the reading is never quoted without its noise.
@MainActor
func measureRetainedRamp<Value>(
    batches: Int = 5,
    count: Int = 8,
    _ scenario: () async -> Value
) async -> FootprintSample {
    func batch() async -> [Value] {
        var values: [Value] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count { values.append(await scenario()) }
        return values
    }

    var held: [[Value]] = []
    held.append(await batch()) // warm-up, kept rather than released

    var deltas: [Int] = []
    for _ in 0 ..< batches {
        let before = ProcessFootprint.current() ?? 0
        held.append(await batch())
        let after = ProcessFootprint.current() ?? 0
        deltas.append(after - before)
    }
    return withExtendedLifetime(held) { FootprintSample(deltas: deltas) }
}

// MARK: - What a value really keeps alive

/// A walk of everything a value keeps alive, and an account of the payload buffers it reaches.
///
/// ## What it counts, and why deduplicated
///
/// The three arrays that carry this feature's weight — a spectral model's `[Float]`, an envelope's
/// `[WaveformBucket]` and a chunk's `[[Float]]` — are counted by their **storage address**, so a
/// buffer reachable by two paths is counted **once**. That is the whole point: a pair holds the first
/// file's model beside the presentation that already holds it, and whether that costs one buffer or
/// two is the question, not an assumption to be waved at with the word *copy-on-write*.
///
/// ## What it cannot see
///
/// A closure's captures, and any value the runtime keeps in an opaque box (a `Task`'s state, for
/// one). `Mirror` reports no children for either. Anything claimed on this instrument alone is
/// therefore a claim about the **stored** graph, and the footprint measurement is what covers the
/// rest.
struct RetainedGraph {
    /// Distinct payload buffers reached, by storage address.
    private(set) var uniqueBuffers: [UInt: Int] = [:]
    /// How many times each type was reached, by name.
    private(set) var occurrences: [String: Int] = [:]

    /// The bytes of payload reachable, counting each distinct buffer once.
    var payloadBytes: Int { uniqueBuffers.values.reduce(0, +) }

    /// How many times a type was reached — 2 for a value held in two places, whatever its storage.
    func count(of typeName: String) -> Int { occurrences[typeName] ?? 0 }

    func reached(_ typeName: String) -> Bool { count(of: typeName) > 0 }

    /// Walks `root`, following stored properties, enum payloads, optionals and collections.
    static func walking(_ root: Any) -> RetainedGraph {
        var graph = RetainedGraph()
        var visitedObjects = Set<ObjectIdentifier>()
        graph.visit(root, visited: &visitedObjects, depth: 0)
        return graph
    }

    private mutating func record(buffer address: UnsafeRawPointer?, bytes: Int) {
        guard let address, bytes > 0 else { return }
        uniqueBuffers[UInt(bitPattern: address)] = bytes
    }

    private mutating func visit(_ value: Any, visited: inout Set<ObjectIdentifier>, depth: Int) {
        // A depth this large means something is recursing that should not be; stopping is better than
        // a hang, and no shape in this codebase comes close to it.
        guard depth < 64 else { return }

        let name = String(describing: type(of: value))
        occurrences[name, default: 0] += 1

        // A class instance reached twice is walked once: its storage is shared by definition.
        if type(of: value) is AnyClass {
            let identity = ObjectIdentifier(value as AnyObject)
            guard visited.insert(identity).inserted else { return }
        }

        // The payload buffers, counted by address and **not** recursed into: a 524 288-element
        // `Mirror` walk would be a different kind of instrument.
        if let floats = value as? [Float] {
            floats.withUnsafeBufferPointer {
                record(buffer: $0.baseAddress.map(UnsafeRawPointer.init), bytes: $0.count * MemoryLayout<Float>.stride)
            }
            return
        }
        if let buckets = value as? [WaveformBucket] {
            buckets.withUnsafeBufferPointer {
                record(buffer: $0.baseAddress.map(UnsafeRawPointer.init), bytes: $0.count * MemoryLayout<WaveformBucket>.stride)
            }
            return
        }
        if let bytes = value as? [UInt8] {
            bytes.withUnsafeBufferPointer {
                record(buffer: $0.baseAddress.map(UnsafeRawPointer.init), bytes: $0.count)
            }
            return
        }
        if let planes = value as? [[Float]] {
            for plane in planes { visit(plane, visited: &visited, depth: depth + 1) }
            return
        }
        // Leaves with no interesting structure. `String` in particular would otherwise be walked
        // character by character.
        if value is String || value is Date || value is Data { return }

        for child in Mirror(reflecting: value).children {
            visit(child.value, visited: &visited, depth: depth + 1)
        }
    }
}

// MARK: - The record's own header

/// The machine and configuration every measurement in group 9 was taken on, printed beside the
/// numbers so a reading is never quoted without the conditions that produced it.
enum MeasurementConditions {
    static var description: String {
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        return """
        machine: \(sysctlString("machdep.cpu.brand_string")) · \(sysctlString("hw.machine")) · \
        \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GiB
        os: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        configuration: \(configuration)
        """
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}
