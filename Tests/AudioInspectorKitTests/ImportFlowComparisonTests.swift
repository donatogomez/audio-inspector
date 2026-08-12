import Testing

import AudioInspectorDomain
@testable import FeatureImport

/// The comparison half of the import flow: choosing a second file while the first report stays on
/// screen. Driven by injected actions — no panel, no filesystem, no SwiftUI, and **no sleeps**: every
/// ordering below is forced by a continuation the test resumes itself.
@MainActor
@Suite("Feature — comparison flow")
struct ImportFlowComparisonTests {

    // MARK: Harness

    /// An action that delivers a first batch of updates, then **suspends** until the test releases it
    /// with a second batch and an outcome.
    ///
    /// **The handler is never stored**, which is not a detail of the harness but the port's own rule:
    /// `InspectionUpdateHandler` is non-escaping precisely so no consumer can deliver an update after
    /// the security-scoped window has closed. A fake that captured it would be testing something the
    /// production seam does not permit.
    ///
    /// Every ordering below is forced by resuming this continuation — **no sleeps and no reliance on
    /// scheduling**.
    @MainActor
    final class ControllableAction {
        struct Release {
            var updates: [InspectionUpdate] = []
            var outcome: SourceInspectionOutcome
        }

        private(set) var callCount = 0
        private let early: [InspectionUpdate]
        private var continuation: CheckedContinuation<Release, Never>?
        /// Set when `finish` is called before the action has reached its suspension point, so the
        /// release is never lost to ordering.
        private var pendingRelease: Release?

        private var hasStarted = false
        private var startedContinuation: CheckedContinuation<Void, Never>?

        /// - Parameter delivering: updates sent as soon as the action starts, before it suspends.
        init(delivering early: [InspectionUpdate] = []) { self.early = early }

        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            callCount += 1
            hasStarted = true
            startedContinuation?.resume()
            startedContinuation = nil

            for update in early { onUpdate(update) }

            let release: Release
            if let pending = pendingRelease {
                pendingRelease = nil
                release = pending
            } else {
                release = await withCheckedContinuation { continuation = $0 }
            }

            for update in release.updates { onUpdate(update) }
            return release.outcome
        }

        /// Suspends until the action has actually begun and delivered its early updates.
        ///
        /// **This is why nothing below needs a sleep or a guessed number of yields.** Waiting on the
        /// action itself is exact, where `Task.yield()` only advances the scheduler by an amount that
        /// depends on how many tasks happen to be between the test and the work.
        func waitUntilStarted() async {
            guard !hasStarted else { return }
            await withCheckedContinuation { startedContinuation = $0 }
        }

