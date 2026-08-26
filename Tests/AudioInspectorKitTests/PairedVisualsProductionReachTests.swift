import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
@testable import AudioInspectorApp
@testable import FeatureAnalysis
@testable import FeatureImport

// Group 8's subject: **the whole path exists, and it costs one read per file.**
//
// Every value asserted here came out of two real files:
//
//     file → AVFoundationAudioDecoder → SourceInspectionCoordinator → InspectionAnalyses
//          → the flow's retention → PairedVisuals → PairedWaveformAxis / PairedSpectrogramAxes
//          → ReportVisuals → PairedVisualsCopy
//
// Nothing here builds an envelope, a spectral model or a stream description. The artefacts the pair
// carries are compared against the ones **those same inspections produced**, captured at the
// coordinator's own boundary, so *reuse* is observed rather than inferred from a lookalike.

@MainActor
@Suite("App — the paired drawings reach the surface from the real read")
struct PairedVisualsProductionReachTests {

    /// What one real inspection produced, captured at the seam the flow takes it from.
    private final class Captured {
        var outcome: SourceInspectionOutcome?
        /// Whether any sample had been read at the moment the report arrived.
        var readHadStartedWhenTheReportArrived: Bool?

        var analyses: InspectionAnalyses? {
            guard case let .inspected(_, analyses)? = outcome else { return nil }
            return analyses
        }

        var report: InspectionReport? {
            guard case let .inspected(report, _)? = outcome else { return nil }
            return report
        }
    }

    /// A `SourceInspectionAction` running the **real** coordinator over one file, with the decoder
    /// wrapped only so its use can be counted. It changes nothing about the read.
    ///
    /// **One counter per file**, so *one decoder and one read per file* is asserted per file rather than
    /// inferred from a total that two files could share unevenly.
    private func action(
        for url: URL, counting counts: ProductionReadCounts, into captured: Captured
    ) -> SourceInspectionAction {
        { onUpdate in
            let coordinator = SourceInspectionCoordinator(makeDecoder: { url in
                counts.decodersMade += 1
                return CountingDecoder(wrapped: AVFoundationAudioDecoder(resolveURL: { _ in url }), counts: counts)
            })
            let outcome = await coordinator.inspect(url) { update in
                if case .report = update {
                    // The requirement itself: not "before the other updates", but before a sample exists.
                    captured.readHadStartedWhenTheReportArrived = counts.decodeCalls > 0
                }
                onUpdate(update)
            }
            captured.outcome = outcome
            return outcome
        }
    }

    /// Two files that differ in **rate, length and level**, so a side swapped anywhere on the path shows
    /// up as a wrong number rather than as a coincidence.
    private func firstSpec() -> AudioFixtureSpec {
        productionSpec(
            "reach-first", productionProgramme(to: 12_000, level: 0.01),
            rate: 44_100, channels: 1, frames: 44_100 // 1.0 s
        )
    }

    private func secondSpec() -> AudioFixtureSpec {
        productionSpec(
            "reach-second", productionProgramme(to: 18_000, level: 0.04),
            rate: 48_000, channels: 1, frames: 96_000 // 2.0 s
        )
    }

    /// One real comparison, driven to a settled pair.
    private func comparedPair(in directory: URL) async throws -> (
        flow: ImportFlowModel,
        first: (counts: ProductionReadCounts, captured: Captured),
        second: (counts: ProductionReadCounts, captured: Captured)
    ) {
        let firstURL = try writeAudioFixture(firstSpec(), in: directory)
        let secondURL = try writeAudioFixture(secondSpec(), in: directory)
        let firstCounts = ProductionReadCounts()
        let secondCounts = ProductionReadCounts()
        let firstCaptured = Captured()
        let secondCaptured = Captured()

        let flow = ImportFlowModel(action: action(for: firstURL, counting: firstCounts, into: firstCaptured))
        await flow.selectAndInspect()
        await flow.compare(using: action(for: secondURL, counting: secondCounts, into: secondCaptured))

        return (flow, (firstCounts, firstCaptured), (secondCounts, secondCaptured))
    }

    private func settledPair(_ flow: ImportFlowModel) -> PairedVisuals? {
        guard case let .ready(_, _, paired) = flow.comparison else { return nil }
        return paired
    }

    // MARK: - 8.1 — one decoder and one read per file, with the pair retained

