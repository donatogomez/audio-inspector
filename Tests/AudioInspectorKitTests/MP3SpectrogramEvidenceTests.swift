import AVFoundation
import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
@testable import AudioInspectorApp
import CryptoKit
import FeatureImport
import Foundation
import Testing

// The MP3 row of the spectrogram acceptance matrix — the one format macOS cannot produce for itself.
//
// **This is local evidence, and it is explicitly NOT CI coverage.** `.github/workflows/ci.yml` runs on
// `macos-26` and installs no FFmpeg, so this suite skips on every CI run. A skip proves nothing and
// must never be counted as a passing row: task 8.6 says so, and the waveform slice's task 0.6 set the
// precedent this file follows exactly.
//
// FFmpeg is used **only** to produce a fixture, never to decode one and never to establish a fact:
// every assertion below is about what the production pipeline — `AVFoundationAudioDecoder` →
// `SpectrogramGeneration` → `Spectrogram` — did with the file. macOS has an MP3 decoder but no MP3
// encoder, so the fixture has to come from somewhere, and FFmpeg is already a declared dev/test-only
// dependency (ADR-0003). It becomes neither a production nor a CI dependency here, and no audio binary
// enters the repository: everything is generated into a temporary directory and removed with it.
//
// `FFmpegTool` is **reused** from `MP3WaveformEvidenceTests` rather than copied — one locator, one
// argument-vector launcher, one failure type. Nothing about the waveform row is changed by this file.

extension FFmpegTool {
    /// Whether this build actually carries the encoder the fixture needs.
    ///
    /// A build of FFmpeg without `libmp3lame` would fail *inside* the gate, which must be a failure and
    /// never a skip — so the encoder is part of what the gate asks about, not something discovered
    /// half-way through. One short process at collection time, and the answer is cached.
    static let hasMP3Encoder: Bool = {
        guard isAvailable else { return false }
        guard let output = try? run(["-hide_banner", "-nostdin", "-encoders"]) else { return false }
        return output.contains("libmp3lame")
    }()
}

@Suite(
    "Analysis — MP3 spectrogram (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.hasMP3Encoder,
        """
        FFmpeg with libmp3lame is not installed on this machine, so no MP3 fixture can be produced. \
        This suite is SKIPPED, and a SKIPPED RUN IS NOT MP3 COVERAGE: task 8.6's MP3 row stays open and \
        nothing may cite this run as evidence that the pipeline handles MP3.
        """
    )
)
struct MP3SpectrogramEvidenceTests {

    /// The source is **ours**: written by the same deterministic fixture writer every other row uses, so
    /// the audio FFmpeg encodes is a pure function of parameters in this repository. A prime frame count
    /// leaves a short final chunk at every chunk size above one, and the two channels carry different
    /// frequencies so they are not copies.
    private var source: AudioFixtureSpec {
        AudioFixtureSpec(
            name: "mp3-spectrogram-source",
            format: .wav,
            signal: .perChannelSine(frequencies: [1_000, 3_000], amplitude: 0.5),
            sampleRate: 44_100,
            channels: 2,
            frames: framesWithShortFinalChunkAtAnyChunkSize
        )
    }

    /// Encodes to MP3 with pinned, explicit parameters, through a **separated argument vector** — never
    /// a shell string, so nothing in a path can be interpreted as a command. `FFmpegTool.run` throws on
    /// a non-zero exit, and that throw stays a **failure**: a fixture that was not produced is this
    /// test failing, never a reason to skip it.
    private func encodeMP3(from wav: URL, to mp3: URL, bitrate: String = "192k") throws {
        try FFmpegTool.run([
            "-hide_banner", "-nostdin", "-y",
            "-i", wav.path,
            "-map_metadata", "-1",
            "-c:a", "libmp3lame",
            "-b:a", bitrate,
            "-ar", "44100",
            "-ac", "2",
            mp3.path,
        ])
    }

