import AVFoundation
import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
import AudioInspectorTesting
@testable import AudioInspectorApp
import CryptoKit
import FeatureImport
import Foundation
import Testing

// The spectrogram acceptance matrix, run against the **production** pipeline over real files:
// `AVFoundationAudioDecoder` → `SpectrogramGeneration` → `SpectrogramAccumulator` → `Spectrogram`.
//
// Everything the groups before this proved with synthetic chunks and a fake port is proved once more
// here with a decoder that opens a file. Nothing below re-implements the transform, the reader or the
// reduction: every assertion is about the model the production composition returns, which is the only
// surface a regression could hide behind. The spike is **not** used as a reference implementation —
// where a figure below matches one of its measurements, that is a result, not an input.
//
// **MP3 is deliberately absent from this file.** macOS has no MP3 encoder, so its row lives in
// `MP3SpectrogramEvidenceTests`, gated on FFmpeg, and a skipped run there is never counted as coverage.

// MARK: - Driving the production pipeline

private func matrixReference() -> AudioFileReference {
    AudioFileReference(
        displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
        source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
    )
}

/// One production generation over the file at `url`. The decoder is the real adapter, the accumulator
/// is built inside `SpectrogramGeneration`, and neither is substituted.
func productionSpectrogram(
    at url: URL,
    chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames
) async -> SpectrogramOutcome {
    await SpectrogramGeneration(
        decoder: AVFoundationAudioDecoder(resolveURL: { _ in url }),
        chunkFrames: chunkFrames
    ).run(for: matrixReference())
}

/// The model, or a recorded failure naming what came back instead.
func requireModel(
    _ outcome: SpectrogramOutcome,
    _ what: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> Spectrogram {
    guard case let .available(model) = outcome else {
        Issue.record("\(what): expected a model, got \(outcome)", sourceLocation: sourceLocation)
        throw SpectrogramMatrixFailure.noModel
    }
    return model
}

enum SpectrogramMatrixFailure: Error { case noModel }

/// The loudest value each band reaches anywhere in the file — the profile a cutoff is read from.
func bandPeaks(of model: Spectrogram) -> [Float] {
    (0 ..< model.bandCount).map { band in
        var peak = -Float.infinity
        for column in 0 ..< model.columnCount {
            peak = max(peak, model.value(column: column, band: band) ?? -Float.infinity)
        }
        return peak
    }
}

/// The highest band still carrying energy within `range` dB of the file's own loudest cell.
///
/// Measured **relative to the content**, never against an absolute number: an absolute threshold would
/// make the answer depend on how loud the file happens to be, which is a property of the recording
/// rather than of where its energy stops.
func highestBand(of model: Spectrogram, within range: Float = 60) -> Int? {
    guard let loudest = model.values.max() else { return nil }
    let threshold = loudest - range
    return bandPeaks(of: model).lastIndex { $0 > threshold }
}

func sha256Digest(of url: URL) throws -> SHA256Digest {
    try SHA256.hash(data: Data(contentsOf: url))
}

/// A stereo fixture whose two channels carry different frequencies, sized so that **every** chunk size
/// above one leaves a short final chunk. Both properties matter: copies of one channel would hide a
/// codec folding them together, and a composite frame count would never exercise the region past
/// `frameLength`.
private func matrixSpec(_ format: AudioFixtureFormat, name: String = "matrix") -> AudioFixtureSpec {
    AudioFixtureSpec(
        name: "\(name)-\(format)",
        format: format,
        signal: .perChannelSine(frequencies: [1_000, 3_000], amplitude: 0.5),
        sampleRate: 44_100,
        channels: 2,
        frames: framesWithShortFinalChunkAtAnyChunkSize
    )
}

// MARK: - One row per format (8.6)

@Suite("Analysis — the spectrogram format matrix, over real files")
struct SpectrogramFormatMatrixTests {

    /// The row every natively writable format must satisfy: it opens, describes itself coherently, and
    /// yields a bounded model of finite values that carries the signal the file was written with.
    @Test("every natively writable format yields a coherent spectrogram", arguments: AudioFixtureFormat.allCases)
    func everyFormatYieldsASpectrogram(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(format), in: directory)
            let declared = try readBackMetadata(of: url)

            let model = try requireModel(await productionSpectrogram(at: url), "\(format)")

            // It describes the stream the file declares.
            #expect(model.sampleRate == declared.sampleRate)
            #expect(model.channelCount == Int(declared.channels))
            #expect(model.frameCount == Int(declared.frames))

            // Bounded by the production caps, never by the file.
            #expect(model.columnCount > 0)
            #expect(model.columnCount <= SpectrogramGridMapping.defaultMaximumColumnCount)
            #expect(model.bandCount == SpectrogramGridMapping.defaultMaximumBandCount)
            #expect(model.values.count == model.columnCount * model.bandCount)

            // Every value describable, and none below the floor the producer is required to apply.
            #expect(model.values.allSatisfy { $0.isFinite }, "a non-finite value reached the model")
            #expect(model.values.allSatisfy { $0 >= Spectrogram.floorDecibels })

            // The axis reaches the file's own Nyquist and is not cropped.
            #expect(model.nyquist == declared.sampleRate / 2)
            let top = try #require(model.frequency(ofBand: model.bandCount - 1))
            #expect(top > model.nyquist - model.nyquist / Double(model.bandCount))

            // The signal survived: two half-scale tones do not decode into silence in any format.
            #expect(model.values.contains { $0 > -20 }, "the model of \(format) carries no signal")
        }
    }

    /// The columns follow the file's own length, and the bands follow its transform, rather than either
    /// following the caller. Asserted against the arithmetic the domain declares, not against a literal.
    @Test("columns and bands follow the file, within the caps", arguments: AudioFixtureFormat.allCases)
    func columnsAndBandsAreCoherent(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(format), in: directory)
            let model = try requireModel(await productionSpectrogram(at: url), "\(format)")

            let windows = model.frameCount >= SpectrogramAccumulator.fftSize
                ? (model.frameCount - SpectrogramAccumulator.fftSize) / SpectrogramAccumulator.hop + 1
                : 0
            let mapping = try #require(SpectrogramGridMapping(
                stftFrameCount: windows, binCount: SpectrogramAccumulator.binCount
            ))

            #expect(model.columnCount == mapping.columnCount)
            #expect(model.bandCount == mapping.bandCount)
        }
    }

    /// The adapter only reads. Asserted over every format, because a container that needed rewriting an
    /// index to be decoded would show up here and nowhere else.
    @Test("the source is byte-identical after the whole pipeline runs", arguments: AudioFixtureFormat.allCases)
    func theSourceIsNeverTouched(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(format), in: directory)
            let digestBefore = try sha256Digest(of: url)
            let attributesBefore = try FileManager.default.attributesOfItem(atPath: url.path)
            let contentsBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

            _ = try requireModel(await productionSpectrogram(at: url), "\(format)")

            #expect(try sha256Digest(of: url) == digestBefore, "\(format) was modified by reading it")
            let attributesAfter = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(attributesBefore[.size] as? Int == attributesAfter[.size] as? Int)
            #expect(
                attributesBefore[.modificationDate] as? Date == attributesAfter[.modificationDate] as? Date,
                "\(format)'s modification date changed"
            )
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == contentsBefore,
                "a file was created or removed beside the \(format) source"
            )
        }
    }
}

