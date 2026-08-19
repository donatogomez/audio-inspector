import AudioInspectorDomain
import FeatureImport
import Foundation
import Testing

// `InspectionAnalyses` as a **unit of operation**: the bundle a superseded inspection produces is
// accepted or rejected whole, and never merged field-by-field into the one on screen.
//
// The existing stale tests — `SpectrogramFlowStateTests.aStaleSpectrogramIsDropped` and its signal
// level metrics counterpart — assert the weaker property that a late result does not land while the
// current operation is still `.loading`. That reads "still loading" as evidence of "did not land",
// which cannot distinguish a field that was protected from one that simply had nothing to overwrite.
// These assert the stronger one: with **six deliberately distinguishable analyses per operation**, the
// settled presentation is entirely B, so any mixture — B's report with A's bandwidth, B's waveform with
// A's loudness — is observable rather than inferred.
//
// Every sequence is driven by explicit signals on a scripted action. No sleeps, no polling, no
// `Task.yield()` as synchronisation.

/// An action whose report and all six analyses are released by the test, one at a time.
///
/// The same handshake the two existing flow suites use, extended to the six analyses this needs:
/// `release` returns only once the handler has actually been called, which is a real happens-before
/// rather than a hope about how two main-actor tasks are scheduled.
@MainActor
private final class SteppedAction {
    let report: InspectionReport
    private var pending: [InspectionUpdate] = []
    private var pendingOutcome: SourceInspectionOutcome?
    private var gate: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var applied: CheckedContinuation<Void, Never>?
    private(set) var runCount = 0

    init(report: InspectionReport) {
        self.report = report
    }

    func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        runCount += 1
        startContinuation?.resume()
        startContinuation = nil

        while true {
            while !pending.isEmpty {
                onUpdate(pending.removeFirst())
            }
            if let outcome = pendingOutcome {
                pendingOutcome = nil
                return outcome
            }
            applied?.resume()
            applied = nil
            await withCheckedContinuation { gate = $0 }
        }
    }

    func waitUntilStarted() async {
        guard runCount == 0 else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func deliverReport() async { await release(.report(report)) }
    func deliver(waveform: WaveformOutcome) async { await release(.waveform(waveform)) }
    func deliver(spectrogram: SpectrogramOutcome) async { await release(.spectrogram(spectrogram)) }
    func deliver(signalLevelMetrics: SignalLevelMetricsOutcome) async { await release(.signalLevelMetrics(signalLevelMetrics)) }
    func deliver(truePeak: TruePeakOutcome) async { await release(.truePeak(truePeak)) }
    func deliver(loudness: LoudnessOutcome) async { await release(.loudness(loudness)) }
    func deliver(significantBandwidth: SignificantBandwidthOutcome) async { await release(.significantBandwidth(significantBandwidth)) }

    private func release(_ update: InspectionUpdate) async {
        pending.append(update)
        gate?.resume()
        gate = nil
        await withCheckedContinuation { applied = $0 }
    }

    func finish(_ outcome: SourceInspectionOutcome) {
        pendingOutcome = outcome
        gate?.resume()
        gate = nil
    }
}

@MainActor
@Suite("Feature — the inspection's analyses land as one operation's bundle")
struct InspectionAnalysesStaleAtomicityTests {
    // MARK: Six analyses, distinguishable per operation

    /// One operation's six analyses, every one of them different from the other operation's.
    ///
    /// Distinguishability is the whole point: a field carrying the same value in both would be unable
    /// to witness a mixture, so none does.
    private struct Analyses {
        let waveform: WaveformEnvelope
        let spectrogram: Spectrogram
        let signalLevelMetrics: SignalLevelMetrics
        let truePeak: TruePeakMeasurement
        let loudness: LoudnessMeasurement
        let significantBandwidth: SignificantBandwidth

        /// The bundle the action returns when it finishes.
        var bundle: InspectionAnalyses {
            InspectionAnalyses(
                waveform: .available(waveform),
                spectrogram: .available(spectrogram),
                signalLevelMetrics: .available(signalLevelMetrics),
                truePeak: .available(truePeak),
                loudness: .available(loudness),
                significantBandwidth: .available(significantBandwidth)
            )
        }