    private func sha256Hex(of url: URL) throws -> String {
        try SHA256.hash(data: Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The row

    /// The whole MP3 case in one run: encode, then decode and transform with the **production**
    /// pipeline, and assert what the model must satisfy — plus that the file came back byte-identical.
    ///
    /// The values are deliberately **not** compared against the source's model: MP3 is lossy, so such a
    /// comparison would be asserting LAME's psychoacoustics. What is compared instead is structural —
    /// the geometry, the finiteness, the floor, the presence of the tones the file was written with —
    /// and the file against itself at different chunk sizes.
    @Test("a real MP3 decodes through the production pipeline into a coherent spectrogram")
    func mp3YieldsACoherentSpectrogram() async throws {
        try await withTemporaryDirectory { directory in
            let ffmpegVersion = try FFmpegTool.versionLine()

            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = directory.appendingPathComponent("mp3-fixture.mp3")
            try encodeMP3(from: wav, to: mp3)

            let digestBefore = try sha256Hex(of: mp3)
            let sizeBefore = try #require(
                try FileManager.default.attributesOfItem(atPath: mp3.path)[.size] as? Int
            )
            let declared = try readBackMetadata(of: mp3)

            let model = try requireModel(await productionSpectrogram(at: mp3), "MP3")

            // The stream it describes is the one the file declares — including the length an encoder is
            // entitled to have changed with its own delay and padding, which is read back rather than
            // assumed equal to the source's.
            #expect(model.sampleRate == declared.sampleRate)
            #expect(model.channelCount == Int(declared.channels))
            #expect(model.frameCount == Int(declared.frames))
            #expect(model.nyquist == declared.sampleRate / 2)

            // Bounded by the grid, and every value describable.
            #expect(model.columnCount > 0)
            #expect(model.columnCount <= SpectrogramGridMapping.defaultMaximumColumnCount)
            #expect(model.bandCount == SpectrogramGridMapping.defaultMaximumBandCount)
            #expect(model.values.count == model.columnCount * model.bandCount)
            #expect(model.values.allSatisfy { $0.isFinite }, "a non-finite value reached the MP3 model")
            #expect(model.values.allSatisfy { $0 >= Spectrogram.floorDecibels })

            // The signal survived: a lossy encoder changes the samples, it does not flatten two
            // half-scale tones into silence, and it does not move them to another part of the spectrum.
            let peaks = bandPeaks(of: model)
            for frequency in [1_000.0, 3_000.0] {
                let band = Int(frequency / model.nyquist * Double(model.bandCount))
                let local = (max(0, band - 2) ... min(model.bandCount - 1, band + 2)).map { peaks[$0] }.max() ?? -120
                #expect(local > -20, "MP3 lost the \(Int(frequency)) Hz tone: \(local) dBFS")
            }

            // Nothing was normalised on the lossy path either.
            #expect(model.values.contains { $0 == Spectrogram.floorDecibels }, "the MP3 model has no floor at all")

            // The source is untouched — the pipeline only reads.
            #expect(try sha256Hex(of: mp3) == digestBefore, "the MP3 was modified by reading it")
            #expect(try FileManager.default.attributesOfItem(atPath: mp3.path)[.size] as? Int == sizeBefore)

            // Nothing was written outside the temporary directory this test owns.
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(contents == ["mp3-fixture.mp3", "mp3-spectrogram-source.wav"])

            // Recorded so the run that closed task 8.6's MP3 row can be compared against a later one.
            print("""
            MP3 spectrogram evidence (local, not CI coverage)
              ffmpeg:            \(ffmpegVersion)
              command:           ffmpeg -hide_banner -nostdin -y -i <source.wav> -map_metadata -1 \
            -c:a libmp3lame -b:a 192k -ar 44100 -ac 2 <fixture.mp3>
              source frames:     \(source.frames) @ \(Int(source.sampleRate)) Hz, 2 ch
              mp3 sha256:        \(digestBefore)
              mp3 size:          \(sizeBefore) bytes
              decoded frames:    \(model.frameCount)
              model:             \(model.columnCount) × \(model.bandCount)
              loudest cell:      \(model.values.max() ?? -120) dBFS
            """)
        }
    }

    /// The `frameLength` invariant over MP3 specifically, and the chunk independence that only a
    /// `frameLength`-bounded reader can achieve: the region past the reported frame count differs with
    /// the buffer's capacity, so a reader consuming the capacity would disagree with itself here. The
    /// frame count is prime, so every one of these sizes leaves a short final chunk.
    @Test(
        "the same MP3 yields the same model at every chunk size",
        arguments: [1, 3, 127, 512, 1_152, 4_096, 65_536]
    )
    func chunkSizeDoesNotChangeTheMP3Model(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = directory.appendingPathComponent("mp3-fixture.mp3")
            try encodeMP3(from: wav, to: mp3)

            let whole = try requireModel(
                await productionSpectrogram(at: mp3, chunkFrames: 200_000), "MP3 whole"
            )
            let chunked = try requireModel(
                await productionSpectrogram(at: mp3, chunkFrames: chunkFrames), "MP3 at \(chunkFrames)"
            )

            #expect(chunked == whole, "chunk size \(chunkFrames) changed the MP3 model")
        }
    }

