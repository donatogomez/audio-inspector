import Testing

import AudioInspectorDomain
@testable import FeatureImport

/// The drop half of the import flow: a source the composition root already accepted arrives as an
/// opaque action, and refusals travel on a channel that never touches the flow state. No panel, no
/// filesystem, no SwiftUI.
///
/// The panel's own behaviour is covered unchanged by `ImportFlowModelTests`, which was not modified —
/// that is the regression criterion for this refactor.
@MainActor
@Suite("Feature — import flow drops")
struct ImportFlowDropTests {

    @MainActor
    final class ScriptedAction {
        private(set) var callCount = 0
        private let outcome: SourceInspectionOutcome
        init(_ outcome: SourceInspectionOutcome) { self.outcome = outcome }
        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            callCount += 1
            return outcome
        }
    }

    /// An action that suspends until released — to observe the in-flight state.
    @MainActor
    final class ControllableAction {
        private(set) var callCount = 0
        private var continuation: CheckedContinuation<SourceInspectionOutcome, Never>?
        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            callCount += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ outcome: SourceInspectionOutcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }

    /// Fails the test if it ever runs — proves a refusal starts nothing.
    @MainActor
    final class UnreachableAction {
        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            Issue.record("a rejected drop must not start an inspection")
            return .cancelled
        }
    }

    private func makeReport(named name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 1_024,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(sampleRate: .available(44_100)),
            warnings: [],
            status: .completed
        )
    }

    // MARK: - A dropped source runs the same transitions as the panel

    @Test func aDroppedSourceEndsInAReportAndRunsItsActionExactlyOnce() async {
        let report = makeReport(named: "dropped.wav")
        let action = ScriptedAction(.inspected(report, waveform: .unavailable, spectrogram: .unavailable))
        let model = ImportFlowModel(action: UnreachableAction().run) // the panel must stay unused

        await model.inspectDroppedSource(using: action.run)

        #expect(model.state == .report(InspectionPresentation(report: report, waveform: .unavailable, spectrogram: .unavailable)))
        #expect(action.callCount == 1)
    }

    @Test func aDroppedSourceReplacesAnExistingReportWhenItCompletes() async {
        let first = makeReport(named: "first.wav")
        let second = makeReport(named: "second.wav")
        let model = ImportFlowModel(action: ScriptedAction(.inspected(first, waveform: .unavailable, spectrogram: .unavailable)).run)

        await model.selectAndInspect()
        #expect(model.state == .report(InspectionPresentation(report: first, waveform: .unavailable, spectrogram: .unavailable)))

        await model.inspectDroppedSource(using: ScriptedAction(.inspected(second, waveform: .unavailable, spectrogram: .unavailable)).run)
        #expect(model.state == .report(InspectionPresentation(report: second, waveform: .unavailable, spectrogram: .unavailable)))
    }

    @Test func aGlobalFailureFromADropStaysAReport() async {
        let error = InspectionError(code: .fileUnreadable, message: "unreadable")
        let failed = InspectionReport(
            file: AudioFileReference(
                displayName: "broken.wav",
                fileExtension: "wav",
                sizeBytes: nil,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: "broken.wav", locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(),
            warnings: [],
            status: .failed(error)
        )
        let model = ImportFlowModel(action: UnreachableAction().run)

        await model.inspectDroppedSource(using: ScriptedAction(.inspected(failed, waveform: .unavailable, spectrogram: .unavailable)).run)

        // The domain models a global failure; the flow must not convert it into its own `failed`.
        #expect(model.state == .report(InspectionPresentation(report: failed, waveform: .unavailable, spectrogram: .unavailable)))
    }

    @Test func aDropIsIgnoredWhileAnInspectionIsInFlight() async {
        let running = ControllableAction()
        let model = ImportFlowModel(action: running.run)
        let report = makeReport(named: "clip.wav")

        let first = Task { await model.selectAndInspect() }
        while running.callCount == 0 { await Task.yield() }
        #expect(model.state == .working)

        await model.inspectDroppedSource(using: UnreachableAction().run) // ignored
        #expect(running.callCount == 1)

        running.finish(.inspected(report, waveform: .unavailable, spectrogram: .unavailable))
        await first.value
        #expect(model.state == .report(InspectionPresentation(report: report, waveform: .unavailable, spectrogram: .unavailable)))
    }

    // MARK: - Rejections are orthogonal to the state

    @Test(arguments: DropRejection.allCases)
    func aRejectionNeverChangesTheStateFromIdle(_ rejection: DropRejection) {
        let model = ImportFlowModel(action: UnreachableAction().run)

        model.reject(rejection)

        #expect(model.state == .idle)
        #expect(model.dropRejection == rejection)
    }

    @Test(arguments: DropRejection.allCases)
    func aRejectionPreservesAnExistingReport(_ rejection: DropRejection) async {
        let report = makeReport(named: "kept.wav")
        let model = ImportFlowModel(action: ScriptedAction(.inspected(report, waveform: .unavailable, spectrogram: .unavailable)).run)

        await model.selectAndInspect()
        model.reject(rejection)

        #expect(model.state == .report(InspectionPresentation(report: report, waveform: .unavailable, spectrogram: .unavailable))) // the report survives the refusal
        #expect(model.dropRejection == rejection)
    }

    @Test func aRejectionIsNeverAFlowFailure() {
        let model = ImportFlowModel(action: UnreachableAction().run)

        model.reject(.multipleItems)

        if case .failed = model.state {
            Issue.record("a refusal must not become a flow failure")
        }
    }

    // MARK: - Clearing

    @Test func avalidDropClearsThePendingRejection() async {
        let report = makeReport(named: "clip.wav")
        let model = ImportFlowModel(action: UnreachableAction().run)
        model.reject(.multipleItems)

        await model.inspectDroppedSource(using: ScriptedAction(.inspected(report, waveform: .unavailable, spectrogram: .unavailable)).run)

        #expect(model.dropRejection == nil)
    }

    @Test func aValidPanelSelectionClearsThePendingRejection() async {
        let report = makeReport(named: "clip.wav")
        let model = ImportFlowModel(action: ScriptedAction(.inspected(report, waveform: .unavailable, spectrogram: .unavailable)).run)
        model.reject(.unsupportedItem)

        await model.selectAndInspect()

        #expect(model.dropRejection == nil)
    }

    @Test func aRejectionIsNotClearedByAnIgnoredDrop() async {
        let running = ControllableAction()
        let model = ImportFlowModel(action: running.run)

        let first = Task { await model.selectAndInspect() }
        while running.callCount == 0 { await Task.yield() }
        model.reject(.inspectionInProgress)

        await model.inspectDroppedSource(using: UnreachableAction().run) // ignored while working
        #expect(model.dropRejection == .inspectionInProgress) // still shown

        running.finish(.cancelled)
        await first.value
    }

    @Test func clearingRemovesTheRejection() {
        let model = ImportFlowModel(action: UnreachableAction().run)
        model.reject(.unsupportedItem)

        model.clearDropRejection()

        #expect(model.dropRejection == nil)
    }

    // MARK: - Presentation, modelled as data (no snapshots)

    @Test func everyRejectionHasItsOwnPresentableMessage() {
        #expect(DropRejection.multipleItems.message == "Drop one file at a time.")
        #expect(DropRejection.unsupportedItem.message == "That item cannot be inspected.")
        #expect(DropRejection.inspectionInProgress.message == "Wait for the current inspection to finish.")

        // Messages disclose no location and no framework detail, and none is reused.
        let messages = Set(DropRejection.allCases.map(\.message))
        #expect(messages.count == DropRejection.allCases.count)
        for message in messages {
            #expect(!message.contains("/"))
            #expect(!message.lowercased().contains("url"))
        }
    }
}
