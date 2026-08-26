import Testing

import AudioInspectorDomain
@testable import FeatureImport

// **Group 3, and the property the whole group exists to protect.**
//
// A comparison now carries three answers about one pair of files: which technical facts differ, what
// their measurements were, and the two drawings. The failure guarded against is not a wrong picture — it
// is a comparison whose drawings describe one pair and whose facts describe another, or a drawing paired
// with the stream description of a read it did not come from.
//
// Every step below is forced by a continuation the test resumes itself. **No sleeps, no polling, no
// `Task.yield()` as synchronisation**, on the precedent `MeasurementComparisonAtomicityTests` set.
@MainActor
@Suite("Feature — a comparison's drawings belong to the files beside them")
struct PairedVisualsAtomicityTests {

    // MARK: A scripted inspection

    /// Delivers a report, suspends until released, then returns a settled outcome.
    @MainActor
    private final class ScriptedAction {
        let report: InspectionReport
        let analyses: InspectionAnalyses
        private var started: CheckedContinuation<Void, Never>?
        private var gate: CheckedContinuation<Void, Never>?
        /// Set when `release` is called before the run has reached its suspension point, so a release is
        /// never lost to ordering — the same safety `ControllableAction.finish` already carries, and what
        /// lets one action serve a second selection.
        private var pendingRelease = false
        private(set) var runCount = 0

        init(report: InspectionReport, analyses: InspectionAnalyses) {
            self.report = report
            self.analyses = analyses
        }

        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            runCount += 1
            onUpdate(.report(report))
            started?.resume(); started = nil
            if pendingRelease {
                pendingRelease = false
            } else {
                await withCheckedContinuation { gate = $0 }
            }
            return .inspected(report, analyses: analyses)
        }

        func waitUntilStarted() async {
            guard runCount == 0 else { return }
            await withCheckedContinuation { started = $0 }
        }

