import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp
@testable import FeatureAnalysis

/// **True peak and the clipped-sample count are two measurements, not one measurement and its
/// consequence.** This suite proves it on the same audio, through the same read, and all the way to the
/// words on screen.
///
/// The two answer different questions of different inputs:
///
/// - `clippedSampleCount` counts **stored** samples whose absolute value is at or beyond
///   `SignalLevelMetricsAccumulator.clippingThreshold` (1.0). It looks at the array the decoder handed
///   over and at nothing else.
/// - `TruePeakMeasurement` is the maximum of the waveform **reconstructed between** those samples, at
///   eight points per input sample. Phase 0 of that reconstruction is the exact identity, so the stored
///   samples are inside the set it maximises over — which is why `truePeak >= samplePeak` — but seven
///   of every eight points it examines are values no array position holds.
///
/// From those definitions alone, neither implies the other: a waveform can cross full scale between two
/// samples that both sit below it, and samples can sit at full scale for reasons a reconstruction does
/// not amplify. The cases below are the demonstration, and ADR-0019 is why the surface stops at
/// reporting them: a positive true peak is a **value**, never a flag, and an inference drawn from the
/// two together would belong to a finding with its own evidence and confidence — which does not exist.
@Suite("Analysis — true peak and clipped samples are independent")
struct TruePeakClippingIndependenceTests {

    // MARK: - Fixtures, generated from formulas rather than from a file

