import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureImport

// Group 9's sixth subject: **a missing drawing never damages a report** (task 9.7).
//
// The property is a negative one and therefore easy to state loosely. What is asserted here is the
// exact form the task names: with either file's artefact absent or failed, **both** reports keep the
// same properties, the same warnings and the same global status they would have had, and **no
// inspection warning is emitted for the drawing** — and the pairing still represents the absence
// rather than hiding it.
//
// Every case is compared against **one** baseline: the same two files with all four drawings
// available. So *unchanged* means unchanged from a state that really exists, not merely internally
// consistent.
//
// The matrix covers what the task enumerates and what the domain distinguishes: a waveform absent, a
// waveform failed, a spectral model absent, a spectral model failed, and the model with **no
// columns** — a file shorter than one analysis window, which is an answer rather than an absence and
// is exactly the case a careless collapse would turn into one. Each is applied to the first file, to
// the second, and to both.

@MainActor
@Suite("Report — a missing drawing changes nothing about either report")
struct VisualAbsenceReportIsolationTests {

    // MARK: - The two files, and the drawings that vary

    /// A report with warnings and a not-`completed` status, so *unchanged* is asserted over a report
    /// that has something to lose. A clean report would pass this suite for the wrong reason.
    /// The two reports, built **once** and reused by every case.
    ///
    /// Not a convenience: `AudioFileReference` carries an ephemeral `id` that is new on every
    /// construction, so a helper that rebuilt them would make every comparison of a `FileComparison`
    /// fail on an identifier that is deliberately not part of what a report says. Building them once
    /// is what lets *unchanged* mean unchanged.
    static let firstReport = makeReport("a.wav")
    static let secondReport = makeReport("b.wav")