        func release() {
            if let gate {
                self.gate = nil
                gate.resume()
            } else {
                pendingRelease = true
            }
        }
    }

    /// An action that never settles at all — the picker dismissed, or a file that could not be opened.
    @MainActor
    private final class RefusingAction {
        let report: InspectionReport?
        let outcome: SourceInspectionOutcome
        private var started: CheckedContinuation<Void, Never>?
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var runCount = 0

        init(report: InspectionReport?, outcome: SourceInspectionOutcome) {
            self.report = report
            self.outcome = outcome
        }

        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            runCount += 1
            if let report { onUpdate(.report(report)) }
            started?.resume(); started = nil
            await withCheckedContinuation { gate = $0 }
            return outcome
        }

        func waitUntilStarted() async {
            guard runCount == 0 else { return }
            await withCheckedContinuation { started = $0 }
        }

        func release() { gate?.resume(); gate = nil }
    }

    // MARK: Deliberately distinguishable drawings

    private func report(named name: String) -> InspectionReport {
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

    private func envelope(peak: Float) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -peak, maximum: peak)!], frameCount: 2_048, channelCount: 2
        )!
    }

    private func model(rate: Double) -> Spectrogram {
        Spectrogram(
            values: [-30, -40], columnCount: 1, bandCount: 2,
            sampleRate: rate, frameCount: 2_048, channelCount: 2
        )!
    }

    private func stream(rate: Double) -> PCMStreamDescription {
        PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: 2_048)!
    }

    /// One file's drawings, every one of them different from another file's, so a mixture is
    /// **observed** rather than inferred from fields that merely stayed empty.
    private func drawings(peak: Float, rate: Double) -> InspectionAnalyses {
        InspectionAnalyses(
            waveform: .available(envelope(peak: peak)),
            spectrogram: .available(model(rate: rate)),
            signalLevelMetrics: .unavailable, truePeak: .unavailable,
            loudness: .unavailable, significantBandwidth: .unavailable,
            stream: stream(rate: rate)
        )
    }

    private func expectedVisuals(peak: Float, rate: Double) -> FileVisuals {
        FileVisuals(
            waveform: .available(envelope(peak: peak)),
            spectrogram: .available(model(rate: rate)),
            stream: stream(rate: rate)
        )!
    }

    /// A flow showing a settled primary report, drawings and stream included.
    private func flowWithSettledPrimary(
        peak: Float = 0.10, rate: Double = 44_100
    ) async -> (ImportFlowModel, ScriptedAction) {
        let primary = ScriptedAction(report: report(named: "a.wav"), analyses: drawings(peak: peak, rate: rate))
        let flow = ImportFlowModel(action: primary.run)
        let running = Task { await flow.selectAndInspect() }
        await primary.waitUntilStarted()
        primary.release()
        await running.value
        return (flow, primary)
    }

    private func publishedPair(_ flow: ImportFlowModel) -> PairedVisuals? {
        guard case let .ready(_, _, visuals) = flow.comparison else { return nil }
        return visuals
    }

    // MARK: - One pair, both sides, each with its own read

    /// **The whole point, in one test.** Two settled files produce exactly one pair; each side carries
    /// the drawings its own inspection produced and the description of the read that produced them; and
    /// the two sides are told apart by values, not by position alone.
    @Test("two settled files publish one pair, each side with its own read's description")
    func bothSidesPublishOnePair() async {
        let (flow, _) = await flowWithSettledPrimary(peak: 0.10, rate: 44_100)

        let second = ScriptedAction(report: report(named: "b.wav"), analyses: drawings(peak: 0.90, rate: 96_000))
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()

        // Nothing while the second file is in flight: its report exists, its drawings do not.
        #expect(publishedPair(flow) == nil, "a pair was published before the second file settled")

        second.release()
        await comparing.value

        guard let pair = publishedPair(flow) else {
            Issue.record("no pair was published for two settled files"); return
        }
        #expect(pair.first == expectedVisuals(peak: 0.10, rate: 44_100))
        #expect(pair.second == expectedVisuals(peak: 0.90, rate: 96_000))

        // Each side's artefacts and its description come from the same read, told apart by rate.
        #expect(pair.first.stream?.sampleRate == 44_100)
        #expect(pair.second.stream?.sampleRate == 96_000)
        #expect(pair.first.spectrogram == .available(model(rate: 44_100)))
        #expect(pair.second.spectrogram == .available(model(rate: 96_000)))

        // And the first file was not quietly replaced by the second.
        #expect(pair.first != pair.second)
    }

    // MARK: - Staleness

    /// **B is superseded by C while B is still reading; B then finishes late.** The published pair must
    /// be entirely C's — and so must every other half of the comparison beside it.
    ///
    /// The retained source is asserted as well as the published value: a defect that let a superseded
    /// result reach the visual side by its own path would leave the published pair looking right while
    /// the flow held B's pictures.
    @Test("a superseded comparison's late drawings reach neither the pair nor the retained side")
    func aStalePairLandsOnNothing() async {
        let (flow, _) = await flowWithSettledPrimary(peak: 0.10, rate: 44_100)

        let b = ScriptedAction(report: report(named: "b.wav"), analyses: drawings(peak: 0.20, rate: 48_000))
        let comparingB = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()

        guard case let .ready(technicalB, measurementsB, visualsB) = flow.comparison else {
            Issue.record("B's technical comparison was not published"); return
        }
        #expect(technicalB.second.file.displayName == "b.wav")
        #expect(measurementsB == nil, "a measurement comparison appeared before B had settled")
        #expect(visualsB == nil, "a pair appeared before B had settled")

        // C replaces B before B has finished.
        let c = ScriptedAction(report: report(named: "c.wav"), analyses: drawings(peak: 0.30, rate: 96_000))
        let comparingC = Task { await flow.compare(using: c.run) }
        await c.waitUntilStarted()
        c.release()
        await comparingC.value

        // C is complete. Now B finishes, late.
        b.release()
        await comparingB.value

        guard case let .ready(technical, _, visuals) = flow.comparison else {
            Issue.record("the comparison stopped being ready"); return
        }
        // The technical half is C's.
        #expect(technical.second.file.displayName == "c.wav",
                "a superseded comparison replaced the technical half")
        // The pair is C's, in both of its sides.
        guard let published = visuals else {
            Issue.record("C's pair never reached the comparison"); return
        }
        #expect(published.second == expectedVisuals(peak: 0.30, rate: 96_000),
                "the published pair is not entirely C's: \(published.second)")
        #expect(published.second != expectedVisuals(peak: 0.20, rate: 48_000),
                "a superseded file's drawings reached the published pair")
        #expect(published.first == expectedVisuals(peak: 0.10, rate: 44_100),
                "the first file's side changed when the second was replaced")

        // And the source the pair is built from holds C's, not B's — the second lane a
        // two-sources defect would corrupt while leaving the published value looking right.
        #expect(flow.comparedVisuals == expectedVisuals(peak: 0.30, rate: 96_000),
                "the retained side is not C's: \(String(describing: flow.comparedVisuals))")
    }

    /// **The intermediate state of a replacement.** B settles and publishes a pair; C is then chosen and
    /// is still in flight. The pair B published must be gone *while C is working* — not merely replaced
    /// once C finishes — because a pair on screen beside a comparison that is loading would describe a
    /// file the user has already replaced.
    @Test("choosing a third file removes the settled pair while the new one is still in flight")
    func replacingASettledComparisonRemovesItsPairImmediately() async {
        let (flow, _) = await flowWithSettledPrimary(peak: 0.10, rate: 44_100)

        let b = ScriptedAction(report: report(named: "b.wav"), analyses: drawings(peak: 0.20, rate: 48_000))
        let comparingB = Task { await flow.compare(using: b.run) }
        await b.waitUntilStarted()
        b.release()
        await comparingB.value
        #expect(publishedPair(flow)?.second == expectedVisuals(peak: 0.20, rate: 48_000),
                "B's pair was never published, so there is nothing to invalidate")

        // C is chosen and has not settled.
        let c = ScriptedAction(report: report(named: "c.wav"), analyses: drawings(peak: 0.30, rate: 96_000))
        let comparingC = Task { await flow.compare(using: c.run) }
        await c.waitUntilStarted()

        // B's pair is gone, and nothing has taken its place yet.
        #expect(publishedPair(flow) == nil, "B's pair survived into C's comparison")
        #expect(flow.comparedVisuals == nil, "B's retained side survived into C's comparison")

        c.release()
        await comparingC.value
        #expect(publishedPair(flow)?.second == expectedVisuals(peak: 0.30, rate: 96_000))
    }

    // MARK: - Nothing published for a file that never settled

    @Test("a cancelled second inspection publishes no pair, and no side stands in as absent")
    func cancellationPublishesNoPair() async {
        let (flow, _) = await flowWithSettledPrimary()

        let cancelled = ScriptedAction(
            report: report(named: "b.wav"),
            analyses: InspectionAnalyses(
                waveform: .cancelled, spectrogram: .cancelled,
                signalLevelMetrics: .cancelled, truePeak: .cancelled,
                loudness: .cancelled, significantBandwidth: .cancelled,
                stream: stream(rate: 48_000)
            )
        )
        let comparing = Task { await flow.compare(using: cancelled.run) }
        await cancelled.waitUntilStarted()
        cancelled.release()
        await comparing.value

        #expect(publishedPair(flow) == nil, "a cancelled inspection published a pair")
        #expect(flow.comparedVisuals == nil, "a cancelled inspection left a retained side behind")
        // The technical comparison is unaffected: cancellation of the drawings says nothing about it.
        guard case .ready = flow.comparison else {
            Issue.record("the technical comparison was lost: \(flow.comparison)"); return
        }
    }

    @Test("a second file that could not be opened publishes no pair, and the failure stands")
    func aFileThatCouldNotBeOpened() async {
        let (flow, _) = await flowWithSettledPrimary()

        let refused = RefusingAction(report: nil, outcome: .preparationFailed)
        let comparing = Task { await flow.compare(using: refused.run) }
        await refused.waitUntilStarted()
        refused.release()
        await comparing.value

        guard case .failed = flow.comparison else {
            Issue.record("expected a failed comparison, got \(flow.comparison)"); return
        }
        #expect(publishedPair(flow) == nil)
        #expect(flow.comparedVisuals == nil)
    }

    // MARK: - The three events that end a comparison

    @Test("dismissing the comparison removes the pair")
    func dismissRemovesThePair() async {
        let flow = await flowWithAPublishedPair()
        #expect(publishedPair(flow) != nil)

        flow.dismissComparison()

        #expect(publishedPair(flow) == nil)
        #expect(flow.comparison == .none)
        #expect(flow.comparedVisuals == nil)
    }

    @Test("a new primary inspection removes the pair, and a late result cannot land afterwards")
    func aNewPrimaryInspectionRemovesThePair() async {
        let (flow, primary) = await flowWithSettledPrimary()

        let second = ScriptedAction(report: report(named: "b.wav"), analyses: drawings(peak: 0.90, rate: 96_000))
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.release()
        await comparing.value
        #expect(publishedPair(flow) != nil)

        // The same action serves the second selection: the flow takes its action once, at construction.
        let running = Task { await flow.selectAndInspect() }
        primary.release()
        await running.value

        #expect(flow.comparison == .none)
        #expect(publishedPair(flow) == nil)
        #expect(flow.comparedVisuals == nil)
    }

    // MARK: - Support

    private func flowWithAPublishedPair() async -> ImportFlowModel {
        let (flow, _) = await flowWithSettledPrimary(peak: 0.10, rate: 44_100)
        let second = ScriptedAction(report: report(named: "b.wav"), analyses: drawings(peak: 0.90, rate: 96_000))
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.release()
        await comparing.value
        return flow
    }
}