    @Test("two real files, two decoders, two reads, and a settled pair")
    func oneReadPerFile() async throws {
        try await withTemporaryDirectory { directory in
            let (flow, first, second) = try await comparedPair(in: directory)

            // Per file, over the **whole** operation: report, measurements, waveform, spectrogram and
            // the pair. Nothing is reset between phases.
            #expect(first.counts.decodersMade == 1, "the first file was given \(first.counts.decodersMade) decoders")
            #expect(first.counts.decodeCalls == 1, "the first file's samples were read \(first.counts.decodeCalls) times")
            #expect(second.counts.decodersMade == 1, "the second file was given \(second.counts.decodersMade) decoders")
            #expect(second.counts.decodeCalls == 1, "the second file's samples were read \(second.counts.decodeCalls) times")
            #expect(first.counts.decodersMade + second.counts.decodersMade == 2)
            #expect(first.counts.decodeCalls + second.counts.decodeCalls == 2)

            // And the pair really settled, so the counts above are the cost of a finished comparison.
            guard let paired = settledPair(flow) else {
                Issue.record("no pair settled: \(flow.comparison)"); return
            }
            guard case .available = paired.first.waveform, case .available = paired.first.spectrogram,
                  case .available = paired.second.waveform, case .available = paired.second.spectrogram
            else {
                Issue.record("the pair settled without drawings: \(paired)"); return
            }
        }
    }

    // MARK: - 8.2 — the pair carries what those inspections produced

    @Test("each side's drawings in the pair are the values that file's own inspection produced")
    func theArtefactsAreReused() async throws {
        try await withTemporaryDirectory { directory in
            let (flow, first, second) = try await comparedPair(in: directory)
            guard let paired = settledPair(flow),
                  let firstAnalyses = first.captured.analyses,
                  let secondAnalyses = second.captured.analyses
            else {
                Issue.record("the comparison did not complete"); return
            }

            // Reuse, compared as values against what the coordinator returned — never against an
            // artefact rebuilt here.
            guard case let .available(firstEnvelope) = firstAnalyses.waveform,
                  case let .available(firstModel) = firstAnalyses.spectrogram,
                  case let .available(secondEnvelope) = secondAnalyses.waveform,
                  case let .available(secondModel) = secondAnalyses.spectrogram
            else {
                Issue.record("an inspection produced no drawing to reuse"); return
            }
            #expect(paired.first.waveform == .available(firstEnvelope))
            #expect(paired.first.spectrogram == .available(firstModel))
            #expect(paired.second.waveform == .available(secondEnvelope))
            #expect(paired.second.spectrogram == .available(secondModel))

            // The stream descriptions are those inspections' own.
            #expect(paired.first.stream == firstAnalyses.stream)
            #expect(paired.second.stream == secondAnalyses.stream)
            #expect(paired.first.stream?.sampleRate == 44_100)
            #expect(paired.second.stream?.sampleRate == 48_000)
            #expect(paired.first.stream?.frameCount == 44_100)
            #expect(paired.second.stream?.frameCount == 96_000)

            // **No swap.** The two files differ in rate, length and content, so a side placed on the
            // wrong lane is a wrong number rather than a coincidence.
            #expect(firstEnvelope != secondEnvelope, "the fixtures no longer discriminate")
            #expect(firstModel != secondModel, "the fixtures no longer discriminate")
            #expect(paired.first.waveform != paired.second.waveform)
            #expect(paired.first.spectrogram != paired.second.spectrogram)
            #expect(paired.first.stream != paired.second.stream)
        }
    }

    // MARK: - 8.4 — one pair of inspections, three answers about it

    @Test("the pair, the technical comparison and the measurement comparison describe the same two files")
    func everythingDescribesTheSamePair() async throws {
        try await withTemporaryDirectory { directory in
            let (flow, first, second) = try await comparedPair(in: directory)
            guard case let .ready(technical, measurements, paired) = flow.comparison,
                  let paired,
                  let firstReport = first.captured.report,
                  let secondReport = second.captured.report,
                  let firstAnalyses = first.captured.analyses,
                  let secondAnalyses = second.captured.analyses
            else {
                Issue.record("the comparison did not complete: \(flow.comparison)"); return
            }

            // The technical half is the two reports those inspections returned.
            #expect(technical == FileComparison(first: firstReport, second: secondReport))
            #expect(technical.first.file.displayName == "reach-first.wav")
            #expect(technical.second.file.displayName == "reach-second.wav")

            // The measurement half is what the domain builds from the two bundles they settled on.
            guard let firstBundle = firstAnalyses.settledMeasurements,
                  let secondBundle = secondAnalyses.settledMeasurements
            else {
                Issue.record("a file settled no measurements"); return
            }
            #expect(measurements == MeasurementComparison(first: firstBundle, second: secondBundle))

            // The visual half is what those same inspections drew.
            #expect(paired.first.stream == firstAnalyses.stream)
            #expect(paired.second.stream == secondAnalyses.stream)

            // And the three agree about which file is which: the rates run 44.1 then 48 everywhere.
            #expect(technical.first.properties.sampleRate == .available(44_100))
            #expect(technical.second.properties.sampleRate == .available(48_000))
            #expect(paired.first.stream?.sampleRate == 44_100)
            #expect(paired.second.stream?.sampleRate == 48_000)
            // The fixtures really are distinguishable to the measurements too.
            #expect(firstBundle.loudness != secondBundle.loudness, "the fixtures no longer discriminate")
        }
    }