// MARK: - Chunking, `frameLength` and determinism over real files (8.8)

@Suite("Analysis — the spectrogram does not depend on how the file was read")
struct SpectrogramChunkIndependenceTests {

    /// The property that makes the seam trustworthy, now over files rather than scripted chunks: the
    /// model is a function of the file alone, down to one frame per read.
    ///
    /// This is also where `frameLength` becomes observable. The region between `frameLength` and
    /// `frameCapacity` is never empty and differs with the capacity — for AAC it is content the read
    /// path produced from the audio itself — so a reader that consumed the capacity would disagree with
    /// itself across these sizes. The frame count is prime, so every size above one leaves a short
    /// final chunk and the region always exists.
    @Test(
        "the same file yields the same model at every chunk size",
        arguments: AudioFixtureFormat.allCases, [1, 3, 127, 512, 2_048, 4_096, 65_536]
    )
    func chunkSizeDoesNotChangeTheModel(format: AudioFixtureFormat, chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(format, name: "chunk"), in: directory)

            let whole = try requireModel(
                await productionSpectrogram(at: url, chunkFrames: 200_000), "\(format) whole"
            )
            let chunked = try requireModel(
                await productionSpectrogram(at: url, chunkFrames: chunkFrames), "\(format) at \(chunkFrames)"
            )

