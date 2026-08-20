import AVFoundation
import Foundation
import Testing

// The lossy rows of group 2, kept apart from the lossless matrix on the container matrix's own
// precedent: a codec is a different question. The question here is **not** "can we detect AAC" — the
// change forbids that reading, and ADR-0023 §1 forbids the finding it would become. It is:
//
//   does a lossy transport change the measured fact, and by how much?
//
// AAC is encoded by macOS itself, so that row is CI coverage. MP3 has no macOS encoder, so its row
// needs FFmpeg and is **local evidence only** — the same rule `MP3SpectrogramEvidenceTests` states,
// and for the same reason: a skipped run is not coverage.

/// A programme with components right up to 20 kHz, so a codec's own low-pass is visible rather than
/// hidden below the content's edge.
private func lossySource() -> AudioFixtureSignal {
    .tones(highest: 20_000, spacing: 500, lowest: 500, perComponentAmplitude: 0.01)
}

private let lossyRate = 44_100.0
private let lossyFrames = AVAudioFrameCount(88_200)

@Suite("Analysis — programme bandwidth through AAC (reference method)")
struct ProgrammeBandwidthAACTests {

    /// A lossy transport is allowed to move the reading — it genuinely changes the samples — but it
    /// must not destroy the fact. Measured at 128 kbps: the source reads 20 075 Hz and the AAC reads
    /// 20 167 Hz, four bins apart, with the codec's own artefacts sitting below the threshold rather
    /// than pushing the answer to Nyquist.
    @Test("AAC moves the reading by a few bins and does not send it to Nyquist")
    func aacPreservesTheFact() async throws {
        try await withTemporaryDirectory { directory in
            let source = try #require(try await measureLossy(.wavFloat, name: "aac-source", in: directory))
            let encoded = try #require(try await measureLossy(.aac, name: "aac-encoded", in: directory))
            #expect(encoded.resolution == source.resolution)
            #expect(
                abs(encoded.bin - source.bin) <= 8,
                "AAC read bin \(encoded.bin) where the source read \(source.bin) — the fact did not survive"
            )
            #expect(
                encoded.frequency < lossyRate / 2 - 1_000,
                "AAC read \(encoded.frequency) Hz, at the top of the band: its artefacts became the answer"
            )
        }
    }

    private func measureLossy(
        _ format: AudioFixtureFormat, name: String, in directory: URL
    ) async throws -> ProgrammeBandwidthReading? {
        let url = try writeAudioFixture(
            AudioFixtureSpec(
                name: name, format: format, signal: lossySource(),
                sampleRate: lossyRate, channels: 1, frames: lossyFrames
            ),
            in: directory
        )
        return try await measureProgrammeBandwidth(of: url).readings.first ?? nil
    }
}

@Suite(
    "Analysis — programme bandwidth through MP3 and rewrap (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.hasMP3Encoder,
        """
        FFmpeg with libmp3lame is not installed on this machine, so no MP3 fixture can be produced. \
        This suite is SKIPPED, and a SKIPPED RUN IS NOT MP3 COVERAGE: task 2.4's MP3 row stays open and \
        nothing may cite this run as evidence that the measurement survives an MP3.
        """
    )
)
struct ProgrammeBandwidthMP3Tests {

    /// The source is ours, written by the same deterministic writer every other row uses, so what
    /// FFmpeg encodes is a pure function of parameters in this repository. FFmpeg produces fixtures
    /// and never establishes a fact: every number below comes from the production decoder.
    private func source(in directory: URL) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "mp3-bandwidth-source", format: .wavFloat, signal: lossySource(),
                sampleRate: lossyRate, channels: 1, frames: lossyFrames
            ),
            in: directory
        )
    }

    /// A low bitrate low-passes hard, and that is the whole point: the measurement sees the codec's
    /// band limit as a *fact about the samples*, without reading a header and without asserting how
    /// the file was made. The exact figure depends on the encoder's build, so what is pinned is that
    /// it sits clearly below the source and clearly above nothing.
    @Test("a low-bitrate MP3 reads its own band limit")
    func lowBitrateShowsItsLimit() async throws {
        try await withTemporaryDirectory { directory in
            let source = try source(in: directory)
            let sourceReading = try #require(try await measureProgrammeBandwidth(of: source).readings.first ?? nil)
            let mp3 = try encode(source, bitrate: "64k", to: directory)
            let reading = try #require(try await measureProgrammeBandwidth(of: mp3).readings.first ?? nil)
            #expect(
                reading.frequency < sourceReading.frequency - 1_000,
                "a 64 kbps MP3 read \(reading.frequency) Hz against a source of \(sourceReading.frequency) Hz"
            )
            #expect(reading.frequency > 10_000, "a 64 kbps MP3 read \(reading.frequency) Hz, which is not a band limit")
        }
    }

    /// A high bitrate keeps the source's own edge, so the measurement is not simply reporting "lossy".
    @Test("a high-bitrate MP3 keeps the source's edge")
    func highBitrateKeepsTheEdge() async throws {
        try await withTemporaryDirectory { directory in
            let source = try source(in: directory)
            let sourceReading = try #require(try await measureProgrammeBandwidth(of: source).readings.first ?? nil)
            let mp3 = try encode(source, bitrate: "320k", to: directory)
            let reading = try #require(try await measureProgrammeBandwidth(of: mp3).readings.first ?? nil)
            #expect(
                abs(reading.bin - sourceReading.bin) <= 8,
                "a 320 kbps MP3 read bin \(reading.bin) where the source read \(sourceReading.bin)"
            )
        }
    }

    /// **The rewrap row.** An MP3 decoded and written back out as PCM is a lossless container carrying
    /// lossy samples, and the band limit travels with the samples rather than with the container.
    ///
    /// This is evidence about **spectral extent**, and nothing else. It does not say the WAV "came
    /// from an MP3" — ADR-0023 §1 and `CLAUDE.md` both forbid asserting transcoding from a frequency
    /// cut-off, and this suite asserts only that the two files measure the same.
    @Test("the measured extent survives a rewrap to PCM", arguments: ["64k", "128k", "320k"])
    func rewrapPreservesTheExtent(bitrate: String) async throws {
        try await withTemporaryDirectory { directory in
            let mp3 = try encode(try source(in: directory), bitrate: bitrate, to: directory)
            let rewrapped = directory.appendingPathComponent("rewrapped-\(bitrate).wav")
            try FFmpegTool.run([
                "-hide_banner", "-nostdin", "-y", "-i", mp3.path, "-codec:a", "pcm_f32le", rewrapped.path,
            ])
            let fromMP3 = try #require(try await measureProgrammeBandwidth(of: mp3).readings.first ?? nil)
            let fromWAV = try #require(try await measureProgrammeBandwidth(of: rewrapped).readings.first ?? nil)
            #expect(
                fromWAV.bin == fromMP3.bin,
                "the rewrapped WAV read bin \(fromWAV.bin) where the MP3 read \(fromMP3.bin)"
            )
            #expect(fromWAV.resolution == fromMP3.resolution)
        }
    }

    private func encode(_ source: URL, bitrate: String, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("bandwidth-\(bitrate).mp3")
        try FFmpegTool.run([
            "-hide_banner", "-nostdin", "-y", "-i", source.path,
            "-codec:a", "libmp3lame", "-b:a", bitrate, url.path,
        ])
        return url
    }
}
