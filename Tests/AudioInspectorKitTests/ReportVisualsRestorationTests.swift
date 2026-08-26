import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
@testable import AudioInspectorApp
@testable import FeatureAnalysis
@testable import FeatureImport

// Group 6's cost claim, measured rather than argued: **going back to the single drawings reads values
// the flow already holds.** Two real files, the real coordinator, the real decoder, and a counter at the
// boundary that opens a decode.
//
// It also drives the transitions that take a pair away — dismissed, cancelled before it settles, and
// ended by a new primary inspection — and asserts which drawings the surface presents at each step.

@MainActor
@Suite("App — the single drawings come back without reading anything again")
struct ReportVisualsRestorationTests {

    private func coordinatorAction(for url: URL, counting counts: ProductionReadCounts) -> SourceInspectionAction {
        { onUpdate in
            let coordinator = SourceInspectionCoordinator(makeDecoder: { url in
                counts.decodersMade += 1
                return CountingDecoder(wrapped: AVFoundationAudioDecoder(resolveURL: { _ in url }), counts: counts)
            })
            return await coordinator.inspect(url, onUpdate: onUpdate)
        }
    }

    private func spec(_ name: String, rate: Double) -> AudioFixtureSpec {
        productionSpec(
            name, productionProgramme(to: 12_000), rate: rate, channels: 1,
            frames: AVAudioFrameCount(rate)
        )
    }

    /// Which drawings the surface would present right now, from the flow's own state.
    private func visuals(_ flow: ImportFlowModel) -> ReportVisuals? {
        guard case let .report(presentation) = flow.state else { return nil }
        return RootView.reportVisuals(for: presentation, in: flow.comparison)
    }

    private func isPaired(_ visuals: ReportVisuals?) -> Bool {
        if case .paired = visuals { true } else { false }
    }

    // MARK: - 6.4

    @Test("dismissing the comparison restores the single drawings, and reads nothing again")
    func dismissRestoresWithoutReadingAgain() async throws {
        try await withTemporaryDirectory { directory in
            let primaryURL = try writeAudioFixture(spec("visual-mode-first", rate: 44_100), in: directory)
            let comparedURL = try writeAudioFixture(spec("visual-mode-second", rate: 48_000), in: directory)
            let counts = ProductionReadCounts()

            let flow = ImportFlowModel(action: coordinatorAction(for: primaryURL, counting: counts))
            await flow.selectAndInspect()

            // Before any comparison: the first file's own drawings.
            #expect(!isPaired(visuals(flow)), "a lone report presented a pair")
            #expect(counts.decodeCalls == 1)

            await flow.compare(using: coordinatorAction(for: comparedURL, counting: counts))

            // The pair settled, and it stands in for the single drawings.
            guard let paired = visuals(flow), isPaired(paired) else {
                Issue.record("the settled pair did not reach the surface: \(String(describing: visuals(flow)))")
                return
            }
            #expect(paired.waveformSections.count == 1)
            #expect(paired.spectrogramSections.count == 1)
            #expect(counts.decodersMade == 2, "\(counts.decodersMade) decoders for two files")
            #expect(counts.decodeCalls == 2, "\(counts.decodeCalls) reads for two files")

            let decodersAtPeak = counts.decodersMade
            let readsAtPeak = counts.decodeCalls

            flow.dismissComparison()

            // The single drawings are back, and nothing was read or produced to bring them back.
            guard let restored = visuals(flow), !isPaired(restored) else {
                Issue.record("the single drawings did not come back"); return
            }
            guard case .singleWaveform = restored.waveformSections[0],
                  case .singleSpectrogram = restored.spectrogramSections[0]
            else {
                Issue.record("what came back was not the first file's own drawings"); return
            }
            #expect(counts.decodersMade == decodersAtPeak, "restoring made a decoder")
            #expect(counts.decodeCalls == readsAtPeak, "restoring read a file again")
            #expect(counts.decodersMade == 2)
            #expect(counts.decodeCalls == 2)

            // And the first file's drawings are the ones its own inspection produced, not new ones.
            guard case let .report(presentation) = flow.state else {
                Issue.record("no report on screen"); return
            }
            guard case .available = presentation.waveform, case .available = presentation.spectrogram else {
                Issue.record("the first file's drawings were lost: \(presentation.waveform), \(presentation.spectrogram)")
                return
            }
        }
    }

    // MARK: - The other ways a pair goes away

    @Test("a second inspection cancelled before it settles leaves the single drawings standing")
    func cancellationLeavesTheSingles() async {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(Self.report("a.wav"))])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        action.finish(.inspected(Self.report("a.wav"), analyses: Self.analyses))
        await running.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        #expect(!isPaired(visuals(flow)), "a comparison that has not settled presented a pair")
        compared.finish(.cancelled)
        await comparing.value

        #expect(!isPaired(visuals(flow)), "a cancelled comparison presented a pair")
    }

    @Test("a new primary inspection takes the pair away")
    func aNewPrimaryInspectionEndsThePair() async {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(Self.report("a.wav"))])
        let flow = ImportFlowModel(action: action.run)
        let first = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        action.finish(.inspected(Self.report("a.wav"), analyses: Self.analyses))
        await first.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(.inspected(Self.report("b.wav"), analyses: Self.analyses))
        await comparing.value
        #expect(isPaired(visuals(flow)), "the settled pair did not reach the surface")

        // The same action serves the second selection: the flow takes its action once, at construction.
        let next = Task { await flow.selectAndInspect() }
        action.finish(.inspected(Self.report("z.wav"), analyses: Self.analyses))
        await next.value

        #expect(!isPaired(visuals(flow)), "the pair survived a new primary inspection")
    }

    // MARK: - Support

    private static func report(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 2_048, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(container: .available("wav")),
            warnings: [],
            status: .completed
        )
    }

    /// A settled inspection with both drawings and a real description, so a pair can form.
    private static let analyses = InspectionAnalyses(
        waveform: .available(WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -0.5, maximum: 0.5)!], frameCount: 2_048, channelCount: 2
        )!),
        spectrogram: .available(Spectrogram(
            values: [-30, -40], columnCount: 1, bandCount: 2,
            sampleRate: 44_100, frameCount: 2_048, channelCount: 2
        )!),
        signalLevelMetrics: .unavailable,
        truePeak: .unavailable,
        loudness: .unavailable,
        significantBandwidth: .unavailable,
        stream: PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 88_200)!
    )
}
