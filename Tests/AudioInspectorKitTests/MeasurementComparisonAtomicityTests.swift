import Testing

import AudioInspectorDomain
@testable import FeatureImport

// **Task 3.3, and the property this whole group exists to protect.**
//
// A comparison now carries two answers about one pair of files. The failure this guards against is not
// a wrong number: it is a comparison whose technical half describes one pair and whose measurement half
// describes another — or worse, one whose four measurements come from two different files.
//
// Every operation below is forced by a continuation the test resumes itself. **No sleeps, no polling, no
// `Task.yield()` as synchronisation**, on the precedent `InspectionAnalysesStaleAtomicityTests` set.
@MainActor
@Suite("Feature — a comparison's measurements belong to the file beside them")
struct MeasurementComparisonAtomicityTests {

    // MARK: A scripted comparison action

    /// Delivers a report, suspends until released, then returns a settled outcome.
    @MainActor
    private final class ScriptedAction {
        let report: InspectionReport
        let analyses: InspectionAnalyses
        private var started: CheckedContinuation<Void, Never>?
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var runCount = 0

        init(report: InspectionReport, analyses: InspectionAnalyses) {
            self.report = report
            self.analyses = analyses
        }

        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            runCount += 1
            onUpdate(.report(report))
            started?.resume(); started = nil
            await withCheckedContinuation { gate = $0 }
            return .inspected(report, analyses: analyses)
        }

        func waitUntilStarted() async {
            guard runCount == 0 else { return }
            await withCheckedContinuation { started = $0 }
        }

