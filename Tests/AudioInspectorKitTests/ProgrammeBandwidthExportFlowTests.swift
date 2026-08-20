import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

// **A real file all the way to the document.** File, real decoder, shared PCM read, the composition's
// outcome, and the exported JSON — with nothing constructed by hand at any step. The measurement that
// reaches the wire is the one production produced, which is the only way to show the mapper copies a
// fact rather than rebuilding one.
@Suite("Export — programme bandwidth from a real file")
struct ProgrammeBandwidthExportFlowTests {

    private let subject = report(status: .completed)

    /// The production measurement for one written fixture, or `nil` where the file has none.
    private func measured(_ spec: AudioFixtureSpec, in directory: URL) async throws -> SignificantBandwidth? {
        switch try await measureThroughProduction(spec, in: directory) {
        case let .available(model): model
        case .unavailable: nil
        case let .failed(message): { Issue.record("the production path failed: \(message)"); return nil }()
        case .cancelled: { Issue.record("the production path reported cancellation"); return nil }()
        }
    }

    /// That measurement, exported and decoded — the document a consumer receives for that file.
    private func exported(_ spec: AudioFixtureSpec, in directory: URL) async throws -> JSONValue {
        let model = try await measured(spec, in: directory)
        return try exportValue(subject, programmeBandwidth: model)
    }

    // MARK: 48 kHz, end to end

    /// **What production measured is what the document carries**, field for field, at full precision —
    /// compared against the measurement itself rather than against a written-down number, so the
    /// assertion cannot drift from the file.
    @Test("a 16 kHz programme reaches the document with the numbers production produced")
    func programmeReachesTheDocument() async throws {
        try await withTemporaryDirectory { directory in
            let spec = productionSpec("export-16k", productionProgramme(to: 16_000), frames: 48_000)
            let model = try #require(try await measured(spec, in: directory), "production measured nothing")
            let overall = try #require(model.overall)
            let json = try exportValue(subject, programmeBandwidth: model)

            let object = try #require(json["measurements"]?["programmeBandwidth"], "the key is missing")
            #expect(object["overall"]?["frequency"]?.double == overall.frequency)
            #expect(object["overall"]?["resolution"]?.double == overall.resolution)
            #expect(object["method"]?["identifier"]?.string == model.method.identifier)
            #expect(object["method"]?["windowFrames"]?.int == model.method.windowFrames)
            #expect(object["method"]?["hopFrames"]?.int == model.method.hopFrames)
            #expect(object["method"]?["sampleRate"]?.double == model.method.sampleRate)
            #expect(json["schemaVersion"]?.int == 1)

            // The wire is the datum, and the surface's rounding never reaches it: this file reads
            // 16 101.5625 Hz and is shown as 16.1 kHz.
            #expect(overall.frequency != overall.frequency.rounded(.toNearestOrEven) || overall.frequency == 16_101.5625)
            #expect(object["overall"]?["frequency"]?.double != 16_100)
        }
    }

    // MARK: Multi-rate