    // MARK: - 8.5 — the report still precedes the read

    /// Not *before the other updates* — **before a sample exists**. Asked of the decoder at the moment
    /// each report arrived, for both inspections, and asserted against a read that really happened so
    /// the answer means something.
    @Test("both reports are handed over before their file's decoder is invoked")
    func theReportStillPrecedesTheRead() async throws {
        try await withTemporaryDirectory { directory in
            let (flow, first, second) = try await comparedPair(in: directory)

            #expect(
                first.captured.readHadStartedWhenTheReportArrived == false,
                "the first file's report was held back until its samples had been read"
            )
            #expect(
                second.captured.readHadStartedWhenTheReportArrived == false,
                "the second file's report was held back until its samples had been read"
            )
            #expect(first.counts.decodeCalls == 1, "the first file was never read, so this proved nothing")
            #expect(second.counts.decodeCalls == 1, "the second file was never read, so this proved nothing")

            // And the pair still settles afterwards: report-first did not cost the drawings.
            #expect(settledPair(flow) != nil)
        }
    }

    // MARK: - The whole path, end to end

    /// **Groups 1 to 7, reached from two real files.** Each stage is asserted on the value production
    /// actually produced, so no part of the path is only reachable through a constructor in a test.
    @Test("the settled contracts, the geometry and the words are all reached from the real read")
    func everyStageIsReachedFromProduction() async throws {
        try await withTemporaryDirectory { directory in
            let (flow, _, _) = try await comparedPair(in: directory)
            guard case let .report(presentation) = flow.state, let paired = settledPair(flow) else {
                Issue.record("no settled comparison on screen"); return
            }

            // Group 1 — the settled shapes, from a real inspection's outcome.
            #expect(paired.first.waveform != .unavailable)
            #expect(paired.first.stream != nil)

            // Group 4 — the time axis, from those two streams: 1.0 s against 2.0 s.
            let visuals = RootView.reportVisuals(for: presentation, in: flow.comparison)
            guard case let .paired(presented) = visuals else {
                Issue.record("the surface did not present the pair"); return
            }
            #expect(presented.waveform.axis?.sharedSeconds == 2)
            #expect(presented.waveform.axis?.first?.fraction == 0.5)
            #expect(presented.waveform.axis?.second?.fraction == 1)

            // Group 5 — the frequency axis: 22 050 against 24 000, shared at the higher.
            #expect(presented.spectrogram.axes?.sharedNyquist == 24_000)
            #expect(presented.spectrogram.axes?.first?.frequencyFraction == 22_050.0 / 24_000.0)
            #expect(presented.spectrogram.axes?.second?.frequencyFraction == 1)

            // Group 6 — the paired sections stand in, exactly one each.
            #expect(visuals.waveformSections.count == 1)
            #expect(visuals.spectrogramSections.count == 1)
            guard case .pairedWaveform = visuals.waveformSections[0],
                  case .pairedSpectrogram = visuals.spectrogramSections[0]
            else {
                Issue.record("the single sections were presented for a settled pair"); return
            }

            // Group 7 — the words, derived from those real states.
            let firstLane = PairedVisualsCopy.spectrogram(
                presented.spectrogram.first, for: .first,
                aboveItsNyquist: (presented.spectrogram.axes?.first?.outOfRangeFraction ?? 0) > 0
            )
            #expect(firstLane.attribution == ComparisonCopy.firstFile)
            #expect(firstLane.outOfRange == PairedVisualsCopy.outsideRepresentableRange)
            let secondLane = PairedVisualsCopy.spectrogram(
                presented.spectrogram.second, for: .second,
                aboveItsNyquist: (presented.spectrogram.axes?.second?.outOfRangeFraction ?? 0) > 0
            )
            #expect(secondLane.outOfRange == nil, "the higher-rate file was told it cannot represent its own range")
            // The shorter file's lane says its audio ends first; the longer one's does not.
            let firstWaveformLane = PairedVisualsCopy.waveform(
                presented.waveform.first, for: .first,
                beyondItsAudio: (presented.waveform.axis?.first?.remainderFraction ?? 0) > 0
            )
            #expect(firstWaveformLane.outOfRange == PairedVisualsCopy.outsideAudio)
        }
    }
}
