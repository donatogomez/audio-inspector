// NativePCMDecodingSpike — entry point.
//
// GATE 1 ONLY: results infrastructure, fixture generation for WAV/AIFF/ALAC/FLAC/AAC, experiment A
// (open, formats, frame length) and experiment B (incremental read to EOF). Experiments C to K are
// NOT implemented and nothing about them may be inferred from this run.
//
// Planned experiments, so the report and the code cannot drift apart. Each maps to a section of
// docs/spikes/2026-08-05-native-pcm-decoding-validation.md with the same letter.
//
//   A — Open, processing format, frame length, per target format.            [gate 1 — implemented]
//   B — Incremental read: frames per call, short final chunk, EOF signal.    [gate 1 — implemented]
//   C — Planar versus interleaved: what the buffer actually exposes.         [gate 2]
//   D — Multichannel: channel count and per-channel access beyond stereo.    [gate 2]
//   E — Sample values: observed range, and whether conversion can exceed ±1. [gate 2]
//   F — Chunk sizes: several sizes, effect on time and allocations.          [gate 3]
//   G — Cancellation: cooperative, checked by the LOOP at chunk boundaries.  [gate 3]
//   H — Empty, truncated, corrupt and unreadable files.                      [gate 3]
//   I — Memory versus duration: approximate, comparative across durations.   [gate 3]
//   J — One instance per task (isolation).                                   [gate 3]
//   K — Media → PCM chunks → Analysis: viability and cost.                   [gate 4, alone]
//
// MP3 is a MANUAL validation with FFmpeg and is explicitly NOT CI coverage.

import AVFoundation
import Foundation

let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("native-pcm-decoding-spike-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

print("native-pcm-decoding spike — GATE 1")
print("fixtures: \(FixtureFactory.frames) frames @ \(Int(FixtureFactory.sampleRate)) Hz, \(FixtureFactory.channels) ch")
print("experiment B chunk size: \(Experiments.chunkFrames) frames")
print("")

var observations: [FormatObservation] = []

for spec in FixtureFactory.specs() {
    var observation = FormatObservation(fixture: spec.name, fileExtension: spec.fileExtension)
    let url = temporaryDirectory.appendingPathComponent("\(spec.name).\(spec.fileExtension)")

    // Generation. Recorded on its own: a write failure is never reported as a decoding failure.
    do {
        observation.framesWritten = try FixtureFactory.write(spec, to: url)
        observation.generated = true
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        observation.fileSizeBytes = (attributes?[.size] as? NSNumber)?.int64Value
    } catch {
        observation.generated = false
        observation.generationError = Describe.error(error)
    }

    // A, then B on the same instance. Attempted only when a file exists to open — a missing file
    // would measure the harness, not the decoder.
    if FileManager.default.fileExists(atPath: url.path) {
        if let file = Experiments.experimentA(url: url, into: &observation) {
            Experiments.experimentB(file: file, into: &observation)
            Experiments.experimentBControl(url: url, into: &observation)
        }
    }

    observations.append(observation)
}

for observation in observations {
    Report.detail(observation)
}

Report.summary(observations)

// ── GATE 2 ────────────────────────────────────────────────────────────────────────────────────────

print(String(repeating: "═", count: 78))
print("GATE 2 — C (layout), D (multichannel), E (values outside ±1)")
print(String(repeating: "═", count: 78))
print("")

/// C reuses the gate-1 fixtures, which are still on disk in the same temporary directory.
var layoutObservations: [LayoutObservation] = []
for spec in FixtureFactory.specs() {
    let url = temporaryDirectory.appendingPathComponent("\(spec.name).\(spec.fileExtension)")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    layoutObservations.append(Gate2Experiments.experimentC(url: url, fixture: spec.name))
}

Gate2Report.layout(layoutObservations)

Gate2Report.multichannel(Gate2Experiments.experimentD(directory: temporaryDirectory))
Gate2Report.range(Gate2Experiments.experimentE(directory: temporaryDirectory))

// ── GATE 2.5 ──────────────────────────────────────────────────────────────────────────────────────

print(String(repeating: "═", count: 78))
print("GATE 2.5 — buffer lifetime investigation (C2, C3)")
print(String(repeating: "═", count: 78))
print("")

var lifetimeObservations: [BufferLifetimeObservation] = []
for spec in FixtureFactory.specs() {
    let url = temporaryDirectory.appendingPathComponent("\(spec.name).\(spec.fileExtension)")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    lifetimeObservations.append(Gate25Experiments.experimentC2(url: url, fixture: spec.name))
}

Gate25Report.bufferLifetime(lifetimeObservations)

var chunkSizeObservations: [ChunkSizeObservation] = []
for spec in FixtureFactory.specs() {
    let url = temporaryDirectory.appendingPathComponent("\(spec.name).\(spec.fileExtension)")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    for capacity in Gate25Experiments.capacities {
        chunkSizeObservations.append(Gate25Experiments.experimentC3(url: url, fixture: spec.name, capacity: capacity))
    }
}

Gate25Report.chunkSizes(chunkSizeObservations)

// ── GATE 2.75 ─────────────────────────────────────────────────────────────────────────────────────

print(String(repeating: "═", count: 78))
print("GATE 2.75 — characterisation of post-frameLength samples (C4, C5, C6, C7)")
print(String(repeating: "═", count: 78))
print("")

let aacURL = temporaryDirectory.appendingPathComponent("AAC.m4a")
if FileManager.default.fileExists(atPath: aacURL.path) {
    print("C4 — PATTERN OF THE POST-frameLength REGION  (AAC, capacity 4096)")
    print("")
    if let lastChunk = try? Gate275Experiments.readLastChunk(url: aacURL, capacity: 4096) {
        print("    final chunk: frameLength \(lastChunk.frameLength) of capacity \(lastChunk.frameCapacity)")
        Gate275Report.comparisons(Gate275Experiments.experimentC4(buffer: lastChunk), title: "last 64 valid vs first 64 post")
    } else {
        print("    no final chunk was produced")
    }
    print("")

    print("C5 — DETERMINISM  (5 full reads, a fresh buffer every read)")
    print("")
    Gate275Report.determinism(Gate275Experiments.experimentC5(url: aacURL, label: "AAC (base fixture)"))
    print("")

    Gate275Report.capacitySensitivity(Gate275Experiments.experimentC6(url: aacURL))

    print("C6 follow-up — is each post region a prefix of the longest one?")
    print("")
    print("    cap    frames  prefix of longest")
    print("    ────── ─────── ─────────────────")
    for row in Gate275Experiments.experimentC6PrefixCheck(url: aacURL) {
        let capacity = String(row.capacity).padding(toLength: 6, withPad: " ", startingAt: 0)
        let frames = String(row.frames).padding(toLength: 7, withPad: " ", startingAt: 0)
        let verdict = row.isPrefixOfLongest.map(String.init(describing:)) ?? "— (no post region)"
        print("    \(capacity) \(frames) \(verdict)")
    }
    print("")
}

Gate275Report.contentDependence(Gate275Experiments.experimentC7(directory: temporaryDirectory))

print("Experiments F–K: NOT IMPLEMENTED at this gate. No conclusion about them may be drawn here.")