    /// **The observation this capability exists for, on a real lossy file.**
    ///
    /// A 128 kbit/s MP3 carries nothing above roughly 16 kHz, and the drawing shows exactly that: its
    /// edge sits far below the source's. Rewrapping that MP3 into a WAV does not put the missing content
    /// back, and the model of the rewrapped file reports **the same edge** — which is the whole reason a
    /// collector looks at a spectrogram.
    ///
    /// The numbers are read from this run, not from the spike, and the edges are compared to one another
    /// rather than pinned to a literal frequency: LAME's exact band limit is LAME's business.
    ///
    /// **It says only where the energy stops.** Nothing here — and nothing in the model — states or
    /// implies that a file is lossy, transcoded, fake or poor. That the rewrapped WAV came from an MP3
    /// is a fact of *this test's* construction, never a conclusion the pipeline drew.
    @Test("a band limit introduced by a lossy encoder survives being rewrapped as WAV")
    func theEdgeSurvivesTranscoding() async throws {
        try await withTemporaryDirectory { directory in
            // A source whose content reaches well above where a 128 kbit/s encoder will stop.
            var wide = source
            wide.name = "wide-source"
            wide.signal = .bandLimitedTones(highest: 21_000, spacing: 500, lowest: 1_000, amplitude: 0.9)
            let wav = try writeAudioFixture(wide, in: directory)

            let mp3 = directory.appendingPathComponent("narrow.mp3")
            try encodeMP3(from: wav, to: mp3, bitrate: "128k")

            let rewrapped = directory.appendingPathComponent("rewrapped.wav")
            try FFmpegTool.run([
                "-hide_banner", "-nostdin", "-y",
                "-i", mp3.path,
                "-map_metadata", "-1",
                "-c:a", "pcm_s16le",
                rewrapped.path,
            ])

            let sourceModel = try requireModel(await productionSpectrogram(at: wav), "wide source")
            let mp3Model = try requireModel(await productionSpectrogram(at: mp3), "MP3")
            let rewrappedModel = try requireModel(await productionSpectrogram(at: rewrapped), "rewrapped WAV")

            let sourceEdge = try #require(highestBand(of: sourceModel))
            let mp3Edge = try #require(highestBand(of: mp3Model))
            let rewrappedEdge = try #require(highestBand(of: rewrappedModel))

            let bandWidth = sourceModel.nyquist / Double(sourceModel.bandCount)

            // The encoder stopped well short of the source.
            #expect(
                mp3Edge < sourceEdge - 20,
                "the MP3's edge (band \(mp3Edge)) was not clearly below the source's (band \(sourceEdge))"
            )

            // And the rewrapping put nothing back: the same edge, within a band or two of resolution.
            #expect(
                abs(rewrappedEdge - mp3Edge) <= 2,
                "the rewrapped WAV reported band \(rewrappedEdge) where the MP3 reported \(mp3Edge)"
            )

            print("""
            MP3 band-limit evidence (local, not CI coverage)
              ffmpeg:            \(try FFmpegTool.versionLine())
              encoder:           libmp3lame, CBR 128k, 44100 Hz, 2 ch; rewrapped with pcm_s16le
              source edge:       band \(sourceEdge) ≈ \(Int(Double(sourceEdge) * bandWidth)) Hz
              mp3 edge:          band \(mp3Edge) ≈ \(Int(Double(mp3Edge) * bandWidth)) Hz
              rewrapped edge:    band \(rewrappedEdge) ≈ \(Int(Double(rewrappedEdge) * bandWidth)) Hz
            """)
        }
    }

    /// A file named `.mp3` that is not audio fails, and the failure names no path and no framework —
    /// MP3 reaches the surface through exactly the same neutral message as every other format.
    @Test("a file that is not audio fails without disclosing a path or a framework")
    func aFileThatIsNotAudioFailsCleanly() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("not-audio.mp3")
            try Data("this is not audio".utf8).write(to: url)

            let outcome = await productionSpectrogram(at: url)
            guard case let .failed(message) = outcome else {
                Issue.record("a file that is not audio produced \(outcome)"); return
            }
            #expect(!message.contains("/"), "a path reached the message")
            #expect(!message.lowercased().contains("avaudio"), "a framework name reached the message")
            #expect(!message.contains(directory.path))
        }
    }

    /// **The case MP3 brings that no other format in the matrix does:** its length can be *declared* by a
    /// header while the frames behind it are missing. LAME writes a Xing/Info header carrying the total
    /// duration and CoreAudio believes it, so a truncated MP3 opens and reports the full original
    /// length — and the pipeline must refuse rather than presenting a partial model as a complete one.
    @Test("a truncated MP3 whose header still declares the full length is refused, not half-drawn")
    func aTruncatedMP3IsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let wav = try writeAudioFixture(source, in: directory)
            let mp3 = directory.appendingPathComponent("truncated.mp3")
            try encodeMP3(from: wav, to: mp3)
            try truncateFixture(at: mp3, toFirst: 2_000)

            let outcome = await productionSpectrogram(at: mp3)
            guard case let .failed(message) = outcome else {
                Issue.record("a truncated MP3 produced \(outcome)"); return
            }
            #expect(!message.contains("/"))
            #expect(!message.contains(directory.path))
        }
    }
}