        /// Releases all six progressively, in the order the shared pass settles them.
        func deliverAll(through action: SteppedAction) async {
            await action.deliver(waveform: .available(waveform))
            await action.deliver(spectrogram: .available(spectrogram))
            await action.deliver(signalLevelMetrics: .available(signalLevelMetrics))
            await action.deliver(truePeak: .available(truePeak))
            await action.deliver(loudness: .available(loudness))
            await action.deliver(significantBandwidth: .available(significantBandwidth))
        }
    }

    private func analyses(
        channelCount: Int, band: Float, peak: Float, truePeak: Float, lufs: Double, frequency: Double
    ) throws -> Analyses {
        let level = try #require(SignalLevelMetrics.Channel(
            sampleCount: 100, peakSample: peak, rms: 0.2, dcOffset: 0, clippedSampleCount: 0
        ))
        let peakChannel = try #require(TruePeakMeasurement.Channel(sampleCount: 100, truePeak: truePeak))
        let peakMethod = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let bandwidthChannel = try #require(SignificantBandwidth.Channel(frequency: frequency, resolution: 23.4375))
        let bandwidthMethod = try #require(SignificantBandwidthMethod(
            windowFrames: 2048, hopFrames: 512, sampleRate: 48_000
        ))
        let envelope = try #require(WaveformEnvelope.empty(channelCount: channelCount))
        let spectrogram = try #require(Spectrogram(
            values: [Float](repeating: band, count: 4),
            columnCount: 2, bandCount: 2,
            sampleRate: 44_100, frameCount: 44_100, channelCount: 1
        ))
        let metrics = try #require(SignalLevelMetrics(
            channels: [level],
            overallPeakSample: peak, overallRMS: 0.2, overallDCOffset: 0, overallClippedSampleCount: 0
        ))
        let peakMeasurement = try #require(TruePeakMeasurement(channels: [peakChannel], method: peakMethod))
        let loudness = try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)
        ))
        let bandwidth = try #require(SignificantBandwidth(channels: [bandwidthChannel], method: bandwidthMethod))
        return Analyses(
            waveform: envelope,
            spectrogram: spectrogram,
            signalLevelMetrics: metrics,
            truePeak: peakMeasurement,
            loudness: loudness,
            significantBandwidth: bandwidth
        )
    }

    private func analysesOfA() throws -> Analyses {
        try analyses(channelCount: 2, band: -60, peak: 0.5, truePeak: 0.75, lufs: -18, frequency: 16_000)
    }

    private func analysesOfB() throws -> Analyses {
        try analyses(channelCount: 1, band: -30, peak: 0.25, truePeak: 0.375, lufs: -23, frequency: 20_000)
    }

    private func report(named name: String = "fixture") -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .completed
        )
    }

    private func presentation(of model: ImportFlowModel) -> InspectionPresentation? {
        guard case let .report(presentation) = model.state else { return nil }
        return presentation
    }

    /// Asserts the settled presentation is **entirely** one operation's, field by field.
    ///
    /// Six separate expectations rather than one on the whole value: a single equality would report
    /// "not equal" where the question is *which* field came from the wrong operation.
    private func expect(
        _ shown: InspectionPresentation, isEntirely expected: Analyses, _ operation: String
    ) {
        #expect(shown.waveform == .available(expected.waveform), "waveform is not \(operation)'s")
        #expect(shown.spectrogram == .available(expected.spectrogram), "spectrogram is not \(operation)'s")
        #expect(shown.signalLevelMetrics == .available(expected.signalLevelMetrics), "signal level metrics are not \(operation)'s")
        #expect(shown.truePeak == .available(expected.truePeak), "true peak is not \(operation)'s")
        #expect(shown.loudness == .available(expected.loudness), "loudness is not \(operation)'s")
        #expect(shown.significantBandwidth == .available(expected.significantBandwidth), "programme bandwidth is not \(operation)'s")
    }

    // MARK: The bundle is one operation's, whole

    /// **The property.** B settles all six; A then delivers all six late and returns a complete bundle.
    /// The presentation must be entirely B — not "B plus whichever of A's fields happened to be
    /// unguarded".
    ///
    /// Both stale paths are exercised in the one sequence: the six progressive updates, each dropped by
    /// the operation guard in the update handler, and the final `.inspected` bundle, dropped by the same
    /// guard on the outcome. Routing any single analysis around either guard leaves a mixture this
    /// fails on.
    @Test("a superseded operation's six analyses land on none of the six")
    func aStaleBundleLandsOnNoField() async throws {
        let a = try analysesOfA()
        let b = try analysesOfB()

        let first = SteppedAction(report: report(named: "first"))
        let model = ImportFlowModel(action: first.run)
        let firstRun = Task { await model.selectAndInspect() }
        await first.waitUntilStarted()
        await first.deliverReport()

        // The user picks another file while the first's analyses are still pending, and the second
        // settles completely.
        let second = SteppedAction(report: report(named: "second"))
        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        await second.deliverReport()
        await b.deliverAll(through: second)
        second.finish(.inspected(second.report, analyses: b.bundle))
        await secondRun.value

        let settled = try #require(presentation(of: model))
        expect(settled, isEntirely: b, "B")

        // The first operation now produces everything, late. None of it may reach the presentation.
        await a.deliverAll(through: first)
        first.finish(.inspected(first.report, analyses: a.bundle))
        // Awaited to completion, so what follows is asserted against an operation that is entirely
        // over rather than one that merely had a scheduling hop left.
        await firstRun.value

        let shown = try #require(presentation(of: model))
        #expect(shown.report.file.displayName == "second", "a stale operation replaced the current report")
        expect(shown, isEntirely: b, "B")
    }

    /// The mixture the merge in `apply(_:restoringOnCancellation:)` could actually produce, and the
    /// reason this suite exists at all.
    ///
    /// When a late bundle's report **equals** the one on screen — the same file inspected twice — that
    /// merge does not replace the presentation wholesale: it fills each field that is still `.loading`
    /// and keeps each that has settled. So without the operation guard, a bundle from A would land on
    /// exactly the fields B had not reached yet, leaving B's waveform beside A's loudness. Nothing
    /// about the report distinguishes the two operations here, which is what makes the six values the
    /// only witness.
    @Test("a late bundle for the same file fills none of the analyses still loading")
    func aStaleBundleDoesNotFillLoadingFields() async throws {
        let a = try analysesOfA()
        let b = try analysesOfB()
        let same = report(named: "the same file, inspected twice")

        let first = SteppedAction(report: same)
        let model = ImportFlowModel(action: first.run)
        let firstRun = Task { await model.selectAndInspect() }
        await first.waitUntilStarted()
        await first.deliverReport()

        // The second operation reaches three of the six and stops there.
        let second = SteppedAction(report: same)
        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        await second.deliverReport()
        await second.deliver(waveform: .available(b.waveform))
        await second.deliver(spectrogram: .available(b.spectrogram))
        await second.deliver(signalLevelMetrics: .available(b.signalLevelMetrics))

        // The first now returns a complete bundle for a report equal to the current one.
        first.finish(.inspected(same, analyses: a.bundle))
        await firstRun.value

        let shown = try #require(presentation(of: model))
        #expect(shown.waveform == .available(b.waveform), "the settled waveform was walked back")
        #expect(shown.spectrogram == .available(b.spectrogram), "the settled spectrogram was walked back")
        #expect(shown.signalLevelMetrics == .available(b.signalLevelMetrics), "the settled metrics were walked back")
        #expect(shown.truePeak == .loading, "a stale bundle filled the true peak still loading")
        #expect(shown.loudness == .loading, "a stale bundle filled the loudness still loading")
        #expect(shown.significantBandwidth == .loading, "a stale bundle filled the programme bandwidth still loading")

        second.finish(.inspected(same, analyses: b.bundle))
        await secondRun.value
    }
}