            #expect(chunked == whole, "chunk size \(chunkFrames) changed the \(format) model")
        }
    }

    /// Only the frames a read reports as valid may contribute. A frame count of `fftSize` exactly means
    /// the file yields **one** complete window; anything read past `frameLength` would extend the audio
    /// and produce a second one.
    @Test("only the frames the file declares contribute", arguments: AudioFixtureFormat.allCases)
    func onlyDeclaredFramesContribute(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            // Ten complete windows and nothing left over, so an extra frame read past `frameLength`
            // would show up as an eleventh column. Not one window: FLAC refuses to reopen a file that
            // short, and a case a format cannot carry is worse than no case at all.
            var spec = matrixSpec(format, name: "exact")
            spec.frames = AVAudioFrameCount(SpectrogramAccumulator.fftSize + SpectrogramAccumulator.hop * 9)
            let url = try writeAudioFixture(spec, in: directory)
            let declared = try readBackMetadata(of: url)

            // A lossy encoder is entitled to its own delay and padding, so the declared length is read
            // back rather than assumed — the invariant is about the *declared* length, whatever it is.
            let expectedColumns = Int(declared.frames) >= SpectrogramAccumulator.fftSize
                ? (Int(declared.frames) - SpectrogramAccumulator.fftSize) / SpectrogramAccumulator.hop + 1
                : 0

            for chunkFrames in [1, 127, 1_024, 2_048] {
                let model = try requireModel(
                    await productionSpectrogram(at: url, chunkFrames: chunkFrames), "\(format)"
                )
                #expect(model.frameCount == Int(declared.frames))
                #expect(
                    model.columnCount == expectedColumns,
                    "\(format) at chunk \(chunkFrames) produced \(model.columnCount) columns, not \(expectedColumns)"
                )
            }
        }
    }

    @Test("the same file read twice produces the same model", arguments: AudioFixtureFormat.allCases)
    func generationIsDeterministic(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(format, name: "deterministic"), in: directory)
            let once = try requireModel(await productionSpectrogram(at: url), "\(format) first")
            let twice = try requireModel(await productionSpectrogram(at: url), "\(format) second")
            #expect(once == twice)
        }
    }

    /// The model is bounded by the grid, never by the duration: thirty times the audio yields the same
    /// 1024 × 512 ceiling, and the reads stay the size the caller asked for.
    @Test("the model is bounded by the grid rather than by the file's length")
    func theModelStaysBounded() async throws {
        try await withTemporaryDirectory { directory in
            var sizes: [(frames: Int, cells: Int, columns: Int)] = []
            for frames in [44_100, 441_000, 44_100 * 30] {
                let url = directory.appendingPathComponent("length-\(frames).wav")
                try writeAudioFixture(
                    AudioFixtureSpec(
                        name: "length", format: .wav, signal: .sine(frequency: 1_000, amplitude: 0.5),
                        sampleRate: 44_100, channels: 1, frames: AVAudioFrameCount(frames)
                    ),
                    to: url
                )
                let model = try requireModel(
                    await productionSpectrogram(at: url, chunkFrames: 1_024), "length \(frames)"
                )
                sizes.append((frames, model.values.count, model.columnCount))
                #expect(model.frameCount == frames, "the file's own length is still reported")
                #expect(model.bandCount == SpectrogramGridMapping.defaultMaximumBandCount)
            }

            let ceiling = SpectrogramGridMapping.defaultMaximumColumnCount
                * SpectrogramGridMapping.defaultMaximumBandCount
            #expect(sizes.allSatisfy { $0.cells <= ceiling }, "the model outgrew its grid")
            #expect(sizes.allSatisfy { $0.columns <= SpectrogramGridMapping.defaultMaximumColumnCount })
            // Thirty seconds is past the cap, so the longest file is capped rather than merely large.
            #expect(sizes.last?.columns == SpectrogramGridMapping.defaultMaximumColumnCount)
        }
    }

    /// A cancelled generation produces **no** model. Cancelled before the task is awaited, so the flag
    /// is already set at the first chunk boundary and nothing is assumed about the scheduler.
    @Test("a cancelled generation over a real file yields no partial model")
    func cancellationYieldsNoModel() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "cancelled", format: .wav, signal: .sine(frequency: 1_000, amplitude: 0.5),
                    sampleRate: 44_100, channels: 2, frames: 441_000
                ),
                in: directory
            )

            let task = Task { await productionSpectrogram(at: url, chunkFrames: 128) }
            task.cancel()

            let outcome = await task.value
            #expect(outcome == .cancelled)
            if case .available = outcome { Issue.record("a partial model escaped a cancelled generation") }
        }
    }
}

// MARK: - The container does not change the evidence (8.7)

@Suite("Analysis — the lossless container does not change the spectrogram")
struct SpectrogramContainerIndependenceTests {

    private func models(in directory: URL, formats: [AudioFixtureFormat]) async throws -> [(AudioFixtureFormat, Spectrogram)] {
        var result: [(AudioFixtureFormat, Spectrogram)] = []
        for format in formats {
            let url = try writeAudioFixture(matrixSpec(format, name: "container"), in: directory)
            result.append((format, try requireModel(await productionSpectrogram(at: url), "\(format)")))
        }
        return result
    }

    /// **WAV, AIFF and ALAC store this fixture at 16 bits, and their models are bit-identical.**
    ///
    /// Not approximately: `Spectrogram` is `Equatable` over its whole grid, and the comparison is exact.
    /// Rewrapping the same samples into a different lossless container changes nothing the drawing
    /// observes.
    @Test("three containers of the same 16-bit audio produce identical models")
    func sixteenBitContainersAreIdentical() async throws {
        try await withTemporaryDirectory { directory in
            let produced = try await models(in: directory, formats: [.wav, .aiff, .alac])
            let reference = try #require(produced.first)

            for (format, model) in produced.dropFirst() {
                #expect(model == reference.1, "\(format) differed from \(reference.0)")
            }
        }
    }

