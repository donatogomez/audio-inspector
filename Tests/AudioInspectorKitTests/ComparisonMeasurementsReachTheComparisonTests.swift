import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
import FeatureImport

@testable import AudioInspectorApp

// **Task 1.1, inverted by task 3.1 — and inverted rather than replaced.**
//
// It began as the evidence that comparing a second file *already pays* for its measurements and then
// throws them away, and it said so by asserting that nothing the read produced changed the comparison.
// Group 3 made that false on purpose. What it asserts now is the other half of the same claim: the same
// measurements, produced by the same single read, **arrive in the comparison** — so the compute cost of
// the feature really was zero and only retention was added.
//
// The read count and the "no second inspection" assertions are unchanged from the original, and must
// stay that way: they are what makes "only retention was added" a measurement rather than a hope.
@MainActor
@Suite("Feature — a comparison measures a file once, and keeps the measurements")
struct ComparisonMeasurementsReachTheComparisonTests {

    /// Counts what the real pipeline actually opened for the compared file.
    private final class Counts: @unchecked Sendable {
        var decodersMade = 0
        var decodeCalls = 0
    }

    /// Delegates to the real decoder and counts the call. It changes nothing about the read.
    private struct CountingDecoder: AudioDecoding {
        let wrapped: any AudioDecoding
        let counts: Counts

        func decode(
            _ file: AudioFileReference,
            chunkFrames: Int,
            receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
        ) async throws(AudioDecodingError) -> PCMStreamDescription? {
            counts.decodeCalls += 1
            return try await wrapped.decode(file, chunkFrames: chunkFrames, receive: receive)
        }
    }

    /// Captures what the flow is about to discard, so the test can assert on it. A class rather than
    /// locals because the action is `@Sendable` and captured mutable state would not be.
    @MainActor
    private final class Capture {
        var outcome: SourceInspectionOutcome?
        var comparisonWhenTheReportLanded: ImportFlowModel.ComparisonState?
        var secondReport: InspectionReport?
    }

    /// An action that delivers one report and then suspends, so a test can inspect the comparison at
    /// the exact moment the report has landed and nothing else has.
    @MainActor
    private final class PrimaryAction {
        let report: InspectionReport
        private var started: CheckedContinuation<Void, Never>?
        private var release: CheckedContinuation<Void, Never>?
        private(set) var runCount = 0

        init(report: InspectionReport) { self.report = report }

        func run(_ onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
            runCount += 1
            onUpdate(.report(report))
            started?.resume(); started = nil
            await withCheckedContinuation { release = $0 }
            return .inspected(report, analyses: InspectionAnalyses(
                waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable,
                truePeak: .unavailable, loudness: .unavailable, significantBandwidth: .unavailable
            ))
        }

        func waitUntilStarted() async {
            guard runCount == 0 else { return }
            await withCheckedContinuation { started = $0 }
        }

        func finish() { release?.resume(); release = nil }
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

