import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import FeatureImport

// **Task 6.6, against production.** A lossy encoder's band limit is a fact about the samples, and it
// travels with the samples rather than with the container.
//
// What this is *not*: detection. Nothing here reads a header, names a codec, or claims a file "came
// from" anything — ADR-0023 §1 and `CLAUDE.md` both forbid asserting transcoding from a frequency
// cut-off, and the assertions below are only that two files measure the same, or that one measures
// lower than another.
//
// AAC is encoded by macOS itself, so that row is CI coverage. MP3 has no macOS encoder, so its row
// needs FFmpeg and is **local evidence only** — a skipped run is not coverage, and task 6.6 stays open
// on a machine that skips it.

private func lossySource() -> AudioFixtureSignal {
    .tones(highest: 20_000, spacing: 500, lowest: 500, perComponentAmplitude: 0.01)
}

private let lossyRate = 44_100.0
private let lossyFrames = AVAudioFrameCount(88_200)

@Suite("App — programme bandwidth through AAC, on the production path")
struct ProgrammeBandwidthProductionAACTests {

    /// A lossy transport is allowed to move the reading — it genuinely changes the samples — but it
    /// must not destroy the fact, and its artefacts must not become the answer.
    @Test("AAC moves the published reading by a few bins and does not send it to the top of the band")
    func aacPreservesTheFact() async throws {
        try await withTemporaryDirectory { directory in
            let source = try await reading(.wavFloat, name: "aac-prod-source", in: directory)
            let encoded = try await reading(.aac, name: "aac-prod-encoded", in: directory)
            #expect(encoded.resolution == source.resolution)
            let binsApart = abs(encoded.frequency - source.frequency) / source.resolution
            #expect(
                binsApart <= 8,
                "AAC published \(encoded.frequency) Hz where the source published \(source.frequency) Hz"
            )
            #expect(
                encoded.frequency < lossyRate / 2 - 1_000,
                "AAC published \(encoded.frequency) Hz, at the top of the band: its artefacts became the answer"
            )
        }
    }

    private func reading(
        _ format: AudioFixtureFormat, name: String, in directory: URL
    ) async throws -> SignificantBandwidth.Channel {
        let outcome = try await measureThroughProduction(
            productionSpec(name, lossySource(), format: format, rate: lossyRate, channels: 1, frames: lossyFrames),
            in: directory
        )
        let model = try productionModel(outcome, Comment(rawValue: name))
        return try #require(model.overall, "\(name) published no reading")
    }
}

@Suite(
    "App — programme bandwidth through MP3 and rewrap, on the production path (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.hasMP3Encoder,
        """
        FFmpeg with libmp3lame is not installed on this machine, so no MP3 fixture can be produced. \
        This suite is SKIPPED, and a SKIPPED RUN IS NOT MP3 COVERAGE: task 6.6's rewrap row stays open \
        and nothing may cite this run as evidence that the production path preserves it.
        """
    )
)
struct ProgrammeBandwidthProductionMP3Tests {

    /// The source is ours, written by the same deterministic writer every other row uses, so what
    /// FFmpeg encodes is a pure function of parameters in this repository. FFmpeg produces fixtures and
    /// never establishes a fact: every number below comes from the production path.
    private func source(in directory: URL) throws -> URL {
        try writeAudioFixture(
            productionSpec("mp3-prod-source", lossySource(), format: .wavFloat,
                           rate: lossyRate, channels: 1, frames: lossyFrames),
            in: directory
        )
    }

    private func encode(_ source: URL, bitrate: String, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("bandwidth-prod-\(bitrate).mp3")
        try FFmpegTool.run([
            "-hide_banner", "-nostdin", "-y", "-i", source.path,
            "-codec:a", "libmp3lame", "-b:a", bitrate, url.path,
        ])
        return url
    }

    private func reading(of url: URL, _ what: String) async throws -> SignificantBandwidth.Channel {
        let model = try productionModel(await measureThroughProduction(url), Comment(rawValue: what))
        return try #require(model.overall, "\(what) published no reading")
    }

    /// A low bitrate low-passes hard, and the production path sees that limit as a fact about the
    /// samples — without reading a header, and without asserting how the file was made.
    @Test("a low-bitrate MP3 publishes its own band limit")
    func lowBitrateShowsItsLimit() async throws {
        try await withTemporaryDirectory { directory in
            let source = try source(in: directory)
            let sourceReading = try await reading(of: source, "the source")
            let encoded = try await reading(of: try encode(source, bitrate: "64k", to: directory), "a 64 kbps MP3")
            #expect(
                encoded.frequency < sourceReading.frequency - 1_000,
                "a 64 kbps MP3 published \(encoded.frequency) Hz against a source of \(sourceReading.frequency) Hz"
            )
            #expect(encoded.frequency > 10_000, "a 64 kbps MP3 published \(encoded.frequency) Hz, which is not a band limit")
        }
    }

    /// A high bitrate keeps the source's own edge, so the measurement is not simply reporting "lossy".
    @Test("a high-bitrate MP3 keeps the source's edge")
    func highBitrateKeepsTheEdge() async throws {
        try await withTemporaryDirectory { directory in
            let source = try source(in: directory)
            let sourceReading = try await reading(of: source, "the source")
            let encoded = try await reading(of: try encode(source, bitrate: "320k", to: directory), "a 320 kbps MP3")
            #expect(
                abs(encoded.frequency - sourceReading.frequency) <= 8 * sourceReading.resolution,
                "a 320 kbps MP3 published \(encoded.frequency) Hz where the source published \(sourceReading.frequency) Hz"
            )
        }
    }

    /// **The rewrap row.** An MP3 decoded and written back out as PCM is a lossless container carrying
    /// lossy samples. The published measurement must be **identical**, not merely close: the two files
    /// decode to the same samples, and the measurement is a pure function of the samples.
    ///
    /// It says nothing about where the WAV came from, and nothing in the outcome names a codec.
    @Test("the published measurement survives a rewrap to PCM", arguments: ["64k", "128k", "320k"])
    func rewrapPreservesTheMeasurement(bitrate: String) async throws {
        try await withTemporaryDirectory { directory in
            let mp3 = try encode(try source(in: directory), bitrate: bitrate, to: directory)
            let rewrapped = directory.appendingPathComponent("rewrapped-prod-\(bitrate).wav")
            try FFmpegTool.run([
                "-hide_banner", "-nostdin", "-y", "-i", mp3.path, "-codec:a", "pcm_f32le", rewrapped.path,
            ])
            let fromMP3 = await measureThroughProduction(mp3)
            let fromWAV = await measureThroughProduction(rewrapped)
            _ = try productionModel(fromMP3, "the MP3")
            #expect(
                fromWAV == fromMP3,
                "the rewrapped WAV published a different measurement from the MP3 it carries"
            )
        }
    }
}