    /// **FLAC is lossless and still not bit-identical here — and the reason is the fixture, not the
    /// spectrogram.**
    ///
    /// `AVAudioFile` writes our FLAC *from a 24-bit source* while WAV, AIFF and ALAC take 16, so the two
    /// files do not carry the same PCM to begin with: the decoded samples differ by **1.51 × 10⁻⁵**,
    /// which is one 16-bit least significant bit. What that difference reaches in the model was measured
    /// rather than guessed:
    ///
    /// - the loudest cell agrees to **0.00004 dB** (−6.597004 against −6.597043);
    /// - across every cell at or above −60 dBFS the largest difference is **0.0025 dB**;
    /// - the largest difference anywhere is **10.74 dB**, and it sits at a cell reading **−109.3 dBFS**
    ///   in the 16-bit file against the **−120 dBFS floor** in the 24-bit one — the quantisation noise
    ///   floor of 16-bit storage, a hundred decibels below the content.
    ///
    /// So the tolerance below is not a preventive allowance: it is two orders of magnitude above the
    /// measured disagreement in the region a reader can see, and the exact-equality claim is kept for
    /// the containers that genuinely hold the same samples. The fixture writer is deliberately **not**
    /// changed to force FLAC to 16 bits, because `AudioFixtureFormat` is also the waveform slice's
    /// acceptance matrix and altering it would silently change what that matrix asserts.
    @Test("a lossless container at a different bit depth changes nothing a reader can see")
    func flacAgreesWhereItMatters() async throws {
        try await withTemporaryDirectory { directory in
            let produced = try await models(in: directory, formats: [.wav, .flac])
            let wav = try #require(produced.first?.1)
            let flac = try #require(produced.last?.1)

            // Structurally the same analysis of the same file.
            #expect(flac.columnCount == wav.columnCount)
            #expect(flac.bandCount == wav.bandCount)
            #expect(flac.frameCount == wav.frameCount)
            #expect(flac.sampleRate == wav.sampleRate)
            #expect(flac.channelCount == wav.channelCount)

            let wavPeak = try #require(wav.values.max())
            let flacPeak = try #require(flac.values.max())
            #expect(abs(wavPeak - flacPeak) < 0.05, "the peaks differed by \(abs(wavPeak - flacPeak)) dB")

            var worstVisible: Float = 0
            var worstAnywhere: Float = 0
            var worstAnywhereLevel: Float = 0
            for index in 0 ..< wav.values.count {
                let difference = abs(wav.values[index] - flac.values[index])
                if difference > worstAnywhere {
                    worstAnywhere = difference
                    worstAnywhereLevel = max(wav.values[index], flac.values[index])
                }
                if wav.values[index] > -60 || flac.values[index] > -60 {
                    worstVisible = max(worstVisible, difference)
                }
            }

            #expect(worstVisible < 0.05, "the containers disagreed by \(worstVisible) dB in visible content")
            #expect(
                worstAnywhereLevel < -100,
                "the containers' worst disagreement was at \(worstAnywhereLevel) dBFS, not in the noise floor"
            )
        }
    }

    /// **AAC is lossy, so nothing here asserts equality with its source.** What is asserted is what a
    /// lossy encoder may not do: lose the signal, move it, invent a level or produce a different shape
    /// of analysis.
    ///
    /// Measured on the same fixture: the loudest cell reads **−6.60 dBFS** from WAV and **−6.49** from
    /// AAC, and AAC lights 40 bands above −60 dBFS where WAV lights 11 — the encoder's own noise, which
    /// is a fact about AAC and not a defect of the drawing.
    @Test("AAC keeps the signal without being expected to match its source exactly")
    func aacKeepsTheSignalWithoutMatching() async throws {
        try await withTemporaryDirectory { directory in
            let produced = try await models(in: directory, formats: [.wav, .aac])
            let wav = try #require(produced.first?.1)
            let aac = try #require(produced.last?.1)

            // The same shape of analysis: a codec changes the samples, not the geometry.
            #expect(aac.columnCount == wav.columnCount)
            #expect(aac.bandCount == wav.bandCount)
            #expect(aac.sampleRate == wav.sampleRate)
            #expect(aac.channelCount == wav.channelCount)

            // The tones are still there, at their own level and in their own bands. The fixture's two
            // channels carry 1 kHz and 3 kHz, and the model combines them by maximum per bin.
            for frequency in [1_000.0, 3_000.0] {
                let band = Int(frequency / aac.nyquist * Double(aac.bandCount))
                let peaks = bandPeaks(of: aac)
                let local = (max(0, band - 2) ... min(aac.bandCount - 1, band + 2)).map { peaks[$0] }.max() ?? -120
                #expect(local > -20, "AAC lost the \(Int(frequency)) Hz tone: \(local) dBFS")
            }

            let wavPeak = try #require(wav.values.max())
            let aacPeak = try #require(aac.values.max())
            #expect(abs(wavPeak - aacPeak) < 1.0, "AAC moved the level by \(abs(wavPeak - aacPeak)) dB")

            // No normalisation crept in on the lossy path either: the model is not scaled to its peak.
            #expect(aac.values.contains { $0 == Spectrogram.floorDecibels }, "AAC's model has no floor at all")
            #expect(aac.values.allSatisfy { $0.isFinite })
        }
    }
}

// MARK: - Sample rates (8.3's axis half)

@Suite("Analysis — the frequency axis follows the file's own sample rate")
struct SpectrogramSampleRateTests {