    /// Two seconds of a band-limited comb at 44.1 kHz stereo — long enough that integrated loudness
    /// spans several gating blocks, so an absence would mean the wiring rather than the file.
    private func fixture(in directory: URL) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "compared", format: .wav, signal: productionProgramme(to: 16_000),
                sampleRate: 44_100, channels: 2, frames: 88_200
            ),
            in: directory
        )
    }

    /// **One sequence, five claims.** A real file is compared against a report on screen, through the
    /// real coordinator and the real decoder: the compared file is inspected exactly once, its four
    /// measurements are produced, the **technical** comparison is complete before any of that finishes,
    /// the **measurement** comparison is not published until it settles, and then it is.
    @Test("comparing a file measures it once and the measurements reach the comparison")
    func aComparisonMeasuresOnceAndKeepsTheMeasurements() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let counts = Counts()
            let coordinator = SourceInspectionCoordinator(
                makeDecoder: { url in
                    counts.decodersMade += 1
                    return CountingDecoder(
                        wrapped: AVFoundationAudioDecoder(resolveURL: { _ in url }), counts: counts
                    )
                }
            )

            let primary = PrimaryAction(report: report(named: "a.wav"))
            let flow = ImportFlowModel(action: primary.run)
            let running = Task { await flow.selectAndInspect() }
            await primary.waitUntilStarted()

            // The comparison runs the real pipeline over a real file. The outcome is captured so the
            // measurements can be inspected — the flow itself is about to drop them.
            let capture = Capture()
            await flow.compare(using: { onUpdate in
                let outcome = await coordinator.inspect(url) { update in
                    onUpdate(update)
                    // The instant the report has landed and nothing else has.
                    if case .report = update { capture.comparisonWhenTheReportLanded = flow.comparison }
                }
                capture.outcome = outcome
                return outcome
            })

            // A. One inspection of the compared file: one decoder, one read.
            #expect(counts.decodersMade == 1, "the compared file was given \(counts.decodersMade) decoders")
            #expect(counts.decodeCalls == 1, "the compared file's samples were read \(counts.decodeCalls) times")

            // B. All four measurements really were produced.
            guard case let .inspected(_, analyses)? = capture.outcome else {
                Issue.record("the compared file was not inspected: \(String(describing: capture.outcome))"); return
            }
            guard case .available = analyses.signalLevelMetrics, case .available = analyses.truePeak,
                  case .available = analyses.loudness, case .available = analyses.significantBandwidth
            else {
                Issue.record("""
                a measurement was not produced for the compared file — \
                levels \(analyses.signalLevelMetrics), truePeak \(analyses.truePeak), \
                loudness \(analyses.loudness), bandwidth \(analyses.significantBandwidth)
                """)
                return
            }
            // The visualisations are produced and discarded too, and stay out of scope here.
            guard case .available = analyses.waveform, case .available = analyses.spectrogram else {
                Issue.record("the compared file's visualisations were not produced either"); return
            }

            // C. The comparison was already complete when the report landed — before a single chunk of
            //    the read had been folded into anything.
            guard case .ready = try #require(capture.comparisonWhenTheReportLanded) else {
                Issue.record("the comparison was not ready when the report landed"); return
            }

            // D. And nothing the read produced changed it afterwards.
            #expect(
                flow.comparison == capture.comparisonWhenTheReportLanded,
                "the comparison changed after the measurements settled, which this task says it does not"
            )

            primary.finish()
            await running.value
        }
    }

    /// **The technical half is still a function of the two reports and nothing else**, which is what
    /// keeps `FileComparison`'s integrity argument intact now that something else travels beside it.
    ///
    /// And the visualisations are still out: a waveform and a spectrogram are pictures of the samples
    /// rather than measurements of them, and `ReportMeasurements` has no field either could occupy — so
    /// their exclusion is enforced by the type, which this states rather than tries to observe.
    @Test("the technical comparison is still derived from the two reports alone")
    func theTechnicalComparisonIsDerivedFromReportsAlone() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let primary = PrimaryAction(report: report(named: "a.wav"))
            let flow = ImportFlowModel(action: primary.run)
            let running = Task { await flow.selectAndInspect() }
            await primary.waitUntilStarted()

            let capture = Capture()
            await flow.compare(using: { onUpdate in
                let outcome = await SourceInspectionCoordinator().inspect(url, onUpdate: onUpdate)
                if case let .inspected(report, _) = outcome { capture.secondReport = report }
                return outcome
            })

            let second = try #require(capture.secondReport)
            guard case let .ready(technical, _) = flow.comparison else {
                Issue.record("no comparison was produced"); return
            }
            #expect(
                technical == FileComparison(first: primary.report, second: second),
                "the technical comparison carries something the two reports alone do not determine"
            )
            // `ReportMeasurements` has four fields and neither visualisation is one of them.
            #expect(
                Set(Mirror(reflecting: ReportMeasurements.none).children.compactMap(\.label))
                    == ["signalLevelMetrics", "truePeak", "loudness", "programmeBandwidth"],
                "a visualisation reached the measurement bundle"
            )

            primary.finish()
            await running.value
        }
    }
}
