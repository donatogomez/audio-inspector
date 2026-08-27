import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureImport

// R1's second subject: **the ten navigation scenarios of `design.md` §4**, and ADR-0026 §5's table of
// four rules, driven against the real `ImportFlowModel` rather than against a description of it.
//
// No SwiftUI, no panel, no filesystem, **no sleeps**: every ordering is forced by a continuation the
// test resumes itself, reusing `ImportFlowComparisonTests.ControllableAction`.
//
// ## The harness observes more often than production does
//
// `RootView` watches `PrimaryInspection(flow.state)` and SwiftUI calls it when that value changes. The
// reader below calls it **after every single publication**, changed or not — a strict superset. That is
// deliberate: it makes every assertion here a property of `WorkspaceNavigation` rather than a property
// of how often the framework happens to call it, so the suite cannot be quietly satisfied by SwiftUI's
// own de-duplication.

/// A reader looking at a window: the flow they are looking at, and where in it they are.
@MainActor
private final class Reader {
    let flow: ImportFlowModel
    private(set) var navigation = WorkspaceNavigation()

    init(_ flow: ImportFlowModel) { self.flow = flow }

    /// The flow published something. Exactly what `RootView` does, and more often.
    func published() { navigation.observe(PrimaryInspection(flow.state)) }

    var section: WorkspaceSection { navigation.section }
    func select(_ section: WorkspaceSection) { navigation.select(section) }
}

/// An action that delivers its updates one at a time, letting the test look at the window between
/// each — the granularity "an analysis settling does not move the reader" is actually about.
@MainActor
private final class NarratingAction {
    private let updates: [InspectionUpdate]
    private let outcome: SourceInspectionOutcome
    /// Run after each update reaches the flow, with the new state already published.
    var afterEachUpdate: (@MainActor () -> Void)?

    init(_ updates: [InspectionUpdate], then outcome: SourceInspectionOutcome) {
        self.updates = updates
        self.outcome = outcome
    }

    func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        for update in updates {
            onUpdate(update)
            afterEachUpdate?()
        }
        return outcome
    }
}

@MainActor
@Suite("App — where the reader is, and the whole of what moves them")
struct WorkspaceNavigationLifecycleTests {

    // MARK: - Fixtures