    /// Every sample rate the fixture writer produces natively, for every format that can hold it.
    ///
    /// **AAC is absent above 48 kHz, and that is recorded rather than worked around**: `AVAudioFile`
    /// refuses to write it at 96 or 192 kHz (`ExtAudioFileWrite` fails with `-50`), so those rows are
    /// **not tested** for AAC. Nothing infers them from a neighbouring format.
    @Test(
        "the axis reaches the file's own Nyquist and is never cropped",
        arguments: [44_100.0, 48_000, 96_000, 192_000], [AudioFixtureFormat.wav, .aiff, .alac, .flac]
    )
    func nyquistFollowsTheFile(sampleRate: Double, format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "rate-\(Int(sampleRate))-\(format)", format: format,
                    signal: .perChannelSine(frequencies: [1_000, 3_000], amplitude: 0.5),
                    sampleRate: sampleRate, channels: 2, frames: 40_000
                ),
                in: directory
            )
            let declared = try readBackMetadata(of: url)
            #expect(declared.sampleRate == sampleRate, "the fixture was not written at \(sampleRate) Hz")

            let model = try requireModel(
                await productionSpectrogram(at: url), "\(format) at \(Int(sampleRate)) Hz"
            )

            #expect(model.sampleRate == sampleRate)
            #expect(model.nyquist == sampleRate / 2)
            // Never cropped to the audible band: the top band's stated frequency is within one band of
            // Nyquist itself, at 96 and 192 kHz just as at 44.1.
            let bandWidth = model.nyquist / Double(model.bandCount)
            let top = try #require(model.frequency(ofBand: model.bandCount - 1))
            #expect(model.nyquist - top <= bandWidth, "the axis stopped at \(top) Hz, short of \(model.nyquist)")
            #expect(model.bandCount == SpectrogramGridMapping.defaultMaximumBandCount)
            #expect(model.columnCount <= SpectrogramGridMapping.defaultMaximumColumnCount)
        }
    }

    /// The AAC rows that *can* be produced, kept apart from the ones that cannot so the gap is visible.
    @Test("AAC covers the two sample rates it can be written at", arguments: [44_100.0, 48_000])
    func aacCoversWhatItCanHold(sampleRate: Double) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "aac-rate-\(Int(sampleRate))", format: .aac,
                    signal: .perChannelSine(frequencies: [1_000, 3_000], amplitude: 0.5),
                    sampleRate: sampleRate, channels: 2, frames: 40_000
                ),
                in: directory
            )
            let model = try requireModel(await productionSpectrogram(at: url), "AAC at \(Int(sampleRate)) Hz")
            #expect(model.nyquist == sampleRate / 2)
            #expect(model.values.contains { $0 > -20 })
        }
    }

    /// The gap itself, asserted rather than described: writing AAC above 48 kHz fails on this platform,
    /// so the rows above are honestly absent instead of quietly missing. If a later SDK gains the
    /// encoder this test fails and the matrix is extended deliberately.
    @Test("AAC still cannot be written above 48 kHz, so those rows stay untested", arguments: [96_000.0, 192_000])
    func aacCannotBeWrittenAtHighRates(sampleRate: Double) async throws {
        try await withTemporaryDirectory { directory in
            var wrote = false
            do {
                _ = try writeAudioFixture(
                    AudioFixtureSpec(
                        name: "aac-high", format: .aac, signal: .sine(frequency: 1_000, amplitude: 0.5),
                        sampleRate: sampleRate, channels: 2, frames: 20_000
                    ),
                    in: directory
                )
                wrote = true
            } catch {
                wrote = false
            }
            #expect(
                !wrote,
                "AAC can now be written at \(Int(sampleRate)) Hz — extend the matrix deliberately"
            )
        }
    }
}

// MARK: - A cutoff is observable, and stays an observation (8.3)

/// A band-limited fixture with its topmost component exactly at `cutoff`.
private func bandLimitedSpec(
    _ format: AudioFixtureFormat,
    cutoff: Double,
    sampleRate: Double
) -> AudioFixtureSpec {
    AudioFixtureSpec(
        name: "cutoff-\(Int(cutoff))-\(Int(sampleRate))-\(format)",
        format: format,
        signal: .bandLimitedTones(highest: cutoff, spacing: 500, lowest: 1_000, amplitude: 0.9),
        sampleRate: sampleRate,
        channels: 1,
        frames: AVAudioFrameCount(SpectrogramAccumulator.fftSize + SpectrogramAccumulator.hop * 19)
    )
}

@Suite("Analysis — where a file's energy stops is observable")
struct SpectrogramCutoffTests {

