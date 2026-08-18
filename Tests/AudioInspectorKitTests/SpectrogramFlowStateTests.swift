import AudioInspectorDomain
import FeatureImport
import Foundation
import Testing

// The spectrogram as flow state: how it settles, how it stays out of the report's way, and how a
// superseded operation's result is kept from landing on the file the user is now looking at.
//
// Every sequence here is driven by explicit signals on a scripted action. No sleeps, no polling, no
// assumption about the order two tasks are scheduled in.

/// An action whose report and each visualisation are released by the test, one at a time.
///
/// It is the only way to observe progressive delivery honestly: the production coordinator settles
/// them in its own order, and a test that raced it would be asserting the scheduler.
@MainActor
private final class SteppedAction {
    let report: InspectionReport
    /// Instructions that arrived before the action reached its suspension point. Recorded rather than
    /// dropped, so a test never depends on how many scheduling hops it takes to get there — the same
    /// approach `SuspendedAction` uses in the waveform suite.
    private var pending: [InspectionUpdate] = []
    private var pendingOutcome: SourceInspectionOutcome?
    private var gate: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    /// Resumed once everything released so far has been handed to the handler, which is what lets
    /// `deliver` return only after the update has actually been applied. See `release(_:)`.
    private var applied: CheckedContinuation<Void, Never>?
    private(set) var runCount = 0

    init(report: InspectionReport) {
        self.report = report
    }