    private static func makeReport(_ name: String) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: nil,
                modifiedAt: date("2026-06-12T09:03:00Z"),
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: allAvailableProperties(),
            warnings: [
                InspectionWarning(
                    code: .metadataSizeUnavailable, field: "sizeBytes", kind: .unavailable,
                    message: "File size in bytes is not available for this file."
                ),
                InspectionWarning(
                    code: .propertyUncertain, field: "bitRate", kind: .uncertain,
                    message: "The bit rate is an estimate."
                ),
            ],
            status: .partial(message: "Some properties could not be read.")
        )
    }

    /// What a drawing can have become, by the name the task uses for it.
    enum Drawing: CaseIterable, Sendable {
        case available
        case waveformUnavailable
        case waveformFailed
        case spectrogramUnavailable
        case spectrogramFailed
        case spectrogramTooShort   // a model with no columns: an answer, not an absence

        var waveform: WaveformOutcome {
            switch self {
            case .waveformUnavailable: .unavailable
            case .waveformFailed: .failed(message: "Producing it did not succeed.")
            default: .available(WaveformEnvelope(
                buckets: [WaveformBucket(minimum: -0.5, maximum: 0.5)!],
                frameCount: 2_048, channelCount: 2
            )!)
            }
        }

        func spectrogram(rate: Double) -> SpectrogramOutcome {
            switch self {
            case .spectrogramUnavailable: .unavailable
            case .spectrogramFailed: .failed(message: "Producing it did not succeed.")
            case .spectrogramTooShort: .available(Spectrogram(
                values: [], columnCount: 0, bandCount: 0,
                sampleRate: rate, frameCount: 0, channelCount: 2
            )!)
            default: .available(Spectrogram(
                values: [-30, -40], columnCount: 1, bandCount: 2,
                sampleRate: rate, frameCount: 2_048, channelCount: 2
            )!)
            }
        }
    }

    private func analyses(_ drawing: Drawing, rate: Double) -> InspectionAnalyses {
        InspectionAnalyses(
            waveform: drawing.waveform,
            spectrogram: drawing.spectrogram(rate: rate),
            signalLevelMetrics: .unavailable, truePeak: .unavailable,
            loudness: .unavailable, significantBandwidth: .unavailable,
            stream: PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: 2_048)!
        )
    }

    /// One comparison, driven to a settled state, with each side's drawings as given.
    private func compare(first: Drawing, second: Drawing) async -> ImportFlowModel {
        let primary = Self.firstReport
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(primary)])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()

        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(.inspected(Self.secondReport, analyses: analyses(second, rate: 96_000)))
        await comparing.value

        action.finish(.inspected(primary, analyses: analyses(first, rate: 44_100)))
        await running.value
        return flow
    }

    /// The three things the task says must not move, read out of a settled flow.
    private struct WhatMustNotMove: Equatable {
        let firstProperties: TechnicalProperties
        let firstWarnings: [InspectionWarning]
        let firstStatus: InspectionStatus
        let secondProperties: TechnicalProperties
        let secondWarnings: [InspectionWarning]
        let secondStatus: InspectionStatus
        let technical: FileComparison?
        let measurements: MeasurementComparison?
    }

    private func readOut(_ flow: ImportFlowModel) -> WhatMustNotMove? {
        guard case let .report(presentation) = flow.state,
              case let .ready(technical, measurements, _) = flow.comparison
        else { return nil }
        return WhatMustNotMove(
            firstProperties: presentation.report.properties,
            firstWarnings: presentation.report.warnings,
            firstStatus: presentation.report.status,
            secondProperties: technical.second.properties,
            secondWarnings: technical.second.warnings,
            secondStatus: technical.second.status,
            technical: technical,
            measurements: measurements
        )
    }

    // MARK: - 9.7 · the whole matrix, against one baseline

    /// **Every case, against the same baseline.** Thirty-five combinations of what became of each
    /// side's drawings, and one answer for all of them: the two reports are the same reports.
    @Test("no combination of absent or failed drawings moves either report")
    func nothingMovesEitherReport() async {
        guard let baseline = readOut(await compare(first: .available, second: .available)) else {
            Issue.record("the baseline did not settle"); return
        }

        for first in Drawing.allCases {
            for second in Drawing.allCases {
                let flow = await compare(first: first, second: second)
                guard let observed = readOut(flow) else {
                    Issue.record("\(first)/\(second) did not settle a comparison"); continue
                }
                let label = "\(first) beside \(second)"
                #expect(observed.firstProperties == baseline.firstProperties, "\(label): first properties")
                #expect(observed.firstWarnings == baseline.firstWarnings, "\(label): first warnings")
                #expect(observed.firstStatus == baseline.firstStatus, "\(label): first status")
                #expect(observed.secondProperties == baseline.secondProperties, "\(label): second properties")
                #expect(observed.secondWarnings == baseline.secondWarnings, "\(label): second warnings")
                #expect(observed.secondStatus == baseline.secondStatus, "\(label): second status")
                #expect(observed.technical == baseline.technical, "\(label): technical comparison")
                #expect(observed.measurements == baseline.measurements, "\(label): measurement comparison")
            }
        }
    }

    /// **No warning is emitted for a drawing.** Asserted twice over: the warnings are the ones the
    /// inspection produced and no more, and none of them names a drawing — so a future warning code
    /// about a waveform would fail this even if the count happened to stay the same.
    @Test("no inspection warning is emitted for a drawing", arguments: Drawing.allCases)
    func noWarningIsEmittedForADrawing(drawing: Drawing) async {
        let flow = await compare(first: drawing, second: drawing)
        guard case let .report(presentation) = flow.state,
              case let .ready(technical, _, _) = flow.comparison
        else { Issue.record("expected a settled comparison"); return }

        for report in [presentation.report, technical.second] {
            #expect(report.warnings.count == 2)
            for warning in report.warnings {
                let text = "\(warning.code.rawValue) \(warning.field ?? "") \(warning.message)".lowercased()
                for term in ["waveform", "envelope", "spectrogram", "spectral", "drawing", "visual", "raster"] {
                    #expect(!text.contains(term), "a warning names \(term): \(warning)")
                }
            }
        }
    }

    /// **The absence is represented rather than hidden.** A report left intact would be worth
    /// nothing if it were bought by quietly dropping the pair: the pair still settles, and the lane
    /// whose artefact is missing says so in its own case.
    @Test("the pair still settles, and the missing side says what became of it")
    func theAbsenceIsStillRepresented() async {
        let flow = await compare(first: .waveformFailed, second: .spectrogramUnavailable)
        guard case let .ready(_, _, paired) = flow.comparison, let pair = paired else {
            Issue.record("expected a settled pair"); return
        }

        #expect(pair.first.waveform == .failed(message: "Producing it did not succeed."))
        #expect(pair.second.spectrogram == .unavailable)
        // And the artefacts that did arrive are untouched by the ones that did not.
        #expect(pair.second.waveform == .available(WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -0.5, maximum: 0.5)!], frameCount: 2_048, channelCount: 2
        )!))
        if case .available = pair.first.spectrogram {} else {
            Issue.record("the first file's model should have survived its waveform failing")
        }
    }

    /// **A drawing that is missing on both sides does not remove the pair.** The state the surface
    /// would most plausibly collapse to a single drawing, asserted not to.
    @Test("both sides missing the same drawing is still a pair")
    func bothSidesMissingIsStillAPair() async {
        let flow = await compare(first: .spectrogramFailed, second: .spectrogramFailed)
        guard case let .ready(_, _, paired) = flow.comparison, let pair = paired else {
            Issue.record("expected a settled pair"); return
        }
        #expect(pair.first.spectrogram == .failed(message: "Producing it did not succeed."))
        #expect(pair.second.spectrogram == .failed(message: "Producing it did not succeed."))
        // The surface stays in paired mode: two lanes saying so, not one drawing standing alone.
        let visuals = RootView.reportVisuals(
            for: presentationOf(flow) ?? placeholderPresentation(), in: flow.comparison
        )
        guard case .paired = visuals else {
            Issue.record("a pair whose spectral models both failed fell back to a single drawing"); return
        }
    }

    private func presentationOf(_ flow: ImportFlowModel) -> InspectionPresentation? {
        guard case let .report(presentation) = flow.state else { return nil }
        return presentation
    }

    private func placeholderPresentation() -> InspectionPresentation {
        InspectionPresentation(report: Self.firstReport, waveform: .loading)
    }
}