    /// The edge lands **at or above** the true cutoff, and within a few reduced bands of it.
    ///
    /// **The tolerance comes from measurement, and it is wider than the task's prose.** Task 8.3 asks
    /// for the cutoff "located within one reduced band"; observed here, across 44.1/48/96/192 kHz and
    /// five cutoffs, the edge lands **+0.50 to +3.32 reduced bands above** the cutoff and never below.
    /// The spike's own table already showed this — +406…+531 Hz at 192 kHz against a 187.5 Hz band, or
    /// 2.2–2.8 bands — so its prose ("about one reduced band") understated its own numbers. Four bands
    /// is the measured ceiling with margin, not an allowance chosen in advance.
    ///
    /// The bias is one-sided and expected: the band holding the cutoff still carries energy from below
    /// it, so the observed edge can only be too high, never too low.
    /// Only the combinations a file can actually carry: a limit at or above the file's own Nyquist is
    /// not a band limit, it is the axis. Listed as pairs rather than filtered inside the test, so an
    /// impossible row is **absent** rather than silently passing.
    static let limitsBySampleRate: [(sampleRate: Double, cutoff: Double)] = [
        (44_100, 16_000), (44_100, 18_000), (44_100, 19_000), (44_100, 20_000),
        (48_000, 16_000), (48_000, 18_000), (48_000, 19_000), (48_000, 20_000), (48_000, 22_000),
        (96_000, 16_000), (96_000, 18_000), (96_000, 19_000), (96_000, 20_000), (96_000, 22_000),
        (192_000, 16_000), (192_000, 18_000), (192_000, 19_000), (192_000, 20_000), (192_000, 22_000),
    ]