    /// A sine of amplitude `a`, whose continuous maximum is exactly `a` whatever the phase. The fade
    /// keeps the file's own boundary against silence from adding overshoot the amplitude does not
    /// explain — the same shape `TruePeakAccumulatorTests` already uses for the same reason.
    private func tone(
        frequency: Double, sampleRate: Double = 44_100, amplitude: Float, phase: Double,
        frames: Int = 44_100, fadeFrames: Int = 4_410
    ) -> [Float] {
        (0 ..< frames).map { n in
            let value = Double(amplitude) * sin(2 * .pi * frequency * Double(n) / sampleRate + phase)
            guard fadeFrames > 0 else { return Float(value) }
            let envelope: Double
            if n < fadeFrames {
                envelope = 0.5 - 0.5 * cos(.pi * Double(n) / Double(fadeFrames))
            } else if n >= frames - fadeFrames {
                envelope = 0.5 - 0.5 * cos(.pi * Double(frames - 1 - n) / Double(fadeFrames))
            } else {
                envelope = 1
            }
            return Float(value * envelope)
        }
    }

    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    /// Both measurements, taken from **one** read of the same samples — the production composition, not
    /// two hand-fed accumulators. If either result were derived from the other, this is the path it
    /// would have to travel through, so it is the path the evidence is gathered on.
    private func measureBoth(_ samples: [Float], chunkFrames: Int = 4_096) async throws
        -> (levels: SignalLevelMetrics, truePeak: TruePeakMeasurement)
    {
        let description = try #require(PCMStreamDescription(
            sampleRate: 44_100, channelCount: 1, frameCount: max(samples.count, 1)
        ))
        var chunks: [PCMChunk] = []
        var start = 0
        while start < samples.count {
            let end = min(start + chunkFrames, samples.count)
            chunks.append(try PCMChunk(startFrame: start, channels: [Array(samples[start ..< end])]))
            start = end
        }

        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: chunks)
        ).run(for: reference())

        guard case let .available(levels) = outcome.signalLevelMetrics,
              case let .available(truePeak) = outcome.truePeak else {
            Issue.record("the shared read did not produce both measurements: \(outcome.signalLevelMetrics), \(outcome.truePeak)")
            throw CancellationError()
        }
        return (levels, truePeak)
    }

    /// Every string both sections can show for a given pair of results.
    private func allText(levels: SignalLevelMetrics, truePeak: TruePeakMeasurement) -> [String] {
        let levelRows = SignalLevelMetricsCopy.rows(for: levels)
            .flatMap { [$0.name, $0.value, $0.detail, $0.accessibilityLabel].compactMap { $0 } }
        let peakRows = TruePeakCopy.rows(for: truePeak)
            .flatMap { [$0.name, $0.value, $0.detail, $0.accessibilityLabel].compactMap { $0 } }
        return levelRows + peakRows + [TruePeakCopy.method(for: truePeak)]
    }

    /// The vocabulary that would turn two coexisting facts into a diagnosis.
    private func expectNoDiagnosis(levels: SignalLevelMetrics, truePeak: TruePeakMeasurement) {
        // Multi-word phrases are safe to look for as substrings; single words are **not**, and this is
        // where a naive sweep goes wrong: "overs" is audio jargon for a clipped sample and is also
        // inside the entirely innocent "oversampling" that the method line legitimately contains.
        // Single words are therefore matched whole.
        let phrases = [
            "clipping detected", "inter-sample clipping", "intersample clipping", "is clipping",
            "too hot", "bad master", "poor quality", "exceeds full scale",
        ]
        let words: Set<String> = ["overs", "unsafe", "distorted", "clipping", "hot", "damaged"]
        for text in allText(levels: levels, truePeak: truePeak) {
            let lowered = text.lowercased()
            for phrase in phrases {
                #expect(!lowered.contains(phrase), "a diagnosis was drawn from the two facts, in: \(text)")
            }
            let found = Set(lowered.split { !$0.isLetter }.map(String.init)).intersection(words)
            #expect(found.isEmpty, "diagnosis word(s) \(found.sorted()) in: \(text)")
        }
    }

    private func decibels(_ value: Float) -> Double { 20 * log10(Double(value)) }

    // MARK: - Case A — zero clipped samples, and a true peak above full scale

    /// **The case this measurement exists for.** A sine of amplitude 1.2 sampled an eighth of a cycle
    /// off the crest: every stored sample sits at `1.2/√2 ≈ 0.85`, comfortably below full scale, while
    /// the waveform they describe reaches 1.2. The count of clipped samples is therefore a truthful
    /// **zero** at the same moment the true peak is truthfully **above** full scale.
    ///
    /// A surface that inferred one from the other would have to call this file either clipped (it has no
    /// clipped sample) or safely below full scale (its waveform is not). It says both facts and neither
    /// conclusion.
    @Test("zero clipped samples and a true peak above full scale coexist, and neither is derived")
    func caseAInterSamplePeakWithoutAnyClippedSample() async throws {
        let samples = tone(frequency: 11_025, amplitude: 1.2, phase: .pi / 4)
        let (levels, truePeak) = try await measureBoth(samples)

        let samplePeak = try #require(levels.overallPeakSample)
        let reconstructed = try #require(truePeak.overallTruePeak)

        // Every stored sample is below full scale — so the counter is right to report none.
        #expect(samplePeak < 1, "the fixture stored a sample at full scale, which is not this case")
        #expect(abs(decibels(samplePeak) - decibels(Float(1.2 / 2.0.squareRoot()))) < 0.05)
        #expect(levels.overallClippedSampleCount == 0)

        // And the waveform between them is above it — so the true peak is right to report more.
        #expect(reconstructed > 1, "the reconstruction did not exceed full scale: \(reconstructed)")
        #expect(abs(decibels(reconstructed) - decibels(1.2)) < 0.05)

        // The two facts, side by side, in the order of magnitude the definitions require.
        #expect(reconstructed > samplePeak)

        // On screen: a positive dBTP value beside a clipped count of zero, and no word joining them.
        let peakRow = try #require(TruePeakCopy.rows(for: truePeak).first)
        #expect(try #require(peakRow.value).hasPrefix("+"), "a true peak above full scale lost its sign")
        let clippedRow = try #require(SignalLevelMetricsCopy.rows(for: levels).first { $0.name == "Clipped samples" })
        #expect(clippedRow.value == "0")
        expectNoDiagnosis(levels: levels, truePeak: truePeak)
    }

    // MARK: - Case B — clipped samples present, and a true peak at or above full scale

    /// Both facts are true of this file, and they are still two facts. The tone reaches full scale on
    /// stored samples, so the counter finds them; the reconstruction is at least as large, because phase
    /// 0 is the identity. **Coexistence is not causation**, and nothing here concludes anything from the
    /// pair.
    @Test("clipped samples and a true peak at or above full scale coexist as two separate facts")
    func caseBBothPresentAndStillSeparate() async throws {
        let samples = tone(frequency: 997, amplitude: 1.2, phase: 0)
        let (levels, truePeak) = try await measureBoth(samples)

        let samplePeak = try #require(levels.overallPeakSample)
        let reconstructed = try #require(truePeak.overallTruePeak)

        #expect(levels.overallClippedSampleCount > 0, "the fixture stored no sample at full scale")
        #expect(samplePeak >= 1)
        #expect(reconstructed >= 1)
        // The structural relationship, and the only one asserted anywhere: the stored samples are inside
        // the set the maximum is taken over.
        #expect(reconstructed >= samplePeak)

        // Neither value moved because the other exists: each equals what its own accumulator produces
        // from the same samples with the other absent entirely.
        var soloLevels = try #require(SignalLevelMetricsAccumulator(channelCount: 1))
        var soloPeak = try #require(TruePeakAccumulator(channelCount: 1))
        let whole = try PCMChunk(startFrame: 0, channels: [samples])
        soloLevels.accumulate(whole)
        soloPeak.accumulate(whole)
        let soloPeakResult = soloPeak.finish()
        let soloLevelsResult = try #require(soloLevels.finish())
        #expect(soloLevelsResult.overallClippedSampleCount == levels.overallClippedSampleCount)
        #expect(try #require(soloPeakResult).overallTruePeak == reconstructed)

        expectNoDiagnosis(levels: levels, truePeak: truePeak)
    }

    // MARK: - Case C — neither

    /// A quiet file: nothing at full scale and nothing above it. The mirror of case A, and the reason
    /// case A cannot be explained by the fixture generator alone — the same generator produces a file
    /// where both measurements stay low.
    @Test("a quiet file reports no clipped samples and a true peak below full scale")
    func caseCNeither() async throws {
        let samples = tone(frequency: 997, amplitude: 0.5, phase: 0)
        let (levels, truePeak) = try await measureBoth(samples)

        let samplePeak = try #require(levels.overallPeakSample)
        let reconstructed = try #require(truePeak.overallTruePeak)

        #expect(levels.overallClippedSampleCount == 0)
        #expect(samplePeak < 1)
        #expect(reconstructed < 1)
        #expect(abs(decibels(reconstructed) - decibels(0.5)) < 0.05)

        // No special wording anywhere, and the value reads as an ordinary negative dBTP figure.
        let peakRow = try #require(TruePeakCopy.rows(for: truePeak).first)
        #expect(try #require(peakRow.value).hasPrefix("-"))
        expectNoDiagnosis(levels: levels, truePeak: truePeak)
    }

    // MARK: - Measured silence, which is not the absence of a measurement

    /// **A silent file was measured**, and both measurements say so with real values: zero clipped
    /// samples, and a true peak of exactly zero that the surface floors rather than calling absent.
    /// Kept apart from the case below because collapsing them would lose the distinction both domain
    /// types were built to preserve.
    @Test("measured silence reports a real zero from both, and the true peak floors rather than absent")
    func measuredSilenceIsAMeasurement() async throws {
        let samples = [Float](repeating: 0, count: 8_192)
        let (levels, truePeak) = try await measureBoth(samples)

        #expect(levels.overallClippedSampleCount == 0)
        #expect(levels.overallPeakSample == 0, "a measured silence lost its computed zero")
        #expect(truePeak.overallTruePeak == 0, "a measured silence was reported as no measurement")
        #expect(truePeak.channels.allSatisfy { $0.sampleCount > 0 })

        let peakRow = try #require(TruePeakCopy.rows(for: truePeak).first)
        #expect(peakRow.value == "-120.00 dBTP")
        #expect(peakRow.detail != TruePeakCopy.notComputable)
    }

    /// **No frames at all is a different thing**, and each measurement keeps its own semantics for it:
    /// the true peak has no maximum to report and says so; the clipped count is still a defined zero,
    /// because counting nothing genuinely yields none.
    @Test("a stream with no frames leaves the true peak absent while the clipped count stays defined")
    func zeroFramesIsAbsenceNotSilence() async throws {
        let (levels, truePeak) = try await measureBoth([])

        #expect(truePeak.overallTruePeak == nil, "an unmeasured file reported a maximum")
        #expect(truePeak.channels.allSatisfy { $0.sampleCount == 0 })
        #expect(levels.overallPeakSample == nil, "an unmeasured file reported a peak sample")
        #expect(levels.overallClippedSampleCount == 0, "the clipped count lost its defined zero")

        let peakRow = try #require(TruePeakCopy.rows(for: truePeak).first)
        #expect(peakRow.value == nil)
        #expect(peakRow.detail == TruePeakCopy.notComputable)
        // The two zero-ish cases must not read alike.
        let silent = try await measureBoth([Float](repeating: 0, count: 8_192))
        let silentRow = try #require(TruePeakCopy.rows(for: silent.truePeak).first)
        #expect(silentRow.value != peakRow.value)
    }

    // MARK: - Non-derivation, at the seam where a coupling would have to live

    /// **The one place both measurements meet is a chunk being handed to each in turn**, and what
    /// travels there is the audio, never a result. This drives the production composition and then
    /// compares each outcome against the same accumulator run **alone**, with the other never
    /// constructed: if either result were informed by the other, one of these equalities would break.
    ///
    /// Swift cannot be asked to prove a type has no member, so this proves the observable consequence
    /// instead, which is the property that actually matters.
    @Test("neither measurement changes when the other is present")
    func neitherResultDependsOnTheOtherExisting() async throws {
        // Case A's fixture: the one where a coupling would be most tempting and most visible.
        let samples = tone(frequency: 11_025, amplitude: 1.2, phase: .pi / 4)
        let shared = try await measureBoth(samples)

        var levelsAlone = try #require(SignalLevelMetricsAccumulator(channelCount: 1))
        var peakAlone = try #require(TruePeakAccumulator(channelCount: 1))
        var start = 0
        while start < samples.count {
            let end = min(start + 4_096, samples.count)
            let chunk = try PCMChunk(startFrame: start, channels: [Array(samples[start ..< end])])
            levelsAlone.accumulate(chunk)
            peakAlone.accumulate(chunk)
            start = end
        }
        let peakAloneResult = peakAlone.finish()

        // Value for value, not merely "close": sharing a read fed them the same audio and nothing else.
        #expect(try #require(levelsAlone.finish()) == shared.levels)
        #expect(try #require(peakAloneResult) == shared.truePeak)
    }

    /// The clipping threshold is the **stored-sample** rule and nothing else touches it: it is not a
    /// dBTP threshold, and no true peak value is compared against it anywhere.
    @Test("the clipping threshold governs stored samples only")
    func theClippingThresholdIsAboutStoredSamplesOnly() throws {
        #expect(SignalLevelMetricsAccumulator.clippingThreshold == 1.0)
        // At the threshold counts, below it does not — asserted through the public accumulator rather
        // than its internals, so this is the rule as callers actually experience it.
        #expect(try clippedCount(of: [0.99, -0.99]) == 0)
        #expect(try clippedCount(of: [1.0, -1.0]) == 2, "a sample exactly at full scale must count")
        #expect(try clippedCount(of: [1.2, -0.5]) == 1)
    }

    private func clippedCount(of samples: [Float]) throws -> Int {
        var accumulator = try #require(SignalLevelMetricsAccumulator(channelCount: 1))
        accumulator.accumulate(try PCMChunk(startFrame: 0, channels: [samples]))
        return try #require(accumulator.finish()).overallClippedSampleCount
    }
}