        /// Resumes the action, optionally delivering further updates first — the "arrives late" case.
        /// Safe to call before the action has suspended: the release is held and consumed on arrival.
        func finish(sending updates: [InspectionUpdate] = [], _ outcome: SourceInspectionOutcome) {
            let release = Release(updates: updates, outcome: outcome)
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: release)
            } else {
                pendingRelease = release
            }
        }
    }

    private func report(
        named name: String,
        sampleRate: Int = 44_100,
        status: InspectionStatus = .completed
    ) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 1_024,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(
                container: .available("wav"),
                sampleRate: .available(sampleRate)
            ),
            warnings: [],
            status: status
        )
    }

    /// A report of a file nothing could be read from — the shape the use case produces on a global
    /// failure: every property `unavailable`, status `failed`.
    private func globallyFailedReport(named name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: nil,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(InspectionError(code: .fileUnreadable, message: "could not be opened"))
        )
    }

    /// The state a comparison actually starts from: a report on screen whose primary operation is still
    /// in flight, so every test below also shows that a comparison neither disturbs it nor waits on it.
    ///
    /// The returned task is **not** awaited by the caller; the action stays suspended until a test
    /// releases it, or until the test ends.
    private func flowShowingAReport(
        _ primary: InspectionReport
    ) async -> (flow: ImportFlowModel, primaryAction: ControllableAction, running: Task<Void, Never>) {
        let action = ControllableAction(delivering: [.report(primary)])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        return (flow, action, running)
    }

    /// The presentation a report on screen has while its visualisations are still being produced.
    private func loadingPresentation(_ report: InspectionReport) -> InspectionPresentation {
        InspectionPresentation(report: report, waveform: .loading, spectrogram: .loading)
    }

    // MARK: Starting a comparison leaves the primary inspection alone

    @Test("a comparison does not disturb the report on screen")
    func startingAComparisonPreservesTheReport() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)
        #expect(flow.state == .report(loadingPresentation(primary)))

        let second = ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()

        // The report is exactly where it was, and the comparison is a separate, parallel state.
        #expect(flow.state == .report(loadingPresentation(primary)))
        #expect(flow.comparison == .loading)

        second.finish(.cancelled)
        await comparing.value
        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    @Test("no comparison is started when there is no report to compare against")
    func aComparisonNeedsAReport() async {
        let flow = ImportFlowModel(action: ControllableAction().run)
        #expect(flow.state == ImportFlowModel.State.idle)

        let second = ControllableAction()
        await flow.compare(using: second.run)

        #expect(second.callCount == 0)
        #expect(flow.comparison == .none)
        #expect(flow.state == ImportFlowModel.State.idle)
    }

    // MARK: The comparison is built from the second report alone

    @Test("the comparison exists the moment the second report arrives")
    func theComparisonAppearsWithTheSecondReport() async {
        let primary = report(named: "a.wav", sampleRate: 44_100)
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let other = report(named: "b.wav", sampleRate: 48_000)
        let second = ControllableAction(delivering: [.report(other)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()

        // Ready already — the second file's visualisations have not even been started.
        guard case let .ready(comparison) = flow.comparison else {
            Issue.record("expected a comparison")
            return
        }
        #expect(comparison.first == primary)
        #expect(comparison.second == other)
        #expect(comparison.sampleRate == .different(first: 44_100, second: 48_000))

        second.finish(.inspected(other, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparing.value
        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    /// **The second file's visualisations neither gate the technical comparison nor change it.**
    @Test("the second file's waveform and spectrogram change nothing")
    func theSecondFilesVisualisationsChangeNothing() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let other = report(named: "b.wav", sampleRate: 48_000)
        let second = ControllableAction(delivering: [.report(other)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        let afterReport = flow.comparison
        #expect(afterReport != .loading)

        // Both of the second file's visualisations settle afterwards, one of them as a failure.
        second.finish(
            sending: [.waveform(.unavailable), .spectrogram(.failed(message: "no"))],
            .inspected(other, waveform: .unavailable, spectrogram: .failed(message: "no"), signalLevelMetrics: .unavailable, truePeak: .unavailable)
        )
        await comparing.value

        #expect(flow.comparison == afterReport)
        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    // MARK: Cancellation

    @Test("cancelling the second selection leaves the report and the previous comparison alone")
    func cancellingTheSecondSelectionIsNeutral() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let second = ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.cancelled)
        await comparing.value

        #expect(flow.comparison == .none) // back to exactly where the user was
        #expect(flow.state == .report(loadingPresentation(primary)))
        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    @Test("cancelling a replacement restores the comparison already on screen")
    func cancellingAReplacementRestoresTheExistingComparison() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report(named: "b.wav", sampleRate: 48_000)
        let second = ControllableAction(delivering: [.report(b)])
        let first = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(b, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await first.value
        let settled = flow.comparison

        // A replacement is started and then cancelled at the picker.
        let third = ControllableAction()
        let replacing = Task { await flow.compare(using: third.run) }
        await third.waitUntilStarted()
        third.finish(.cancelled)
        await replacing.value

        #expect(flow.comparison == settled)
        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    @Test("dismissing a comparison leaves the report untouched and stops a late result landing")
    func dismissingAComparisonLeavesTheReport() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report(named: "b.wav")
        let second = ControllableAction(delivering: [.report(b)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        #expect(flow.comparison != .none)

        flow.dismissComparison()
        #expect(flow.comparison == .none)
        #expect(flow.state == .report(loadingPresentation(primary)))

        second.finish(.inspected(b, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparing.value
        #expect(flow.comparison == .none, "a dismissed comparison came back")

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    // MARK: The second file fails

    /// **A globally failed second file is not a failed comparison.** Its report exists, so a comparison
    /// is built and every field reports that nothing was compared — and the status explaining why
    /// travels with the report.
    @Test("a globally failed second file still produces a comparison")
    func aGloballyFailedSecondFileStillCompares() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let broken = globallyFailedReport(named: "b.wav")
        let second = ControllableAction(delivering: [.report(broken)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(broken, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparing.value

        guard case let .ready(comparison) = flow.comparison else {
            Issue.record("expected a comparison")
            return
        }
        #expect(comparison.sampleRate == .incomparable(.firstAvailable(second: .unavailable)))
        #expect(comparison.container == .incomparable(.firstAvailable(second: .unavailable)))
        #expect(
            comparison.second.status
                == .failed(InspectionError(code: .fileUnreadable, message: "could not be opened"))
        )
        #expect(comparison.first == primary)
        #expect(flow.state == .report(loadingPresentation(primary)))

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    /// A file that could not be prepared at all yields no report, so there is nothing to compare — and
    /// that is a failure of the comparison, never of the inspection on screen.
    @Test("a second file that cannot be opened at all fails only the comparison")
    func aSecondFileThatCannotBeOpenedFailsOnlyTheComparison() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let second = ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.preparationFailed)
        await comparing.value

        #expect(flow.comparison == .failed(message: "That file could not be opened for comparison."))
        #expect(flow.state == .report(loadingPresentation(primary)))

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    // MARK: Replacement — the test the identity model exists for

    /// **B starts, C starts before B finishes, B reports and finishes late, then C settles.** C wins, B
    /// reaches nothing, and the report on screen never moves.
    @Test("a third file replaces the second, and only the second")
    func aThirdFileReplacesTheSecondOnly() async {
        let primary = report(named: "a.wav", sampleRate: 44_100)
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        // B starts and stays in flight, having reported nothing yet.
        let bAction = ControllableAction()
        let comparingB = Task { await flow.compare(using: bAction.run) }
        await bAction.waitUntilStarted()

        // C starts while B is still in flight.
        let c = report(named: "c.wav", sampleRate: 96_000)
        let cAction = ControllableAction(delivering: [.report(c)])
        let comparingC = Task { await flow.compare(using: cAction.run) }
        await cAction.waitUntilStarted()

        // C is already the comparison on screen.
        guard case let .ready(afterC) = flow.comparison else {
            Issue.record("expected C's comparison")
            return
        }
        #expect(afterC.second == c)

        // B now reports *and* finishes, both late. Neither may reach anything.
        let b = report(named: "b.wav", sampleRate: 48_000)
        bAction.finish(
            sending: [.report(b)],
            .inspected(b, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable)
        )
        await comparingB.value

        guard case let .ready(afterStaleB) = flow.comparison else {
            Issue.record("a superseded second file replaced the comparison on screen")
            return
        }
        #expect(afterStaleB.second == c, "a superseded second file reached the surface")
        #expect(afterStaleB.sampleRate == .different(first: 44_100, second: 96_000))

        cAction.finish(.inspected(c, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparingC.value

        guard case let .ready(final) = flow.comparison else {
            Issue.record("expected a comparison")
            return
        }
        #expect(final.second == c)
        #expect(final.first == primary)
        #expect(flow.state == .report(loadingPresentation(primary)))

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    // MARK: The primary inspection's own work still lands

    /// **The invariant the two operation numbers exist for.** A waveform and a spectrogram belonging to
    /// the file on screen are still in flight when a comparison starts and finishes; both must arrive.
    @Test("the first file's late waveform and spectrogram still land during a comparison")
    func theFirstFilesLateVisualisationsStillLand() async throws {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        // A whole comparison begins and settles while the first file's work is unfinished.
        let b = report(named: "b.wav")
        let second = ControllableAction(delivering: [.report(b)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(b, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparing.value

        // Now the first file's visualisations arrive, late.
        let envelope = try #require(WaveformEnvelope.empty(channelCount: 2))
        primaryAction.finish(
            sending: [.waveform(.available(envelope)), .spectrogram(.unavailable)],
            .inspected(primary, waveform: .available(envelope), spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable)
        )
        await running.value

        guard case let .report(presentation) = flow.state else {
            Issue.record("expected a report")
            return
        }
        #expect(presentation.waveform == .available(envelope))
        #expect(presentation.spectrogram == .unavailable)

        // And the comparison is still there, unaffected by either.
        guard case let .ready(comparison) = flow.comparison else {
            Issue.record("expected a comparison")
            return
        }
        #expect(comparison.second == b)
    }

    // MARK: Starting a new primary inspection

    /// A comparison describes *the report on screen*. Once that report is being replaced, its left-hand
    /// side is gone, so the comparison goes with it.
    @Test("inspecting a new file ends the comparison")
    func aNewPrimaryInspectionEndsTheComparison() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report(named: "b.wav")
        let second = ControllableAction(delivering: [.report(b)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(b, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparing.value
        #expect(flow.comparison != .none)

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value

        // A brand-new primary selection.
        let newPrimary = report(named: "d.wav")
        let fresh = ControllableAction(delivering: [.report(newPrimary)])
        let reinspecting = Task { await flow.inspectDroppedSource(using: fresh.run) }
        await fresh.waitUntilStarted()

        #expect(flow.comparison == .none)

        fresh.finish(.inspected(newPrimary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await reinspecting.value
        #expect(flow.comparison == .none)
    }

    // MARK: No shared mutable state

    /// Two comparison sessions in a row share nothing: the second neither inherits the first's result
    /// nor is polluted by it.
    @Test("two consecutive comparisons share no state")
    func consecutiveComparisonsShareNoState() async {
        let primary = report(named: "a.wav", sampleRate: 44_100)
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report(named: "b.wav", sampleRate: 48_000)
        let firstAction = ControllableAction(delivering: [.report(b)])
        let first = Task { await flow.compare(using: firstAction.run) }
        await firstAction.waitUntilStarted()
        firstAction.finish(.inspected(b, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await first.value

        // The next one starts from `loading`, not from the previous result.
        let secondAction = ControllableAction()
        let second = Task { await flow.compare(using: secondAction.run) }
        await secondAction.waitUntilStarted()
        #expect(flow.comparison == .loading, "the previous comparison leaked into the new one")

        let c = report(named: "c.wav", sampleRate: 44_100)
        secondAction.finish(
            sending: [.report(c)],
            .inspected(c, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable)
        )
        await second.value

        guard case let .ready(comparison) = flow.comparison else {
            Issue.record("expected a comparison")
            return
        }
        #expect(comparison.second == c)
        #expect(comparison.sampleRate == .same(44_100))

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    /// **The same file chosen twice is compared honestly, with no attempt to notice.** Nothing consults
    /// a name, a size, a date or an identifier to decide the two selections are one file.
    @Test("choosing the same file twice compares it against itself")
    func choosingTheSameFileTwiceComparesHonestly() async {
        let primary = report(named: "a.wav", sampleRate: 44_100)
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        // The very same report, as a second inspection of the same file would produce.
        let second = ControllableAction(delivering: [.report(primary)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await comparing.value

        guard case let .ready(comparison) = flow.comparison else {
            Issue.record("expected a comparison")
            return
        }
        #expect(comparison.sampleRate == .same(44_100))
        #expect(comparison.container == .same("wav"))

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }

    /// A comparison never adds a warning to, or changes the status of, the report on screen — whatever
    /// became of the second file.
    @Test("no comparison outcome touches the report on screen")
    func aComparisonNeverWarnsAboutTheFirstFile() async {
        let primary = report(named: "a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let outcomes: [SourceInspectionOutcome] = [
            .cancelled,
            .preparationFailed,
            .inspected(globallyFailedReport(named: "b.wav"), waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable),
        ]

        for outcome in outcomes {
            let second = ControllableAction()
            let comparing = Task { await flow.compare(using: second.run) }
            await second.waitUntilStarted()
            second.finish(outcome)
            await comparing.value

            guard case let .report(presentation) = flow.state else {
                Issue.record("expected a report")
                return
            }
            #expect(presentation.report == primary)
            #expect(presentation.report.warnings.isEmpty)
            #expect(presentation.report.status == .completed)
        }

        primaryAction.finish(.inspected(primary, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable))
        await running.value
    }
}