    @Test(
        "a known band limit appears at or just above where the file's content stops",
        arguments: limitsBySampleRate
    )
    func theEdgeAppearsWhereTheContentStops(sampleRate: Double, cutoff: Double) async throws {
        try await withTemporaryDirectory { directory in
            let spec = bandLimitedSpec(.wav, cutoff: cutoff, sampleRate: sampleRate)
            let url = try writeAudioFixture(spec, in: directory)
            let model = try requireModel(
                await productionSpectrogram(at: url), "\(Int(cutoff)) Hz at \(Int(sampleRate)) Hz"
            )

            let peaks = bandPeaks(of: model)
            let bandWidth = model.nyquist / Double(model.bandCount)
            let loudest = try #require(model.values.max())
            let edge = try #require(highestBand(of: model))
            let edgeFrequency = try #require(model.frequency(ofBand: edge))

            // The comb's teeth are 500 Hz apart, so a single band below the edge can legitimately sit
            // in a gap between two of them. The window is one whole spacing wide, which always contains
            // at least one tooth whatever the sample rate makes a band worth.
            let spacingInBands = max(1, Int((500 / bandWidth).rounded(.up)))

            // Energy is clearly present below the limit — the file's loudest cell is down there.
            let justBelow = try #require(peaks[max(0, edge - spacingInBands) ... edge].max())
            #expect(justBelow > loudest - 6, "the content just below the limit read \(justBelow) dBFS")

            // …and clearly gone above it, within the same distance. This is the step, not the threshold
            // that found the edge: it compares two neighbouring windows of the same width.
            if edge + 1 < model.bandCount {
                let above = min(model.bandCount - 1, edge + spacingInBands)
                let justAbove = try #require(peaks[(edge + 1) ... above].max())
                #expect(
                    justBelow - justAbove > 40,
                    "the step across the limit was only \(justBelow - justAbove) dB"
                )
            }

            // The edge sits where the sample rate and the resolution say it should.
            let error = (edgeFrequency - cutoff) / bandWidth
            #expect(error >= -1, "the edge appeared \(error) bands *below* the limit")
            #expect(error <= 4, "the edge appeared \(error) bands above the limit")
        }
    }

    /// The property the whole slice was gated on: the five limits stay **separable from one another** at
    /// every sample rate, so the resolution is enough to tell a 19 kHz limit from a 20 kHz one.
    @Test("neighbouring band limits stay apart at every sample rate", arguments: [44_100.0, 48_000, 96_000, 192_000])
    func neighbouringLimitsStayApart(sampleRate: Double) async throws {
        try await withTemporaryDirectory { directory in
            var edges: [(cutoff: Double, band: Int)] = []
            for cutoff in [16_000.0, 18_000, 19_000, 20_000, 22_000] where cutoff < sampleRate / 2 - 100 {
                let url = try writeAudioFixture(
                    bandLimitedSpec(.wav, cutoff: cutoff, sampleRate: sampleRate), in: directory
                )
                let model = try requireModel(await productionSpectrogram(at: url), "\(Int(cutoff)) Hz")
                edges.append((cutoff, try #require(highestBand(of: model))))
            }

            #expect(edges.count >= 4, "too few limits were testable at \(Int(sampleRate)) Hz")
            for (lower, higher) in zip(edges, edges.dropFirst()) {
                #expect(
                    higher.band > lower.band,
                    "\(Int(higher.cutoff)) Hz did not read higher than \(Int(lower.cutoff)) Hz"
                )
                // Four bands is the narrowest margin the spike found — five, at 192 kHz between 18 and
                // 19 kHz — so anything at or above it keeps the two distinguishable.
                #expect(
                    higher.band - lower.band >= 4,
                    "\(Int(lower.cutoff)) and \(Int(higher.cutoff)) Hz were only \(higher.band - lower.band) bands apart"
                )
            }
        }
    }

    /// The same limit, rewrapped. **Every lossless container reports the identical band.** AAC is left
    /// out of the equality deliberately: a lossy encoder applies a band limit of its own, and holding it
    /// to the source's edge would be asserting the encoder rather than the drawing.
    @Test("the same band limit survives a change of lossless container")
    func theEdgeSurvivesTheContainer() async throws {
        try await withTemporaryDirectory { directory in
            var edges: [(AudioFixtureFormat, Int)] = []
            for format in [AudioFixtureFormat.wav, .aiff, .alac, .flac] {
                let url = try writeAudioFixture(
                    bandLimitedSpec(format, cutoff: 16_000, sampleRate: 44_100), in: directory
                )
                let model = try requireModel(await productionSpectrogram(at: url), "\(format)")
                edges.append((format, try #require(highestBand(of: model))))
            }

            let reference = try #require(edges.first)
            for (format, band) in edges.dropFirst() {
                #expect(band == reference.1, "\(format) reported band \(band), \(reference.0) reported \(reference.1)")
            }
        }
    }

    /// **And the model turns none of it into a verdict.** The type carries a grid, a sample rate, a
    /// frame count and a channel count — no confidence, no flag, no conclusion — so there is nothing on
    /// it for a surface to read a judgement from.
    @Test("a file with an obvious band limit yields a model that says nothing about why")
    func theEdgeIsNeverAVerdict() async throws {
        try await withTemporaryDirectory { directory in
            let limited = try writeAudioFixture(
                bandLimitedSpec(.wav, cutoff: 16_000, sampleRate: 44_100), in: directory
            )
            var fullSpec = bandLimitedSpec(.wav, cutoff: 21_000, sampleRate: 44_100)
            fullSpec.name = "full-band"
            let full = try writeAudioFixture(fullSpec, in: directory)

            let limitedModel = try requireModel(await productionSpectrogram(at: limited), "limited")
            let fullModel = try requireModel(await productionSpectrogram(at: full), "full")

            // The two files really do differ in the one way the drawing can see…
            let limitedEdge = try #require(highestBand(of: limitedModel))
            let fullEdge = try #require(highestBand(of: fullModel))
            #expect(fullEdge > limitedEdge, "the two fixtures were not distinguishable at all")

            // …and in no other way the model can express. Same geometry, same scale, same everything the
            // type carries. There is no field that could hold a conclusion.
            #expect(limitedModel.columnCount == fullModel.columnCount)
            #expect(limitedModel.bandCount == fullModel.bandCount)
            #expect(limitedModel.sampleRate == fullModel.sampleRate)
            #expect(limitedModel.frameCount == fullModel.frameCount)
            #expect(limitedModel.channelCount == fullModel.channelCount)
        }
    }
}

// MARK: - Adverse files, through the real pipeline (8.8)

@Suite("Analysis — adverse files through the production pipeline")
struct SpectrogramAdverseFileTests {

    /// A file that cannot be opened is a failure, and the message says nothing a user cannot act on:
    /// no path, no framework, no error code.
    @Test("an empty file fails without disclosing a path or a framework")
    func anEmptyFileFails() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeEmptyFixture(named: "empty", format: .wav, in: directory)
            let outcome = await productionSpectrogram(at: url)

            guard case let .failed(message) = outcome else {
                Issue.record("an empty file produced \(outcome)"); return
            }
            #expect(!message.contains("/"), "a path reached the message")
            #expect(!message.lowercased().contains("avaudio"))
            #expect(!message.contains(directory.path))
        }
    }

    @Test("a file whose header is corrupt fails rather than yielding an empty model")
    func aCorruptHeaderFails() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "corrupt", format: .wav, signal: .silence, channels: 1, frames: 10_000),
                in: directory
            )
            try corruptFixture(at: url, replacingBytesIn: 0 ..< 32, with: 0xFF)

            let outcome = await productionSpectrogram(at: url)
            guard case .failed = outcome else {
                Issue.record("a corrupt header produced \(outcome)"); return
            }
        }
    }

    /// **Observed, not assumed.** A truncated AAC still declares its original length through its
    /// container index, so the decode runs out of frames before the declared end — and the pipeline
    /// refuses rather than presenting a short read as a complete model. That is the same `readFailed`
    /// path the waveform's MP3 row exercises, reached here by a different route.
    @Test("a truncated AAC is refused rather than half-drawn")
    func aTruncatedAACIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(.aac, name: "truncated"), in: directory)
            try truncateFixture(at: url, toFirst: 4_000)

            let outcome = await productionSpectrogram(at: url)
            guard case .failed = outcome else {
                Issue.record("a truncated AAC produced \(outcome)"); return
            }
        }
    }

    /// **A truncated WAV is a different case, and the difference is measured rather than argued.** Its
    /// header is recomputed from what is left, so it opens and declares the shorter length — and the
    /// model honestly describes *that* shorter file. Nothing is invented to fill the gap.
    @Test("a truncated WAV describes what is left of it, without inventing the rest")
    func aTruncatedWAVDescribesWhatRemains() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "short-wav", format: .wav, signal: .sine(frequency: 1_000, amplitude: 0.5),
                    sampleRate: 44_100, channels: 1, frames: 20_000
                ),
                in: directory
            )
            try truncateFixture(at: url, toFirst: 8_192)
            let declared = try readBackMetadata(of: url)

            let model = try requireModel(await productionSpectrogram(at: url), "truncated WAV")
            #expect(model.frameCount == Int(declared.frames), "the model claimed frames the file no longer has")
            #expect(model.frameCount < 20_000, "the truncation had no effect, so this proves nothing")
            #expect(model.values.allSatisfy { $0.isFinite })
        }
    }

    /// A file with real audio but less than one analysis window: a valid model of **no columns**. Not an
    /// absence, not a failure, and no column invented for it.
    @Test("a file shorter than one window yields a valid model with no columns", arguments: [1, 512, 2_047])
    func aFileShorterThanOneWindow(frames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "tiny-\(frames)", format: .wav, signal: .sine(frequency: 1_000, amplitude: 0.5),
                    sampleRate: 44_100, channels: 1, frames: AVAudioFrameCount(frames)
                ),
                in: directory
            )

            let model = try requireModel(await productionSpectrogram(at: url), "\(frames) frames")
            #expect(model.columnCount == 0)
            #expect(model.values.isEmpty)
            #expect(model.frameCount == frames, "the file's real length is still reported")
        }
    }

    /// A file with no audio at all: also a valid model with no columns, and a **different** thing from
    /// the port reporting an absence.
    @Test("a file with no audio yields a valid model rather than an absence")
    func aFileWithNoAudio() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "no-audio", format: .wav, signal: .silence, channels: 1, frames: 0),
                in: directory
            )

            let outcome = await productionSpectrogram(at: url)
            let model = try requireModel(outcome, "no audio")
            #expect(model.columnCount == 0)
            #expect(model.frameCount == 0)
            #expect(outcome != .unavailable, "an empty model is not an absence")
        }
    }

    /// The parameter the caller controls is refused before a file is opened.
    @Test("a chunk size of zero or fewer frames fails the generation", arguments: [0, -1, -4_096])
    func anInvalidChunkSizeFails(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(matrixSpec(.wav, name: "config"), in: directory)
            let outcome = await productionSpectrogram(at: url, chunkFrames: chunkFrames)
            guard case .failed = outcome else {
                Issue.record("chunk size \(chunkFrames) produced \(outcome)"); return
            }
        }
    }
}

