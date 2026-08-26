import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
@testable import AudioInspectorApp
@testable import FeatureImport

// Group 2's cost claim, measured rather than argued: **retaining the compared file's pictures costs no
// read.** Two real files, the real coordinator, the real decoder, and a counter at the boundary that
// opens a decode.
//
// It also answers the question no value test can: whether the stream description the flow keeps is the
// one the decoder reported. Anything derived from the report, the envelope or the spectral model would
// be a reconstruction — and a reconstruction that happened to agree would prove nothing.

@MainActor
@Suite("Feature — the retained visuals come from the read that already happened")
struct ComparedVisualsProductionReachTests {

    private final class CapturedOutcomes {
        var compared: (report: InspectionReport, analyses: InspectionAnalyses)?
    }

    /// A `SourceInspectionAction` running the **real** coordinator over one file, with the decoder
    /// wrapped only so the read can be counted. It changes nothing about the read itself.
    private func coordinatorAction(
        for url: URL, counting counts: ProductionReadCounts, into captured: CapturedOutcomes?
    ) -> SourceInspectionAction {
        { onUpdate in
            let coordinator = SourceInspectionCoordinator(makeDecoder: { url in
                counts.decodersMade += 1
                return CountingDecoder(wrapped: AVFoundationAudioDecoder(resolveURL: { _ in url }), counts: counts)
            })
            let outcome = await coordinator.inspect(url, onUpdate: onUpdate)
            if case let .inspected(report, analyses) = outcome { captured?.compared = (report, analyses) }
            return outcome
        }
    }

    private func spec(_ name: String, rate: Double) -> AudioFixtureSpec {
        productionSpec(
            name, productionProgramme(to: 12_000), rate: rate, channels: 1,
            frames: AVAudioFrameCount(rate)
        )
    }

    @Test("two files, two reads, and the compared file's pictures are kept from its own")
    func twoFilesTwoReads() async throws {
        try await withTemporaryDirectory { directory in
            // Deliberately different rates, so "the second file's description" is distinguishable from
            // the first's rather than merely plausible.
            let primaryURL = try writeAudioFixture(spec("visual-primary", rate: 44_100), in: directory)
            let comparedURL = try writeAudioFixture(spec("visual-compared", rate: 48_000), in: directory)

            let counts = ProductionReadCounts()
            let captured = CapturedOutcomes()

            let flow = ImportFlowModel(action: coordinatorAction(
                for: primaryURL, counting: counts, into: nil
            ))
            await flow.selectAndInspect()
            await flow.compare(using: coordinatorAction(
                for: comparedURL, counting: counts, into: captured
            ))

            // **One decoder and one read per file, and not one more.** Retention adds neither.
            #expect(counts.decodersMade == 2, "the two files were given \(counts.decodersMade) decoders")
            #expect(counts.decodeCalls == 2, "the two files' samples were read \(counts.decodeCalls) times")

            let compared = try #require(captured.compared, "the compared file was not inspected")
            guard let retained = flow.comparedVisuals else {
                Issue.record("the compared file's visuals were discarded by the flow"); return
            }

            // **Reuse, not recomputation**: the retained artefacts are the values that inspection
            // produced, compared as values rather than trusted because no second call was seen.
            guard case let .available(envelope) = compared.analyses.waveform,
                  case let .available(model) = compared.analyses.spectrogram
            else {
                Issue.record("""
                the compared file produced no drawing to retain — \
                waveform \(compared.analyses.waveform), spectrogram \(compared.analyses.spectrogram)
                """)
                return
            }
            #expect(retained.waveform == .available(envelope))
            #expect(retained.spectrogram == .available(model))

            // **The description is the decoder's own**, not a number rebuilt from anything else.
            let reported = try #require(counts.reportedStreams.last, "the decoder reported no stream")
            #expect(retained.stream == reported)
            #expect(retained.stream?.sampleRate == 48_000, "the retained description is not the second file's")
            #expect(counts.reportedStreams.first?.sampleRate == 44_100, "the two reads were not distinguishable")
        }
    }

    /// **The published pair, over two real files.** Both sides come from the reads that already
    /// happened, each carrying the description its own decoder reported, and neither file is read twice.
    @Test("the published pair is built from the two reads that already happened")
    func thePublishedPairIsBuiltFromTheTwoReads() async throws {
        try await withTemporaryDirectory { directory in
            let primaryURL = try writeAudioFixture(spec("pair-primary", rate: 44_100), in: directory)
            let comparedURL = try writeAudioFixture(spec("pair-compared", rate: 48_000), in: directory)
            let counts = ProductionReadCounts()

            let flow = ImportFlowModel(action: coordinatorAction(for: primaryURL, counting: counts, into: nil))
            await flow.selectAndInspect()
            await flow.compare(using: coordinatorAction(for: comparedURL, counting: counts, into: nil))

            // **One decoder and one read per file, with the pair published.** Building it costs neither.
            #expect(counts.decodersMade == 2, "the two files were given \(counts.decodersMade) decoders")
            #expect(counts.decodeCalls == 2, "the two files' samples were read \(counts.decodeCalls) times")

            guard case let .ready(technical, _, visuals) = flow.comparison else {
                Issue.record("the flow published \(flow.comparison)"); return
            }
            guard let pair = visuals else {
                Issue.record("no pair was published for two real files"); return
            }

            // Each side's description is the one **that file's** decoder reported, told apart by rate.
            #expect(counts.reportedStreams.count == 2)
            #expect(pair.first.stream == counts.reportedStreams.first)
            #expect(pair.second.stream == counts.reportedStreams.last)
            #expect(pair.first.stream?.sampleRate == 44_100)
            #expect(pair.second.stream?.sampleRate == 48_000)

            // The published sides are the values the two inspections produced — reuse, not a lookalike.
            guard case let .report(presentation) = flow.state else {
                Issue.record("expected a report on screen, got \(flow.state)"); return
            }
            #expect(pair.first == presentation.settledVisuals)
            #expect(pair.second == flow.comparedVisuals)

            // And the three halves of the comparison describe the same two files.
            #expect(technical.first.file.displayName == "pair-primary.wav")
            #expect(technical.second.file.displayName == "pair-compared.wav")
        }
    }

    /// The first file keeps its own pictures where they always were, and the retained side is the other
    /// one — over real files, not fixtures chosen to look different.
    @Test("the first file's own drawings are untouched by the second file's retention")
    func theFirstFileKeepsItsOwn() async throws {
        try await withTemporaryDirectory { directory in
            let primaryURL = try writeAudioFixture(spec("visual-first", rate: 44_100), in: directory)
            let comparedURL = try writeAudioFixture(spec("visual-second", rate: 48_000), in: directory)
            let counts = ProductionReadCounts()

            let flow = ImportFlowModel(action: coordinatorAction(for: primaryURL, counting: counts, into: nil))
            await flow.selectAndInspect()

            guard case let .report(before) = flow.state else {
                Issue.record("expected a report on screen, got \(flow.state)"); return
            }
            guard case .available = before.spectrogram else {
                Issue.record("the primary file produced no spectrogram: \(before.spectrogram)"); return
            }

            await flow.compare(using: coordinatorAction(for: comparedURL, counting: counts, into: nil))

            guard case let .report(after) = flow.state else {
                Issue.record("expected a report on screen, got \(flow.state)"); return
            }
            #expect(after.waveform == before.waveform)
            #expect(after.spectrogram == before.spectrogram)
            #expect(flow.comparedVisuals?.stream?.sampleRate == 48_000)
        }
    }
}