        func release() { gate?.resume(); gate = nil }
    }

    // MARK: Deliberately distinguishable measurements

    /// One file's four measurements, every one of them different from another file's, so a mixture is
    /// observable rather than inferred.
    private func measurements(
        peak: Float, truePeakValue: Float, lufs: Double, bandwidthHz: Double
    ) throws -> InspectionAnalyses {
        let level = try #require(SignalLevelMetrics.Channel(
            sampleCount: 100, peakSample: peak, rms: 0.2, dcOffset: 0, clippedSampleCount: 0
        ))
        let levels = try #require(SignalLevelMetrics(
            channels: [level], overallPeakSample: peak, overallRMS: 0.2,
            overallDCOffset: 0, overallClippedSampleCount: 0
        ))
        let peakMethod = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        let peakChannel = try #require(TruePeakMeasurement.Channel(sampleCount: 100, truePeak: truePeakValue))
        let truePeak = try #require(TruePeakMeasurement(channels: [peakChannel], method: peakMethod))
        let loudness = try #require(LoudnessMeasurement(
            integratedLoudness: lufs,
            method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)
        ))
        let bandwidthMethod = try #require(SignificantBandwidthMethod(
            windowFrames: 2_048, hopFrames: 512, sampleRate: 48_000
        ))
        let reading = try #require(SignificantBandwidth.Channel(frequency: bandwidthHz, resolution: 23.4375))
        let bandwidth = try #require(SignificantBandwidth(channels: [reading], method: bandwidthMethod))
        return InspectionAnalyses(
            waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .available(levels),
            truePeak: .available(truePeak), loudness: .available(loudness),
            significantBandwidth: .available(bandwidth)
        )
    }

    private func report(named name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(), warnings: [], status: .completed
        )
    }

    /// A flow showing a **fully settled** primary file, so the comparison's own publication is the only
    /// thing left waiting.
    private func flowWithSettledPrimary(
        _ analyses: InspectionAnalyses
    ) async -> (ImportFlowModel, InspectionReport) {
        let primary = report(named: "a.wav")
        let action = ScriptedAction(report: primary, analyses: analyses)
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        action.release()
        await running.value
        return (flow, primary)
    }

    /// Reads the four figures that identify which file a measurement comparison's *second* side is.
    private func secondSideFingerprint(_ c: MeasurementComparison) -> [String] {
        var out: [String] = []
        if case let .different(_, second) = c.signalLevels.overall.peakSample { out.append("peak=\(second)") }
        if case let .different(_, second) = c.truePeak.overall { out.append("truePeak=\(second)") }
        if case let .different(_, second, _) = c.loudness { out.append("lufs=\(second)") }
        if case let .separated(_, second) = c.programmeBandwidth.overall { out.append("hz=\(second.frequency)") }
        return out
    }

    // MARK: The property

    /// **B is superseded by C while B is still reading; B then finishes late.** The published pair must
    /// be entirely C's — technical *and* measurements, and all four measurements from the same file.
    @Test("a superseded comparison's late measurements land on none of the four")
    func aStaleComparisonLandsOnNothing() async throws {
        let (flow, primary) = await flowWithSettledPrimary(
            try measurements(peak: 0.10, truePeakValue: 0.11, lufs: -30, bandwidthHz: 8_000)
        )

        let b = ScriptedAction(
            report: report(named: "b.wav"),
            analyses: try measurements(peak: 0.20, truePeakValue: 0.21, lufs: -20, bandwidthHz: 12_000)
        )
        let comparingB = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        // B's report has landed: the technical comparison exists and carries no measurements yet.
        guard case let .ready(technicalB, measurementsB, _) = flow.comparison else {
            Issue.record("B's technical comparison was not published"); return
        }
        #expect(technicalB.second.file.displayName == "b.wav")
        #expect(measurementsB == nil, "a measurement comparison appeared before B had settled")

        // C replaces B before B has finished.
        let c = ScriptedAction(
            report: report(named: "c.wav"),
            analyses: try measurements(peak: 0.30, truePeakValue: 0.31, lufs: -10, bandwidthHz: 20_000)
        )
        let comparingC = Task { await flow.compare(using: c.run) }
        await c.waitUntilStarted()
        c.release()
        await comparingC.value

        // C is complete. Now B finishes, late.
        b.release()
        await comparingB.value

        guard case let .ready(technical, published, _) = flow.comparison else {
            Issue.record("the comparison stopped being ready"); return
        }
        #expect(technical == FileComparison(first: primary, second: c.report),
                "a superseded comparison replaced the technical half")
        let measurements = try #require(published, "C's measurements never reached the comparison")

        // All four name C, and none names B.
        #expect(
            secondSideFingerprint(measurements) == ["peak=0.3", "truePeak=0.31", "lufs=-10.0", "hz=20000.0"],
            "the measurement comparison is not entirely C's: \(secondSideFingerprint(measurements))"
        )
        // And the pair is the one the domain builds from C alone — no field could have come from B.
        let expected = MeasurementComparison(
            first: try #require(flowPrimaryMeasurements(flow)), second: try #require(c.analyses.settledMeasurements)
        )
        #expect(measurements == expected, "the published pair is not the one C's own measurements produce")
    }

    private func flowPrimaryMeasurements(_ flow: ImportFlowModel) -> ReportMeasurements? {
        guard case let .report(presentation) = flow.state else { return nil }
        return presentation.settledMeasurements
    }

    /// **The primary file can settle last**, because the compare action is offered the moment its report
    /// is on screen and the two files then read concurrently. Until it settles there is no pair, and the
    /// technical comparison stands alone rather than being held back.
    @Test("the pair waits for whichever file settles last")
    func thePairWaitsForBothSides() async throws {
        let primary = report(named: "a.wav")
        let primaryAction = ScriptedAction(
            report: primary,
            analyses: try measurements(peak: 0.10, truePeakValue: 0.11, lufs: -30, bandwidthHz: 8_000)
        )
        let flow = ImportFlowModel(action: primaryAction.run)
        let running = Task { await flow.selectAndInspect() }
        await primaryAction.waitUntilStarted()
        // The primary's report is on screen; it is still measuring.

        let b = ScriptedAction(
            report: report(named: "b.wav"),
            analyses: try measurements(peak: 0.20, truePeakValue: 0.21, lufs: -20, bandwidthHz: 12_000)
        )
        let comparing = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        b.release()
        await comparing.value

        // B has settled and the primary has not: technical yes, measurements no.
        guard case let .ready(_, beforePrimary, _) = flow.comparison else {
            Issue.record("no technical comparison"); return
        }
        #expect(beforePrimary == nil, "the pair was published while the primary was still measuring")

        // The primary settles; the pair appears without the technical half being rebuilt.
        primaryAction.release()
        await running.value
        guard case let .ready(technical, after, _) = flow.comparison else {
            Issue.record("the comparison stopped being ready"); return
        }
        #expect(technical.second.file.displayName == "b.wav")
        #expect(after != nil, "the pair never appeared after the primary settled")
    }

    // MARK: Cancellation and failure

    /// Cancelling a replacement restores the comparison that was on screen — **with the bundle it was
    /// built from**, so a later settling of the primary refreshes that one rather than a superseded
    /// file's.
    @Test("cancelling a replacement restores the previous pair and publishes nothing partial")
    func cancellingARepla_cementIsNeutral() async throws {
        let (flow, _) = await flowWithSettledPrimary(
            try measurements(peak: 0.10, truePeakValue: 0.11, lufs: -30, bandwidthHz: 8_000)
        )
        let b = ScriptedAction(
            report: report(named: "b.wav"),
            analyses: try measurements(peak: 0.20, truePeakValue: 0.21, lufs: -20, bandwidthHz: 12_000)
        )
        let comparingB = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        b.release()
        await comparingB.value
        let established = flow.comparison

        // A replacement that the user then dismisses.
        await flow.compare(using: { _ in .cancelled })
        #expect(flow.comparison == established, "cancelling changed the comparison on screen")
    }

    /// **A restored comparison keeps the bundle it was built from**, so a primary file that settles
    /// afterwards refreshes *that* comparison rather than nothing at all.
    ///
    /// Written because a control found it untested: dropping the bundle on cancellation is invisible
    /// unless the primary settles later, and no other test had that ordering.
    @Test("a comparison restored by cancellation still completes when the primary settles")
    func aRestoredComparisonStillCompletes() async throws {
        let primary = report(named: "a.wav")
        let primaryAction = ScriptedAction(
            report: primary,
            analyses: try measurements(peak: 0.10, truePeakValue: 0.11, lufs: -30, bandwidthHz: 8_000)
        )
        let flow = ImportFlowModel(action: primaryAction.run)
        let running = Task { await flow.selectAndInspect() }
        await primaryAction.waitUntilStarted()  // the primary is still measuring

        let b = ScriptedAction(
            report: report(named: "b.wav"),
            analyses: try measurements(peak: 0.20, truePeakValue: 0.21, lufs: -20, bandwidthHz: 12_000)
        )
        let comparingB = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        b.release()
        await comparingB.value
        guard case let .ready(_, notYet, _) = flow.comparison else { Issue.record("no comparison"); return }
        #expect(notYet == nil, "the pair was published while the primary was still measuring")

        // A replacement the user dismisses: B's comparison comes back.
        await flow.compare(using: { _ in .cancelled })

        // The primary settles last. B's pair must appear — which it can only do if the bundle came back
        // with the comparison.
        primaryAction.release()
        await running.value
        guard case let .ready(technical, published, _) = flow.comparison else {
            Issue.record("the comparison stopped being ready"); return
        }
        #expect(technical.second.file.displayName == "b.wav")
        let measurements = try #require(published, "the restored comparison never completed")
        #expect(secondSideFingerprint(measurements) == ["peak=0.2", "truePeak=0.21", "lufs=-20.0", "hz=12000.0"])
    }

    /// **A producer failure is not a technical failure.** Every measurement fails while the report
    /// survives, so the technical comparison stands and the measurement comparison reports that the
    /// second side had nothing — never that the comparison failed.
    @Test("a compared file whose measurements all failed still compares technically")
    func aMeasurementFailureIsNotAComparisonFailure() async throws {
        let (flow, primary) = await flowWithSettledPrimary(
            try measurements(peak: 0.10, truePeakValue: 0.11, lufs: -30, bandwidthHz: 8_000)
        )
        let failed = InspectionAnalyses(
            waveform: .failed(message: "no"), spectrogram: .failed(message: "no"),
            signalLevelMetrics: .failed(message: "no"), truePeak: .failed(message: "no"),
            loudness: .failed(message: "no"), significantBandwidth: .failed(message: "no")
        )
        let b = ScriptedAction(report: report(named: "b.wav"), analyses: failed)
        let comparing = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        b.release()
        await comparing.value

        guard case let .ready(technical, published, _) = flow.comparison else {
            Issue.record("a measurement failure failed the whole comparison"); return
        }
        #expect(technical == FileComparison(first: primary, second: b.report))
        let measurements = try #require(published, "the pair was withheld because a measurement failed")
        // The compared file's measurements all failed, so it has nothing on that side — and the primary
        // file's numbers are **still there**, which is what the surface needs to avoid printing
        // "No value" under a file that has one.
        #expect(measurements.loudness.gapReason == .secondMissing)
        #expect(measurements.truePeak.overall.gapReason == .secondMissing)
        #expect(measurements.loudness.gapValue?.first != nil, "the primary file's loudness was dropped")
        #expect(measurements.truePeak.overall.gapValue?.first != nil, "the primary file's true peak was dropped")
    }

    /// A cancelled analysis is **not** a settled answer, so no pair is published for it — but the
    /// technical comparison the report already produced is untouched.
    @Test("a cancelled analysis publishes no pair and does not disturb the technical comparison")
    func aCancelledAnalysisPublishesNoPair() async throws {
        let (flow, primary) = await flowWithSettledPrimary(
            try measurements(peak: 0.10, truePeakValue: 0.11, lufs: -30, bandwidthHz: 8_000)
        )
        let cancelled = InspectionAnalyses(
            waveform: .cancelled, spectrogram: .cancelled, signalLevelMetrics: .cancelled,
            truePeak: .cancelled, loudness: .cancelled, significantBandwidth: .cancelled
        )
        let b = ScriptedAction(report: report(named: "b.wav"), analyses: cancelled)
        let comparing = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        b.release()
        await comparing.value

        guard case let .ready(technical, published, _) = flow.comparison else {
            Issue.record("the technical comparison was lost"); return
        }
        #expect(technical == FileComparison(first: primary, second: b.report))
        #expect(published == nil, "a cancelled analysis produced a measurement comparison")
    }
}