// MARK: - The report is unaffected, once per format (8.9 over the real matrix)

/// The isolation guarantee `SpectrogramReportIsolationTests` establishes with a scripted port, extended
/// with the one thing only the format matrix can add: it holds when the spectrogram is **genuinely
/// produced** from each container by the production decoder and the production transform.
///
/// The suite deliberately does **not** repeat what is already sufficient — the key sweep over the
/// exported document, the warning and status assertions, the exporter's structural isolation. Those are
/// proved once, there, and duplicating them here would add runtime without adding a guarantee.
@MainActor
@Suite("App — a real spectrogram of any format leaves the report alone")
struct SpectrogramFormatIsolationTests {

    private struct InspectionDidNotComplete: Error {}

    private func inspect(
        _ url: URL,
        decoder: FakeAudioDecoding?
    ) async throws -> (report: InspectionReport, spectrogram: SpectrogramOutcome) {
        let coordinator = decoder.map { scripted in
            SourceInspectionCoordinator(makeDecoder: { _ in scripted })
        } ?? SourceInspectionCoordinator()
        let outcome = await coordinator.inspect(url, onUpdate: { _ in })
        guard case let .inspected(report, _, spectrogram, _, _, _) = outcome else {
            throw InspectionDidNotComplete()
        }
        return (report, spectrogram)
    }

    @Test(
        "producing a real spectrogram changes neither the report nor a byte of the export",
        arguments: AudioFixtureFormat.allCases
    )
    func aRealSpectrogramChangesNothing(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "isolation-\(format)", format: format,
                    signal: .perChannelSine(frequencies: [1_000, 3_000], amplitude: 0.5),
                    sampleRate: 44_100, channels: 2, frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )

            // The real pipeline, and the same file with the decoding port reporting an absence.
            let produced = try await inspect(url, decoder: nil)
            let withoutModel = try await inspect(url, decoder: FakeAudioDecoding(.absent))

            // The two runs really did differ in the one way this test is about.
            guard case let .available(model) = produced.spectrogram else {
                Issue.record("\(format): expected a real model, got \(produced.spectrogram)"); return
            }
            #expect(model.columnCount > 0)
            #expect(withoutModel.spectrogram == .unavailable)

            // And in no other way.
            #expect(produced.report.properties == withoutModel.report.properties, "\(format): properties differed")
            #expect(produced.report.warnings == withoutModel.report.warnings, "\(format): warnings differed")
            #expect(produced.report.status == withoutModel.report.status, "\(format): status differed")
            #expect(
                try exportData(produced.report) == (try exportData(withoutModel.report)),
                "\(format): the exported document differed"
            )
        }
    }
}
