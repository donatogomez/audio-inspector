import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureImport

// Group 2's subject: **the compared file stops losing the pictures it already produced.**
//
// Nothing here pairs the two files, publishes anything, or touches `ComparisonState` — those are group
// 3's. What is asserted is narrower and entirely observable: what the flow retains, when it retains it,
// when it lets go, and that the stream description it keeps is the one the decoder reported rather than
// a number recomputed from something else.

@MainActor
@Suite("Feature — the compared file's visuals are retained, not discarded")
struct ComparedVisualsRetentionTests {

    // MARK: - Fixtures

    private func report(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 2_048,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(container: .available("wav")),
            warnings: [],
            status: .completed
        )
    }

    private func envelope(peak: Float) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -peak, maximum: peak)!],
            frameCount: 2_048,
            channelCount: 2
        )!
    }

    private func model(sampleRate: Double) -> Spectrogram {
        Spectrogram(
            values: [-30, -40], columnCount: 1, bandCount: 2,
            sampleRate: sampleRate, frameCount: 2_048, channelCount: 2
        )!
    }

    private func stream(sampleRate: Double, frameCount: Int = 2_048) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: sampleRate, channelCount: 2, frameCount: frameCount)!
    }

    private func analyses(
        stream: PCMStreamDescription?,
        waveform: WaveformOutcome,
        spectrogram: SpectrogramOutcome
    ) -> InspectionAnalyses {
        InspectionAnalyses(
            waveform: waveform, spectrogram: spectrogram,
            signalLevelMetrics: .unavailable, truePeak: .unavailable,
            loudness: .unavailable, significantBandwidth: .unavailable,
            stream: stream
        )
    }

    /// A settled second file with recognisable pictures, so "this one and not that one" can be observed
    /// rather than inferred from fields that merely stayed empty.
    private func settledSecond(
        _ name: String, peak: Float, sampleRate: Double
    ) -> (SourceInspectionOutcome, InspectionReport) {
        let second = report(name)
        return (
            .inspected(second, analyses: analyses(
                stream: stream(sampleRate: sampleRate),
                waveform: .available(envelope(peak: peak)),
                spectrogram: .available(model(sampleRate: sampleRate))
            )),
            second
        )
    }

    private func flowShowingAReport() async
        -> (ImportFlowModel, ImportFlowComparisonTests.ControllableAction, Task<Void, Never>) {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(report("a.wav"))])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        return (flow, action, running)
    }

    // MARK: - Retention

    @Test("a settled comparison retains the second file's pictures and its stream")
    func aSettledComparisonRetainsThem() async {
        let (flow, primaryAction, primaryRunning) = await flowShowingAReport()
        primaryAction.finish(.inspected(report("a.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .unavailable, spectrogram: .unavailable
        )))
        await primaryRunning.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let (outcome, _) = settledSecond("b.wav", peak: 0.75, sampleRate: 96_000)
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()

        // Nothing is retained until the second file has settled.
        #expect(flow.comparedVisuals == nil)

        compared.finish(outcome)
        await comparing.value

        guard let retained = flow.comparedVisuals else {
            Issue.record("the compared file's visuals were discarded"); return
        }
        #expect(retained.waveform == .available(envelope(peak: 0.75)))
        #expect(retained.spectrogram == .available(model(sampleRate: 96_000)))
        #expect(retained.stream == stream(sampleRate: 96_000))
    }

    /// Cancellation is not a settled answer. The file is not blamed for an operation the user replaced,
    /// so no absence is retained in its place.
    @Test("a cancelled second inspection retains nothing, and no absence stands in for it")
    func cancellationRetainsNothing() async {
        let (flow, primaryAction, primaryRunning) = await flowShowingAReport()
        primaryAction.finish(.inspected(report("a.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .unavailable, spectrogram: .unavailable
        )))
        await primaryRunning.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(.inspected(report("b.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .cancelled, spectrogram: .cancelled
        )))
        await comparing.value

        #expect(flow.comparedVisuals == nil)
    }

    /// An absence really is retained — it is a settled answer about the file, unlike a cancellation.
    @Test("an absent drawing is retained as an absence, not as nothing")
    func anAbsenceIsRetained() async {
        let (flow, primaryAction, primaryRunning) = await flowShowingAReport()
        primaryAction.finish(.inspected(report("a.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .unavailable, spectrogram: .unavailable
        )))
        await primaryRunning.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(.inspected(report("b.wav"), analyses: analyses(
            stream: nil, waveform: .unavailable, spectrogram: .unavailable
        )))
        await comparing.value

        #expect(flow.comparedVisuals?.waveform == .unavailable)
        #expect(flow.comparedVisuals?.spectrogram == .unavailable)
        #expect(flow.comparedVisuals?.stream == nil)
    }

    // MARK: - Letting go

    @Test("dismissing the comparison releases what was retained")
    func dismissReleases() async {
        let (flow, _) = await flowWithASettledComparison(peak: 0.5, sampleRate: 48_000)
        #expect(flow.comparedVisuals != nil)
        flow.dismissComparison()
        #expect(flow.comparedVisuals == nil)
    }

    @Test("a new comparison releases the previous one's pictures before it starts")
    func aNewComparisonReleases() async {
        let (flow, _) = await flowWithASettledComparison(peak: 0.5, sampleRate: 48_000)

        let second = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()

        // The previous comparison's pictures are gone the moment a new one starts, not when it settles.
        #expect(flow.comparedVisuals == nil)

        let (outcome, _) = settledSecond("c.wav", peak: 0.9, sampleRate: 44_100)
        second.finish(outcome)
        await comparing.value

        #expect(flow.comparedVisuals?.waveform == .available(envelope(peak: 0.9)))
    }

    @Test("a new primary inspection releases them")
    func aNewPrimaryInspectionReleases() async {
        let (flow, primaryAction) = await flowWithASettledComparison(peak: 0.5, sampleRate: 48_000)
        #expect(flow.comparedVisuals != nil)

        // The same action serves the second selection: the flow takes its action once, at construction.
        let running = Task { await flow.selectAndInspect() }
        primaryAction.finish(.inspected(report("z.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .unavailable, spectrogram: .unavailable
        )))
        await running.value

        #expect(flow.comparedVisuals == nil)
    }

    /// Dismissing the *picker* is not a statement about either file: the comparison that was on screen
    /// returns, and its pictures return with it. Retaining the measurements of one comparison beside the
    /// pictures of another is what this mirrors away.
    @Test("dismissing the picker restores the previous comparison's pictures")
    func cancellingThePickerRestores() async {
        let (flow, _) = await flowWithASettledComparison(peak: 0.5, sampleRate: 48_000)
        let beforeSecondAttempt = flow.comparedVisuals

        let second = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.cancelled)
        await comparing.value

        #expect(flow.comparedVisuals == beforeSecondAttempt)
        #expect(flow.comparedVisuals?.waveform == .available(envelope(peak: 0.5)))
    }

    // MARK: - What this must not disturb

    /// The first file's pictures stay exactly where they are, in its own presentation state. Nothing
    /// copies them into the comparison's storage (ADR-0025 §4).
    @Test("the first file's pictures are untouched, and are not copied anywhere")
    func theFirstFileIsUntouched() async {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [
            .report(report("a.wav")),
            .waveform(.available(envelope(peak: 0.1))),
            .spectrogram(.available(model(sampleRate: 44_100))),
        ])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        action.finish(.inspected(report("a.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100),
            waveform: .available(envelope(peak: 0.1)),
            spectrogram: .available(model(sampleRate: 44_100))
        )))
        await running.value

        guard case let .report(before) = flow.state else {
            Issue.record("expected a report on screen, got \(flow.state)"); return
        }

        let compared = ImportFlowComparisonTests.ControllableAction()
        let (outcome, _) = settledSecond("b.wav", peak: 0.75, sampleRate: 96_000)
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(outcome)
        await comparing.value

        guard case let .report(after) = flow.state else {
            Issue.record("expected a report on screen, got \(flow.state)"); return
        }
        #expect(after.waveform == before.waveform)
        #expect(after.spectrogram == before.spectrogram)
        // And the retained side is the second file's, never the first's.
        #expect(flow.comparedVisuals?.waveform == .available(envelope(peak: 0.75)))
        #expect(flow.comparedVisuals?.waveform != before.waveform.settledEquivalent)
    }

    /// The technical comparison is complete the moment the second report exists and must not wait for
    /// that file's pictures — the ordering retention could most plausibly have broken.
    @Test("the technical comparison still lands on the report, before any drawing settles")
    func theTechnicalComparisonStillLandsEarly() async {
        let (flow, primaryAction, primaryRunning) = await flowShowingAReport()
        primaryAction.finish(.inspected(report("a.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .unavailable, spectrogram: .unavailable
        )))
        await primaryRunning.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()

        let (outcome, secondReport) = settledSecond("b.wav", peak: 0.75, sampleRate: 96_000)
        compared.finish(sending: [.report(secondReport)], outcome)
        await comparing.value

        guard case let .ready(technical, _, _) = flow.comparison else {
            Issue.record("expected a ready comparison, got \(flow.comparison)"); return
        }
        #expect(technical.second.file.displayName == "b.wav")
    }

    // MARK: - Support

    private func flowWithASettledComparison(
        peak: Float, sampleRate: Double
    ) async -> (ImportFlowModel, ImportFlowComparisonTests.ControllableAction) {
        let (flow, primaryAction, primaryRunning) = await flowShowingAReport()
        primaryAction.finish(.inspected(report("a.wav"), analyses: analyses(
            stream: stream(sampleRate: 44_100), waveform: .unavailable, spectrogram: .unavailable
        )))
        await primaryRunning.value

        let compared = ImportFlowComparisonTests.ControllableAction()
        let (outcome, _) = settledSecond("b.wav", peak: peak, sampleRate: sampleRate)
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(outcome)
        await comparing.value
        return (flow, primaryAction)
    }
}

private extension WaveformState {
    /// The first file's state expressed as the settled answer, so a test can say *"and not that one"*
    /// without reaching for a second collapse.
    var settledEquivalent: SettledWaveform? { SettledWaveform(self) }
}