    /// Applies whatever the test has released, then waits for more. The handler is used strictly
    /// within the call — not `@escaping` — which keeps the production contract as tight as it is.
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
            // Everything released has now been applied. Releasing the waiting `deliver` here — rather
            // than leaving it to guess — is the whole handshake.
            applied?.resume()
            applied = nil
            await withCheckedContinuation { gate = $0 }
        }
    }

    /// Suspends until this action has actually been invoked.
    func waitUntilStarted() async {
        guard runCount == 0 else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func deliverReport() async { await release(.report(report)) }
    func deliver(waveform: WaveformOutcome) async { await release(.waveform(waveform)) }
    func deliver(spectrogram: SpectrogramOutcome) async { await release(.spectrogram(spectrogram)) }

    /// Releases an update and returns **only once the handler has been called with it**.
    ///
    /// Resuming the action's gate makes it *runnable*, not *run*: both tasks are then queued on the main
    /// actor and their order is unspecified, so the `await Task.yield()` this used to rely on lost the
    /// race roughly once in three hundred deliveries — measured, and enough to fail these suites a few
    /// runs in a hundred. The return trip is the fix: the action resumes `applied` at the point where it
    /// has drained everything, which is a real happens-before rather than a hope about scheduling.
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
@Suite("Feature — spectrogram flow state")
struct SpectrogramFlowStateTests {
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

    private func spectrogram(columns: Int = 2, bands: Int = 2) throws -> Spectrogram {
        try #require(Spectrogram(
            values: [Float](repeating: -60, count: columns * bands),
            columnCount: columns, bandCount: bands,
            sampleRate: 44_100, frameCount: 44_100, channelCount: 1
        ))
    }

    private func envelope() throws -> WaveformEnvelope {
        try #require(WaveformEnvelope.empty(channelCount: 2))
    }

    private func presentation(of model: ImportFlowModel) -> InspectionPresentation? {
        guard case let .report(presentation) = model.state else { return nil }
        return presentation
    }

    // MARK: States

    /// The report appears with **both** visualisations still loading. Neither withholds it.
    @Test("the report appears while both visualisations are still loading")
    func theReportDoesNotWaitForEither() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()

        let shown = try #require(presentation(of: model))
        #expect(shown.report == action.report)
        #expect(shown.waveform == .loading)
        #expect(shown.spectrogram == .loading)

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await running.value
    }

    /// Each settled outcome maps to its own state, and none of them disturbs the report.
    @Test(
        "each settled outcome becomes its own state, leaving the report alone",
        arguments: [
            (SpectrogramOutcome.unavailable, SpectrogramState.unavailable),
            (.failed(message: "It could not be produced."), .failed(message: "It could not be produced.")),
        ]
    )
    func settledOutcomesBecomeStates(outcome: SpectrogramOutcome, expected: SpectrogramState) async throws {
        let shown = try await settle(spectrogram: outcome)
        #expect(shown.spectrogram == expected)
        #expect(shown.report.status == .completed, "the report was disturbed")
    }

    @Test("an available spectrogram replaces loading without touching the report")
    func availableSettles() async throws {
        let model = try spectrogram()
        let shown = try await settle(spectrogram: .available(model))
        #expect(shown.spectrogram == .available(model))
        #expect(shown.report.status == .completed, "the report was disturbed")
    }

    /// Drives one operation to the point where the given outcome has settled, and returns what is shown.
    private func settle(spectrogram outcome: SpectrogramOutcome) async throws -> InspectionPresentation {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()
        await action.deliver(spectrogram: outcome)

        let shown = try #require(presentation(of: model))
        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: outcome, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await running.value
        return shown
    }

    /// Cancellation has no visible state. A result belonging to an operation the user replaced is
    /// discarded rather than rendered as an absence of energy in their file.
    @Test("a cancelled spectrogram leaves the state untouched rather than showing an absence")
    func cancelledIsNotVisible() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()
        await action.deliver(spectrogram: .cancelled)

        #expect(presentation(of: model)?.spectrogram == .loading, "cancellation was rendered as a state")
        #expect(SpectrogramState(.cancelled) == nil, "cancellation has no state to settle into")

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .cancelled, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await running.value
    }

    // MARK: Progressive delivery, in both orders

    /// Either visualisation may finish first, and the one that does is shown immediately without
    /// waiting for the other.
    @Test("the waveform can settle first, leaving the spectrogram loading")
    func theWaveformCanArriveFirst() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()
        await action.deliver(waveform: .available(try envelope()))

        let shown = try #require(presentation(of: model))
        #expect(shown.waveform == .available(try envelope()))
        #expect(shown.spectrogram == .loading, "the spectrogram was settled by the waveform's arrival")

        action.finish(.inspected(action.report, waveform: .available(try envelope()), spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await running.value
    }

    @Test("the spectrogram can settle first, leaving the waveform loading")
    func theSpectrogramCanArriveFirst() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()
        await action.deliver(spectrogram: .available(try spectrogram()))

        let shown = try #require(presentation(of: model))
        #expect(shown.spectrogram == .available(try spectrogram()))
        #expect(shown.waveform == .loading, "the waveform was settled by the spectrogram's arrival")

        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .available(try spectrogram()), signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await running.value
    }

    /// One failing changes nothing about the other, and nothing about the report.
    @Test("a failing spectrogram leaves an available waveform and the report alone")
    func failuresDoNotCross() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()
        await action.deliver(waveform: .available(try envelope()))
        await action.deliver(spectrogram: .failed(message: "no model"))

        let shown = try #require(presentation(of: model))
        #expect(shown.waveform == .available(try envelope()))
        #expect(shown.spectrogram == .failed(message: "no model"))
        #expect(shown.report == action.report, "the report changed")

        action.finish(.inspected(
            action.report, waveform: .available(try envelope()), spectrogram: .failed(message: "no model"),
            signalLevelMetrics: .unavailable, truePeak: .unavailable
        , loudness: .unavailable))
        await running.value
    }

    /// The settled state survives the final outcome: a value already shown is not walked back.
    @Test("the final outcome does not overwrite what the channel already settled")
    func theOutcomeDoesNotWalkBackSettledState() async throws {
        let action = SteppedAction(report: report())
        let model = ImportFlowModel(action: action.run)

        let running = Task { await model.selectAndInspect() }
        await action.waitUntilStarted()
        await action.deliverReport()
        await action.deliver(spectrogram: .available(try spectrogram()))

        // A final outcome that disagrees — as a cancelled one would — must not replace the model
        // already on screen with a fallback.
        action.finish(.inspected(action.report, waveform: .unavailable, spectrogram: .cancelled, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await running.value

        #expect(presentation(of: model)?.spectrogram == .available(try spectrogram()))
    }

    // MARK: Operation identity and stale results

    /// A result from a superseded operation must not land on the current one. The second selection is
    /// accepted because the first had already produced its report — the inspection was over and only
    /// the visualisations were pending.
    @Test("a late spectrogram from a replaced operation is discarded")
    func aStaleSpectrogramIsDropped() async throws {
        let first = SteppedAction(report: report(named: "first"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        await first.waitUntilStarted()
        await first.deliverReport()
        #expect(presentation(of: model)?.report.file.displayName == "first")

        // The user picks another file while the first's visualisations are still pending.
        let second = SteppedAction(report: report(named: "second"))
        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        await second.waitUntilStarted()
        await second.deliverReport()
        #expect(presentation(of: model)?.report.file.displayName == "second")

        // The first operation now finishes, late. Nothing of it may reach the second's presentation.
        await first.deliver(spectrogram: .available(try spectrogram()))
        await first.deliver(waveform: .available(try envelope()))
        first.finish(.inspected(first.report, waveform: .available(try envelope()), spectrogram: .available(try spectrogram()), signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        // The stale operation is awaited to completion, so what follows is asserted against a first
        // operation that is entirely over rather than one that merely had a scheduling hop to finish in.
        await firstRun.value

        let shown = try #require(presentation(of: model))
        #expect(shown.report.file.displayName == "second", "a stale operation replaced the current report")
        #expect(shown.spectrogram == .loading, "a stale spectrogram landed on the current operation")
        #expect(shown.waveform == .loading, "a stale waveform landed on the current operation")

        second.finish(.inspected(second.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await secondRun.value
    }

    /// The distinction the accepted specification draws, restated for the spectrogram: while the
    /// **inspection** is running (`.working`) a second selection is ignored, and at most one inspection
    /// exists at a time. Once the report exists, the inspection is over and a new selection is accepted.
    @Test("a selection during the inspection itself is ignored, not queued")
    func aSelectionDuringWorkingIsIgnored() async throws {
        let first = SteppedAction(report: report(named: "first"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        // The action is invoked only after `inspect` has set `.working`, so its own start signal is
        // proof the transition happened — where a `Task.yield()` merely hoped one hop was enough.
        await first.waitUntilStarted()
        #expect(model.state == .working)

        // No report yet, so the inspection is still running: this must not start a second one.
        let second = SteppedAction(report: report(named: "second"))
        await model.inspectDroppedSource(using: second.run)

        #expect(second.runCount == 0, "a second inspection started while one was running")
        #expect(model.state == .working)

        await first.deliverReport()
        first.finish(.inspected(first.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await firstRun.value
        #expect(presentation(of: model)?.report.file.displayName == "first")
    }

    /// And its counterpart: once the report exists the pending visualisations may be superseded.
    @Test("a selection after the report replaces the pending visualisations")
    func aSelectionAfterTheReportIsAccepted() async throws {
        let first = SteppedAction(report: report(named: "first"))
        let model = ImportFlowModel(action: first.run)

        let firstRun = Task { await model.selectAndInspect() }
        await first.waitUntilStarted()
        await first.deliverReport()

        let second = SteppedAction(report: report(named: "second"))
        let secondRun = Task { await model.inspectDroppedSource(using: second.run) }
        // Waiting for the action to actually be invoked, rather than hoping one scheduling hop was
        // enough: a `Task.yield()` here inferred "it started" from nothing, and lost that bet roughly
        // one run in ten.
        await second.waitUntilStarted()

        #expect(second.runCount == 1, "the second selection was refused after the report existed")

        await second.deliverReport()
        second.finish(.inspected(second.report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await secondRun.value
        first.finish(.inspected(first.report, waveform: .cancelled, spectrogram: .cancelled, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable))
        await firstRun.value

        #expect(presentation(of: model)?.report.file.displayName == "second")
    }
}

// MARK: - Boundaries

@Suite("Feature — spectrogram boundaries")
struct SpectrogramFeatureBoundaryTests {
    private func imports(of directory: String) throws -> [(file: String, line: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = FileManager.default
            .enumerator(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.flatMap { file -> [(String, String)] in
            try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n").map(String.init)
                .filter { $0.hasPrefix("import ") }
                .map { (file.lastPathComponent, $0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    /// Boundary rule 10, restated after the spectrogram crossed into the feature: a feature module may
    /// gain neither a `URL`-bearing framework nor AppKit. The location stays in the composition root.
    @Test("no feature module imports AppKit or a media framework", arguments: ["Sources/FeatureImport", "Sources/FeatureAnalysis"])
    func featuresStayFree(module: String) throws {
        let forbidden = ["AppKit", "AVFoundation", "AudioToolbox", "CoreAudio", "Accelerate", "AudioInspectorMedia", "AudioInspectorAnalysis"]
        let found = try imports(of: module).filter { line in forbidden.contains { line.line.contains($0) } }
        #expect(found.isEmpty, "\(module) imported: \(found)")
    }

    /// The features never learn a location. `URL` reaches neither of them, in any signature or body.
    @Test("no feature module mentions URL", arguments: ["Sources/FeatureImport", "Sources/FeatureAnalysis"])
    func featuresNeverSeeALocation(module: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = FileManager.default
            .enumerator(at: root.appendingPathComponent(module), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let offending = source.split(separator: "\n").map(String.init).filter { line in
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { return false }
                return code.contains("URL")
            }
            #expect(offending.isEmpty, "\(file.lastPathComponent) mentions URL: \(offending)")
        }
    }

    /// The features do not import one another: the composition root translates between their
    /// vocabularies, exactly as it already does for the waveform.
    @Test("the feature modules do not import each other")
    func featuresDoNotImportEachOther() throws {
        #expect(try imports(of: "Sources/FeatureImport").allSatisfy { !$0.line.contains("FeatureAnalysis") })
        #expect(try imports(of: "Sources/FeatureAnalysis").allSatisfy { !$0.line.contains("FeatureImport") })
    }
}