    /// The method on the wire is the one that **ran**, per rate, and the mapper never derives it: the
    /// window lengths differ because the window is fixed in time, and each document says which one
    /// produced its number.
    @Test("every rate exports the method that actually ran",
          arguments: [(44_100.0, 1_920), (48_000.0, 2_048), (96_000.0, 4_096), (192_000.0, 8_192)])
    func multiRate(rate: Double, windowFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let spec = productionSpec("export-rate-\(Int(rate))", productionProgramme(to: 16_000),
                                      rate: rate, frames: AVAudioFrameCount(rate))
            let model = try #require(try await measured(spec, in: directory))
            let overall = try #require(model.overall)
            let object = try #require(
                try exportValue(subject, programmeBandwidth: model)["measurements"]?["programmeBandwidth"]
            )
            #expect(object["method"]?["sampleRate"]?.double == rate)
            #expect(object["method"]?["windowFrames"]?.int == windowFrames, "the exported window is not the one that ran")
            #expect(object["method"]?["hopFrames"]?.int == windowFrames / 4)
            #expect(object["overall"]?["frequency"]?.double == overall.frequency)
            // The resolution on the wire is the rate's own grid, carried rather than recomputed.
            #expect(object["overall"]?["resolution"]?.double == rate / Double(windowFrames))
        }
    }

    // MARK: Absence

    /// A file with no measurement carries **no key**, and the siblings beside it are untouched.
    @Test("a file production cannot measure omits the key, leaving its siblings alone",
          arguments: ["silence", "short"])
    func absenceOmitsTheKey(kind: String) async throws {
        try await withTemporaryDirectory { directory in
            let spec = kind == "silence"
                ? productionSpec("export-silence", .silence, frames: 144_000)
                : productionSpec("export-short", productionProgramme(to: 16_000), frames: 1_000)
            #expect(try await measured(spec, in: directory) == nil, "production measured something for \(kind)")

            let peakMethod = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
            let peakChannel = try #require(TruePeakMeasurement.Channel(sampleCount: 44_100, truePeak: 0.5))
            let peak = try #require(TruePeakMeasurement(channels: [peakChannel], method: peakMethod))

            let json = try exportValue(subject, truePeak: peak, programmeBandwidth: try await measured(spec, in: directory))
            let measurements = try #require(json["measurements"])
            #expect(measurements["programmeBandwidth"] == nil, "\(kind) produced a key")
            #expect(try #require(measurements.keys) == ["truePeak"], "a sibling was disturbed")
        }
    }

    // MARK: The impulse control, on the wire

    /// **The wire equivalent of the guarantee that already reaches the surface.** An isolated click
    /// inside a programme leaves the exported object byte-for-byte the same — asserted on the decoded
    /// value *and* on the bytes, because the whole point is that nothing downstream can tell the two
    /// files apart by this measurement.
    @Test("an isolated click inside a programme exports an identical measurement")
    func impulseExportsIdentically() async throws {
        try await withTemporaryDirectory { directory in
            let clean = try #require(try await measured(
                productionSpec("export-clean", productionProgramme(to: 16_000), frames: 144_000), in: directory
            ))
            let clicked = try #require(try await measured(
                productionSpec("export-clicked",
                               .sum([productionProgramme(to: 16_000), .impulse(amplitude: 0.9, frameIndex: 72_000)]),
                               frames: 144_000),
                in: directory
            ))
            let cleanJSON = try exportValue(subject, programmeBandwidth: clean)["measurements"]?["programmeBandwidth"]
            let clickedJSON = try exportValue(subject, programmeBandwidth: clicked)["measurements"]?["programmeBandwidth"]
            #expect(clickedJSON == cleanJSON, "a click changed the exported measurement")
            #expect(
                try exportData(subject, programmeBandwidth: clean)
                    == (try exportData(subject, programmeBandwidth: clicked)),
                "a click changed the exported bytes"
            )
        }
    }

    // MARK: Transport — the document copies the fact, it does not reinterpret it

    /// A lossless container and a lossy one, representative rather than the whole of group 6's matrix.
    /// The point is only that the exporter carries whatever production produced: the AAC file measures
    /// differently because its samples differ, and the document says so without naming a codec.
    @Test("a lossless and a lossy file each export their own measured fact")
    func transportIsCopiedNotReinterpreted() async throws {
        try await withTemporaryDirectory { directory in
            let signal = AudioFixtureSignal.tones(highest: 20_000, spacing: 500, lowest: 500, perComponentAmplitude: 0.01)
            let lossless = try #require(try await measured(
                productionSpec("export-lossless", signal, format: .wav, rate: 44_100, frames: 88_200), in: directory
            ))
            let lossy = try #require(try await measured(
                productionSpec("export-aac", signal, format: .aac, rate: 44_100, frames: 88_200), in: directory
            ))
            for model in [lossless, lossy] {
                let object = try #require(
                    try exportValue(subject, programmeBandwidth: model)["measurements"]?["programmeBandwidth"]
                )
                #expect(object["overall"]?["frequency"]?.double == model.overall?.frequency)
                #expect(object["method"]?["identifier"]?.string == SignificantBandwidthMethod.v1)
            }
            // **Nothing the measurement contributes says how the file was encoded.** Scoped to its own
            // object: the envelope's `technicalProperties.codec` is a property read from the file's
            // metadata and is nobody's business here — sweeping the whole document would reject that
            // legitimate, pre-existing field and prove nothing about this measurement.
            let object = try #require(
                try exportValue(subject, programmeBandwidth: lossy)["measurements"]?["programmeBandwidth"]
            )
            let text = String(decoding: try JSONEncoder().encode(["m": lossy.method.identifier]), as: UTF8.self)
            for named in ["aac", "mp3", "lossy", "codec"] {
                #expect(!allKeys(object).contains(where: { $0.lowercased().contains(named) }), "\(named) is a key")
                #expect(!text.lowercased().contains(named), "\(named) reached the method identity")
            }
        }
    }
}
