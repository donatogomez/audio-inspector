import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

/// The seam the export button reads, asserted on its own — **the point of R0.**
///
/// This rule used to live as four computed properties on `ReportView`, unreachable from a headless
/// test, and three tests plus a production harness reproduced it by hand. Four copies of a rule are
/// four rules that agree until one of them does not. What is asserted here is exactly the behaviour
/// those copies had: nothing was normalised, and the one asymmetry between the four is deliberate and
/// is pinned as such.
@Suite("Export — what the report surface hands the exporter")
struct ExportableMeasurementsTests {

    // MARK: - Fixtures
    //
    // Built through each type's own failable initialiser, exactly as the presentation suites do — a
    // fixture this seam could not have been handed by production would prove nothing about it.

    private func metrics() throws -> SignalLevelMetrics {
        let channel = try #require(SignalLevelMetrics.Channel(
            sampleCount: 1_024, peakSample: 0.5, rms: 0.25, dcOffset: 0.001, clippedSampleCount: 0
        ))
        return try #require(SignalLevelMetrics(
            channels: [channel], overallPeakSample: 0.5, overallRMS: 0.25,
            overallDCOffset: 0.001, overallClippedSampleCount: 0
        ))
    }

    private func peak() throws -> TruePeakMeasurement {
        let channel = try #require(TruePeakMeasurement.Channel(sampleCount: 44_100, truePeak: 0.9))
        let method = try #require(TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1))
        return try #require(TruePeakMeasurement(channels: [channel], method: method))
    }

    private func loudness() throws -> LoudnessMeasurement {
        try #require(LoudnessMeasurement(
            integratedLoudness: -23.0,
            method: LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)
        ))
    }

    private func bandwidthMethod() throws -> SignificantBandwidthMethod {
        try #require(SignificantBandwidthMethod(
            identifier: SignificantBandwidthMethod.v1,
            windowFrames: 2_048, hopFrames: 512, sampleRate: 48_000
        ))
    }

    /// A bandwidth measurement that really carries a reading.
    private func bandwidth() throws -> SignificantBandwidth {
        let channel = try #require(SignificantBandwidth.Channel(frequency: 16_000, resolution: 23.4375))
        return try #require(SignificantBandwidth(channels: [channel], method: try bandwidthMethod()))
    }

    /// A bandwidth measurement whose windows were eligible and none of whose bins met the persistence
    /// criterion: it **exists**, and it carries no reading at all.
    private func bandwidthWithNoReading() throws -> SignificantBandwidth {
        try #require(SignificantBandwidth(channels: [nil], method: try bandwidthMethod()))
    }

    // MARK: - Every state, per measurement

    /// **A measured value survives exactly**, and is the same value the presentation carried — not a
    /// copy rebuilt from its parts.
    @Test("a measured value reaches the export unchanged, for all four")
    func measuredValuesSurvive() throws {
        let levels = try metrics()
        let truePeak = try peak()
        let integrated = try loudness()
        let edge = try bandwidth()

        #expect(ExportableMeasurements.value(of: .metrics(levels)) == levels)
        #expect(ExportableMeasurements.value(of: .measurement(truePeak)) == truePeak)
        #expect(ExportableMeasurements.value(of: .measurement(integrated)) == integrated)
        #expect(ExportableMeasurements.value(of: .measurement(edge)) == edge)
    }

    /// **`loading` is not a value.** A measurement still being produced has nothing to report, and
    /// exporting mid-read must not put a half-answer on the wire.
    @Test("loading yields nothing, for all four")
    func loadingYieldsNothing() {
        #expect(ExportableMeasurements.value(of: SignalLevelMetricsPresentation.loading) == nil)
        #expect(ExportableMeasurements.value(of: TruePeakPresentation.loading) == nil)
        #expect(ExportableMeasurements.value(of: LoudnessPresentation.loading) == nil)
        #expect(ExportableMeasurements.value(of: SignificantBandwidthPresentation.loading) == nil)
    }

    /// **An absence is not a zero.** It is the key not being there, never a substituted `0`, floor or
    /// Nyquist — the distinction every one of these measurements exists to preserve.
    @Test("absence yields nothing, for all four")
    func absenceYieldsNothing() {
        #expect(ExportableMeasurements.value(of: SignalLevelMetricsPresentation.absent) == nil)
        #expect(ExportableMeasurements.value(of: TruePeakPresentation.absent) == nil)
        #expect(ExportableMeasurements.value(of: LoudnessPresentation.absent) == nil)
        #expect(ExportableMeasurements.value(of: SignificantBandwidthPresentation.absent) == nil)
    }

    /// **A failure collapses to the same nothing an absence does, and that is deliberate.** *This run's
    /// loudness failed* is a fact about a run; the document describes measurements, never why one does
    /// not exist. The surface still says which of the two happened — that distinction lives in the
    /// copy, not on the wire.
    @Test("failure yields nothing, for all four")
    func failureYieldsNothing() {
        let message = "Measuring it did not succeed."
        #expect(ExportableMeasurements.value(of: SignalLevelMetricsPresentation.failed(message: message)) == nil)
        #expect(ExportableMeasurements.value(of: TruePeakPresentation.failed(message: message)) == nil)
        #expect(ExportableMeasurements.value(of: LoudnessPresentation.failed(message: message)) == nil)
        #expect(ExportableMeasurements.value(of: SignificantBandwidthPresentation.failed(message: message)) == nil)
    }

    // MARK: - The one asymmetry, pinned as an asymmetry

    /// **The bandwidth rule is not its siblings' rule**, and this is the test that says so on purpose.
    ///
    /// A measurement can exist and carry no reading, and that is an absence to a reader — so it does
    /// not reach the wire, even though the enum case is `.measurement`. The other three have no such
    /// state and are not given one here: R0 moved this rule, it did not normalise it.
    @Test("a bandwidth measurement carrying no reading does not reach the export")
    func bandwidthWithoutAReadingIsAbsent() throws {
        let withoutReading = try bandwidthWithNoReading()
        let withReading = try bandwidth()

        #expect(withoutReading.overall == nil)
        #expect(ExportableMeasurements.value(of: .measurement(withoutReading)) == nil)
        // And the one that does carry a reading still does.
        #expect(ExportableMeasurements.value(of: .measurement(withReading)) != nil)
    }

    // MARK: - The four together

    /// The whole payload, assembled once. Each measurement is read from **its own** presentation: a
    /// value cannot arrive on another's field.
    @Test("the four are assembled independently, each from its own state")
    func theFourAreIndependent() throws {
        let levels = try metrics()
        let edge = try bandwidth()

        let assembled = ExportableMeasurements.measurements(
            signalLevelMetrics: .metrics(levels),
            truePeak: .absent,
            loudness: .failed(message: "no"),
            programmeBandwidth: .measurement(edge)
        )

        #expect(assembled.signalLevelMetrics == levels)
        #expect(assembled.truePeak == nil)
        #expect(assembled.loudness == nil)
        #expect(assembled.programmeBandwidth == edge)
    }

    /// A report exported while everything is still loading carries **no measurements at all** — the
    /// state the export button is most likely to be pressed in, and the one a careless collapse would
    /// turn into four zeroes.
    @Test("nothing settled yields an empty payload, not four zeroes")
    func nothingSettledYieldsAnEmptyPayload() {
        let assembled = ExportableMeasurements.measurements(
            signalLevelMetrics: .loading, truePeak: .loading,
            loudness: .loading, programmeBandwidth: .loading
        )
        #expect(assembled.signalLevelMetrics == nil)
        #expect(assembled.truePeak == nil)
        #expect(assembled.loudness == nil)
        #expect(assembled.programmeBandwidth == nil)
    }

    // MARK: - What this layer may not know

    /// **No JSON and no export type reaches this seam**, asserted over its source rather than intended.
    /// It produces a domain value; what happens to it afterwards is not this feature's business, and a
    /// `FeatureAnalysis → Export` dependency is not expressible anyway (the module graph refuses it).
    @Test("the seam names no encoder, no wire type and no SwiftUI")
    func theSeamKnowsNothingOfTheWire() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/AudioInspectorKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Sources/FeatureAnalysis/ExportableMeasurements.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") && !trimmed.hasPrefix("*") else { continue }
            for forbidden in [
                "Codable", "Encodable", "Decodable", "JSONEncoder", "JSONDecoder", "JSONSerialization",
                "SwiftUI", "View", "DTO", "schemaVersion", "ReportExporting", "JSONReportExporter",
            ] {
                #expect(
                    line.range(of: "\\b\(forbidden)\\b", options: .regularExpression) == nil,
                    "the seam names \(forbidden): \(trimmed)"
                )
            }
        }
        // The import list is the domain and nothing else.
        let imports = text.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("import ") }
        #expect(imports == ["import AudioInspectorDomain"])
    }

    /// **`ReportView` no longer knows how to build an export payload**, which is the property R0
    /// exists to establish: the redesign can take that view apart without the export following it.
    @Test("the report view holds no exportable extraction of its own")
    func theViewNoLongerOwnsTheRule() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis/ReportView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        #expect(!text.contains("exportableSignalLevelMetrics"))
        #expect(!text.contains("exportableTruePeak"))
        #expect(!text.contains("exportableLoudness"))
        #expect(!text.contains("exportableProgrammeBandwidth"))
        // It calls the seam instead — so this is "moved", not "deleted".
        #expect(text.contains("ExportableMeasurements.measurements("))
    }
}
