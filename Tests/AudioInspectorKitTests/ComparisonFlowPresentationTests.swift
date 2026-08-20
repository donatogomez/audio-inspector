import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis
@testable import FeatureImport

// The flow's comparison state as the surface sees it: the translation the composition root performs,
// and what a view would be handed under each state. Still no SwiftUI — what is asserted is the value,
// not a rendering.

/// The translation the composition root performs, and the surface's behaviour under each flow state.
/// Still no SwiftUI: what is asserted is the presentation value a view would be handed.
@MainActor
@Suite("Feature — comparison presentation from the flow")
struct ComparisonFlowPresentationTests {

    /// The same translation `RootView` performs, kept here so the mapping is exercised without a view.
    private func presentation(for state: ImportFlowModel.ComparisonState) -> ComparisonPresentation {
        switch state {
        case .none: .none
        case .loading: .loading
        case let .ready(comparison, _): .ready(comparison)
        case let .failed(message): .failed(message: message)
        }
    }

    private func report(_ name: String, sampleRate: Int = 44_100) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name,
                fileExtension: "wav",
                sizeBytes: 2_048,
                modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(
                container: .available("wav"),
                sampleRate: .available(sampleRate)
            ),
            warnings: [],
            status: .completed
        )
    }

    private func flowShowingAReport(
        _ primary: InspectionReport
    ) async -> (ImportFlowModel, ImportFlowComparisonTests.ControllableAction, Task<Void, Never>) {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(primary)])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        return (flow, action, running)
    }

    /// With a report and no comparison, the surface shows no comparison at all — the report reads
    /// exactly as it does without this feature.
    @Test("a report with no comparison presents nothing extra")
    func aReportWithNoComparisonPresentsNothing() async {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        #expect(presentation(for: flow.comparison) == .none)

        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// While the second file is being inspected the surface says so **in words**, and the report stays
    /// entirely visible.
    @Test("an in-flight second file presents as loading, with the report intact")
    func anInFlightSecondFilePresentsAsLoading() async {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let second = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()

        #expect(presentation(for: flow.comparison) == .loading)
        #expect(ComparisonCopy.loading == "Inspecting the second file…")
        // The report is untouched, so everything the reader was looking at is still there.
        guard case let .report(shown) = flow.state else { Issue.record("expected a report"); return }
        #expect(shown.report == primary)

        second.finish(.cancelled)
        await comparing.value
        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// The second report turns the surface into a full comparison with its eight rows.
    @Test("the second report presents a comparison of every property")
    func theSecondReportPresentsAComparison() async {
        let primary = report("a.wav", sampleRate: 44_100)
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let other = report("b.wav", sampleRate: 48_000)
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(other)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()

        guard case let .ready(comparison) = presentation(for: flow.comparison) else {
            Issue.record("expected a ready comparison")
            return
        }
        let rows = ComparisonFormatter.rows(for: comparison)
        #expect(rows.count == ReportPropertyFormatter.displays(for: other.properties).count)
        #expect(rows.first { $0.name == "Sample rate" }?.outcome.text == "Different")

        second.finish(.inspected(other, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparing.value
        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// Replacing the second file replaces what the surface shows, and only that.
    @Test("replacing the second file replaces the comparison shown")
    func replacingTheSecondFileReplacesTheComparison() async {
        let primary = report("a.wav", sampleRate: 44_100)
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report("b.wav", sampleRate: 48_000)
        let bAction = ImportFlowComparisonTests.ControllableAction(delivering: [.report(b)])
        let comparingB = Task { await flow.compare(using: bAction.run) }
        await bAction.waitUntilStarted()
        bAction.finish(.inspected(b, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparingB.value

        let c = report("c.wav", sampleRate: 44_100)
        let cAction = ImportFlowComparisonTests.ControllableAction(delivering: [.report(c)])
        let comparingC = Task { await flow.compare(using: cAction.run) }
        await cAction.waitUntilStarted()
        cAction.finish(.inspected(c, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparingC.value

        guard case let .ready(comparison) = presentation(for: flow.comparison) else {
            Issue.record("expected a ready comparison")
            return
        }
        #expect(comparison.second.file.displayName == "c.wav")
        #expect(comparison.sampleRate == .same(44_100))

        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// Closing the comparison removes only the comparison.
    @Test("dismissing removes the comparison and nothing else")
    func dismissingRemovesOnlyTheComparison() async {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report("b.wav")
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(b)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(b, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparing.value

        flow.dismissComparison()

        #expect(presentation(for: flow.comparison) == .none)
        guard case let .report(shown) = flow.state else { Issue.record("expected a report"); return }
        #expect(shown.report == primary)

        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// A second file that could not be opened presents as a failure **of the comparison**, with a
    /// message, while the report on screen stays exactly as it was.
    @Test("a second file that cannot be opened presents a comparison failure, not a report failure")
    func aFailedSecondFilePresentsAsAComparisonFailure() async {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let second = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.preparationFailed)
        await comparing.value

        guard case let .failed(message) = presentation(for: flow.comparison) else {
            Issue.record("expected a failed comparison")
            return
        }
        #expect(!message.isEmpty)
        #expect(ComparisonCopy.failedHeadline == "The second file could not be inspected.")
        guard case let .report(shown) = flow.state else { Issue.record("expected a report"); return }
        #expect(shown.report == primary)
        #expect(shown.report.status == .completed)

        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// **Comparing a file with itself shows agreement field by field and claims nothing more.** No row
    /// and no piece of copy says the two selections are one file.
    @Test("comparing a file with itself agrees per field without claiming they are one file")
    func comparingAFileWithItself() async {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(primary)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparing.value

        guard case let .ready(comparison) = presentation(for: flow.comparison) else {
            Issue.record("expected a ready comparison")
            return
        }
        let rows = ComparisonFormatter.rows(for: comparison)
        #expect(rows.first { $0.name == "Sample rate" }?.outcome.text == "Same")

        // Nothing anywhere claims the two are the same file.
        let everySentence = rows.map(\.accessibilityLabel) + [ComparisonCopy.subtitle, ComparisonCopy.title]
        for sentence in everySentence {
            #expect(!sentence.lowercased().contains("same file"))
            #expect(!sentence.lowercased().contains("identical file"))
        }

        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }

    /// The report's own visualisations arrive late, during and after a comparison, and are still shown.
    @Test("the report's late visualisations remain visible through a comparison")
    func lateVisualisationsRemainVisible() async throws {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        let b = report("b.wav")
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(b)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(b, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparing.value

        let envelope = try #require(WaveformEnvelope.empty(channelCount: 2))
        primaryAction.finish(
            sending: [.waveform(.available(envelope))],
            .inspected(primary, analyses: InspectionAnalyses(waveform: .available(envelope), spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable))
        )
        await running.value

        guard case let .report(shown) = flow.state else { Issue.record("expected a report"); return }
        #expect(shown.waveform == .available(envelope))
        // And the comparison is still on screen.
        if case .ready = presentation(for: flow.comparison) {} else {
            Issue.record("the comparison disappeared")
        }
    }

    /// **A comparison changes nothing about the report it compares against**, which is what keeps the
    /// export identical: the exporter is handed the same value whether or not a comparison exists.
    @Test("the report handed to the exporter is unchanged by any comparison")
    func theReportForExportIsUnchanged() async {
        let primary = report("a.wav")
        let (flow, primaryAction, running) = await flowShowingAReport(primary)

        guard case let .report(before) = flow.state else { Issue.record("expected a report"); return }

        let b = report("b.wav", sampleRate: 96_000)
        let second = ImportFlowComparisonTests.ControllableAction(delivering: [.report(b)])
        let comparing = Task { await flow.compare(using: second.run) }
        await second.waitUntilStarted()
        second.finish(.inspected(b, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await comparing.value

        guard case let .report(after) = flow.state else { Issue.record("expected a report"); return }
        #expect(after.report == before.report)
        #expect(after.report.properties == before.report.properties)
        #expect(after.report.warnings == before.report.warnings)
        #expect(after.report.status == before.report.status)

        primaryAction.finish(.inspected(primary, analyses: InspectionAnalyses(waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable)))
        await running.value
    }
}