    private func report(_ name: String, status: InspectionStatus = .completed) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 1_024,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(container: .available("wav"), sampleRate: .available(44_100)),
            warnings: [],
            status: status
        )
    }

    /// A report of a file nothing could be read from. **Still a report**, which is the whole of
    /// scenario 7.
    private func failedReport(_ name: String) -> InspectionReport {
        report(name, status: .failed(InspectionError(code: .fileOpenFailed, message: "could not open")))
    }

    private var nothingSettled: InspectionAnalyses {
        InspectionAnalyses(
            waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable,
            truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable
        )
    }

    /// Every analysis settling, in the order the pipeline publishes them.
    private var everyAnalysisSettling: [InspectionUpdate] {
        [
            .waveform(.unavailable), .spectrogram(.unavailable), .signalLevelMetrics(.unavailable),
            .truePeak(.unavailable), .loudness(.unavailable), .significantBandwidth(.unavailable),
        ]
    }

    /// A window with `report` on screen and every analysis settled, observed throughout.
    private func windowShowing(_ report: InspectionReport) async -> Reader {
        let action = NarratingAction(
            [.report(report)] + everyAnalysisSettling, then: .inspected(report, analyses: nothingSettled)
        )
        let flow = ImportFlowModel(action: action.run)
        let reader = Reader(flow)
        action.afterEachUpdate = { reader.published() }
        await flow.selectAndInspect()
        reader.published()
        return reader
    }

    // MARK: - Scenario 1 — a report arrives

    @Test("a report arriving selects the overview, wherever the reader was")
    func aReportArrivingSelectsTheOverview() async {
        let action = NarratingAction([.report(report("a.wav"))], then: .cancelled)
        let flow = ImportFlowModel(action: action.run)
        let reader = Reader(flow)
        reader.select(.details) // somewhere else entirely, before anything arrives
        action.afterEachUpdate = { reader.published() }

        await flow.selectAndInspect()
        reader.published()

        #expect(reader.section == .overview)
    }

    // MARK: - Scenario 2, and ADR-0026 §5's "nothing else moves it"

    @Test("the reader selects the waveform, and every analysis settling leaves them there")
    func settlingAnalysesDoNotMoveTheReader() async {
        let a = report("a.wav")
        let action = NarratingAction(
            [.report(a)] + everyAnalysisSettling, then: .inspected(a, analyses: nothingSettled)
        )
        let flow = ImportFlowModel(action: action.run)
        let reader = Reader(flow)

        // The report first, so the reader has somewhere to choose from.
        action.afterEachUpdate = {
            reader.published()
            if reader.navigation.section == .overview, case .report = flow.state { reader.select(.waveform) }
        }
        await flow.selectAndInspect()
        reader.published()

        #expect(reader.section == .waveform)
        // And the value the shell watches never moved either: a settling analysis republishes the same
        // report, so there is nothing for the rule to react to in the first place.
        #expect(PrimaryInspection(flow.state) == PrimaryInspection(.report(
            InspectionPresentation(report: a, waveform: .unavailable, spectrogram: .unavailable,
                                   signalLevelMetrics: .unavailable, truePeak: .unavailable,
                                   loudness: .unavailable, significantBandwidth: .unavailable)
        )))
    }

    /// The rule is **idempotent**: observing the same report a hundred times moves nobody. This is what
    /// makes the property belong to `WorkspaceNavigation` and not to SwiftUI's de-duplication.
    @Test("observing the same report again and again moves nobody")
    func observingTheSameReportIsIdempotent() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.spectrum)

        for _ in 0 ..< 100 { reader.published() }

        #expect(reader.section == .spectrum)
    }

    // MARK: - Scenario 6, and the working state that precedes it

    @Test("a new primary file returns the reader to the overview, and working does not")
    func aNewPrimaryFileReturnsToTheOverview() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.waveform)

        let b = report("b.wav")
        let second = ImportFlowComparisonTests.ControllableAction()
        let running = Task { await reader.flow.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()

        #expect(reader.flow.state == .working)
        reader.published()
        #expect(reader.section == .waveform, "an inspection merely starting moved the reader")

        second.finish(sending: [.report(b)], .inspected(b, analyses: nothingSettled))
        await running.value
        reader.published()

        #expect(reader.section == .overview)
    }

    /// Choosing the same file twice is a new inspection, and `AudioFileReference.id` is minted per
    /// inspection — so it is a new primary here too, and the reader returns to the overview.
    @Test("re-inspecting the same file is a new primary")
    func reInspectingTheSameFileIsANewPrimary() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.details)

        let again = report("a.wav") // same name, new inspection, new reference id
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(again)])
        let running = Task { await reader.flow.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(again, analyses: nothingSettled))
        await running.value
        reader.published()

        #expect(reader.section == .overview)
    }

    // MARK: - Scenario 7 — a failure is not a navigation event

    @Test("a new primary file that failed globally leaves the reader where they are")
    func aFailedPrimaryReportDoesNotMoveTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.spectrum)

        let broken = failedReport("broken.wav")
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(broken)])
        let running = Task { await reader.flow.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(broken, analyses: nothingSettled))
        await running.value
        reader.published()

        // The failed report is on screen, and the reader did not move.
        guard case let .report(presentation) = reader.flow.state else {
            Issue.record("a failed inspection did not present a report")
            return
        }
        #expect(presentation.report == broken)
        #expect(reader.section == .spectrum, "a failure was treated as a navigation event")

        // And the next file that does produce a report does move them.
        let c = report("c.wav")
        let third = ImportFlowComparisonTests.ControllableAction(delivering: [.report(c)])
        let alsoRunning = Task { await reader.flow.inspectDroppedSource(using: third.run) }
        await third.waitUntilStarted()
        third.finish(.inspected(c, analyses: nothingSettled))
        await alsoRunning.value
        reader.published()

        #expect(reader.section == .overview)
    }

    /// A partial inspection is a report a reader can read, so it moves them exactly as a completed one
    /// does. Only `failed` is the exception, and only because it is the exception `design.md` §4 names.
    @Test("a partial report is a new primary like any other")
    func aPartialReportMovesTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.measurements)

        let partial = report("b.wav", status: .partial(message: "some properties were unavailable"))
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(partial)])
        let running = Task { await reader.flow.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(partial, analyses: nothingSettled))
        await running.value
        reader.published()

        #expect(reader.section == .overview)
    }

    // MARK: - The two ways an inspection ends without a report

    @Test("a file that could not be opened at all leaves the reader where they are")
    func aPreparationFailureDoesNotMoveTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.details)

        let second = ImportFlowComparisonTests.ControllableAction()
        let running = Task { await reader.flow.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.preparationFailed)
        await running.value
        reader.published()

        #expect(reader.flow.state == .failed(message: "That file could not be opened for inspection."))
        #expect(reader.section == .details)
    }

    /// **The picker dismissed.** The flow leaves `.report(A)`, passes through `.working`, and returns to
    /// `.report(A)` — and the reader must not be sent to the overview for having changed their mind.
    /// This is the case `WorkspaceNavigation`'s memory exists for.
    @Test("dismissing the picker leaves the reader exactly where they were")
    func cancellingTheSelectionDoesNotMoveTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.measurements)
        let before = reader.flow.state

        let second = ImportFlowComparisonTests.ControllableAction()
        let running = Task { await reader.flow.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        reader.published() // working
        second.finish(.cancelled)
        await running.value
        reader.published()

        #expect(reader.flow.state == before, "the flow did not return the reader to their report")
        #expect(reader.section == .measurements, "dismissing the picker moved the reader")
    }

    // MARK: - Scenarios 3, 4 and 5 — a comparison moves nobody

    @Test("a comparison loading, settling and being dismissed all leave the reader where they are")
    func aComparisonNeverMovesTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.waveform)

        let second = ImportFlowComparisonTests.ControllableAction()
        let running = Task { await reader.flow.compare(using: second.run) }
        await second.waitUntilStarted()

        #expect(reader.flow.comparison == .loading)
        reader.published()
        #expect(reader.section == .waveform, "a comparison starting moved the reader")

        let b = report("b.wav")
        second.finish(sending: [.report(b)], .inspected(b, analyses: nothingSettled))
        await running.value
        guard case .ready = reader.flow.comparison else {
            Issue.record("the comparison did not settle")
            return
        }
        reader.published()
        #expect(reader.section == .waveform, "a comparison settling moved the reader")

        reader.flow.dismissComparison()
        #expect(reader.flow.comparison == .none)
        reader.published()
        #expect(reader.section == .waveform, "dismissing a comparison moved the reader")
    }

    @Test("a second file that could not be opened leaves the reader where they are")
    func aFailedComparisonDoesNotMoveTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.waveform)

        let second = ImportFlowComparisonTests.ControllableAction()
        let running = Task { await reader.flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.preparationFailed)
        await running.value
        reader.published()

        #expect(reader.flow.comparison == .failed(message: "That file could not be opened for comparison."))
        #expect(reader.section == .waveform)
    }

    @Test("dismissing the comparison picker leaves the reader where they are")
    func aCancelledComparisonDoesNotMoveTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.spectrum)

        let second = ImportFlowComparisonTests.ControllableAction()
        let running = Task { await reader.flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.cancelled)
        await running.value
        reader.published()

        #expect(reader.flow.comparison == .none)
        #expect(reader.section == .spectrum)
    }

    @Test("a comparison superseded by another leaves the reader where they are")
    func aSupersededComparisonDoesNotMoveTheReader() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.waveform)

        let first = ImportFlowComparisonTests.ControllableAction()
        let runningFirst = Task { await reader.flow.compare(using: first.run) }
        await first.waitUntilStarted()
        reader.published()
        #expect(reader.section == .waveform)

        let c = report("c.wav")
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(c)])
        let runningSecond = Task { await reader.flow.compare(using: second.run) }
        await second.waitUntilStarted()

        // The first operation finishes after being superseded; its result is dropped as stale.
        first.finish(.inspected(report("b.wav"), analyses: nothingSettled))
        await runningFirst.value
        reader.published()
        #expect(reader.section == .waveform, "a superseded comparison moved the reader")

        second.finish(.inspected(c, analyses: nothingSettled))
        await runningSecond.value
        reader.published()
        #expect(reader.section == .waveform)
    }

    /// ADR-0026 §5's third row and its exception: a comparison ending moves nobody **except** where the
    /// primary was replaced, which is the row above — and that row wins.
    @Test("replacing the primary while a comparison is settled returns the reader to the overview")
    func replacingThePrimaryUnderneathAComparisonReturnsToTheOverview() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.details)

        let b = report("b.wav")
        let comparison = ImportFlowComparisonTests.ControllableAction(delivering: [.report(b)])
        let comparing = Task { await reader.flow.compare(using: comparison.run) }
        await comparison.waitUntilStarted()
        comparison.finish(.inspected(b, analyses: nothingSettled))
        await comparing.value
        reader.published()
        #expect(reader.section == .details)

        let c = report("c.wav")
        let replacement = ImportFlowComparisonTests.ControllableAction(delivering: [.report(c)])
        let replacing = Task { await reader.flow.inspectDroppedSource(using: replacement.run) }
        await replacement.waitUntilStarted()
        replacement.finish(.inspected(c, analyses: nothingSettled))
        await replacing.value
        reader.published()

        #expect(reader.flow.comparison == .none, "the new primary did not end the comparison")
        #expect(reader.section == .overview)
    }

    // MARK: - Scenarios 9 and 10 — the five are five whatever happened, and whatever the window

    /// **An absent or failed artefact never removes its section.** The sections are a closed list that no
    /// inspection state is an input to, so this holds by construction — and the test drives the states
    /// that would break it if it did not. What each section then *says* about the absence is the
    /// existing report surface's, unchanged by R1 and covered by `WaveformPresentationTests` and
    /// `SpectrogramCopyTests`.
    ///
    /// Scenario 10 is the same claim from the other side: the identity of the five is a constant, so no
    /// layout — narrow window included — can narrow, rename or reorder them. R1 asserts the model; the
    /// responsive pass is R9's.
    @Test("every section stays reachable and keeps its name, whatever became of the artefacts")
    func absentArtefactsRemoveNoSection() async {
        let states: [(WaveformOutcome, SpectrogramOutcome)] = [
            (.unavailable, .unavailable),
            (.failed(message: "The waveform for this file could not be produced."), .unavailable),
            (.unavailable, .failed(message: "The spectrogram for this file could not be produced.")),
            (.cancelled, .cancelled),
        ]

        for (waveform, spectrogram) in states {
            let a = report("a.wav")
            let action = NarratingAction(
                [.report(a), .waveform(waveform), .spectrogram(spectrogram)],
                then: .inspected(
                    a,
                    analyses: InspectionAnalyses(
                        waveform: waveform, spectrogram: spectrogram, signalLevelMetrics: .unavailable,
                        truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable
                    )
                )
            )
            let flow = ImportFlowModel(action: action.run)
            let reader = Reader(flow)
            action.afterEachUpdate = { reader.published() }
            await flow.selectAndInspect()
            reader.published()

            #expect(WorkspaceSection.allCases.count == 5)
            #expect(
                WorkspaceSection.allCases.map(WorkspaceCopy.label(for:))
                    == ["Overview", "Measurements", "Waveform", "Spectrum", "Details"]
            )
            for section in WorkspaceSection.allCases {
                reader.select(section)
                #expect(reader.section == section)
            }
        }
    }

    // MARK: - Scenario 8 — relaunch

    /// A new workspace is a new launch, and it begins at the overview knowing nothing of the session
    /// before it. Nothing was written anywhere for it to know.
    @Test("a new workspace begins at the overview, whatever the last one was reading")
    func relaunchBeginsAtTheOverview() async {
        let reader = await windowShowing(report("a.wav"))
        reader.select(.spectrum)
        #expect(reader.section == .spectrum)

        #expect(WorkspaceNavigation().section == .overview)
    }
}
