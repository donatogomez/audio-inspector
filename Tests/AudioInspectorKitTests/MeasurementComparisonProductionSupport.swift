import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia

@testable import AudioInspectorApp
@testable import FeatureImport

// Group 5's subject, stated once: **two real files, the real coordinator, the real decoder, one shared
// PCM read each, and the `MeasurementComparison` production builds from what they settled on.**
//
// `MeasurementComparisonTests` is the domain oracle: it hands the comparator two `ReportMeasurements`
// it wrote itself, which is the right way to pin a *rule* and no way at all to show the rule ever runs
// on a measurement a file produced. Nothing here constructs a `SignalLevelMetrics`, a
// `TruePeakMeasurement`, a `LoudnessMeasurement` or a `SignificantBandwidth`. Every value a group-5
// suite asserts on came out of:
//
//     file → AVFoundationAudioDecoder → SharedPCMAnalysisGeneration → InspectionAnalyses
//          → FeatureImport's settled collapse → ReportMeasurements → MeasurementComparison
//
// The collapse is `FeatureImport`'s own — the same `settledMeasurements` `ImportFlowModel` calls — so
// the only thing standing between these suites and the flow is the flow's stale guard, which
// `MeasurementComparisonAtomicityTests` owns.

/// What one production inspection of one file settled on.
@MainActor
struct MeasuredFile {
    let url: URL
    let report: InspectionReport
    let analyses: InspectionAnalyses
    /// The bundle `FeatureImport` collapses the analyses to. Never assembled here.
    let measurements: ReportMeasurements

    var signalLevels: SignalLevelMetrics? { measurements.signalLevelMetrics }
    var truePeak: TruePeakMeasurement? { measurements.truePeak }
    var loudness: LoudnessMeasurement? { measurements.loudness }
    var bandwidth: SignificantBandwidth? { measurements.programmeBandwidth }
}

/// Two measured files and the comparison production builds from them.
///
/// The comparison is built from `first.measurements` and `second.measurements` and from nothing else,
/// which is the same expression `ImportFlowModel.publishMeasurementComparisonIfBothSettled` evaluates.
@MainActor
struct MeasuredPair {
    let first: MeasuredFile
    let second: MeasuredFile
    let comparison: MeasurementComparison
}

/// Counts what the real pipeline opened and read, per file.
///
/// A class rather than a struct because the decoder factory is `@Sendable` and the count has to
/// survive the closure. It is the same shape `ComparisonMeasurementsReachTheComparisonTests` uses, and
/// it exists here for the same reason: "one decoder, one read" has to be observed rather than assumed.
final class ProductionReadCounts: @unchecked Sendable {
    var decodersMade = 0
    var decodeCalls = 0
}

/// Delegates to the real decoder and counts the call. It changes nothing about the read.
struct CountingDecoder: AudioDecoding {
    let wrapped: any AudioDecoding
    let counts: ProductionReadCounts

    func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription? {
        counts.decodeCalls += 1
        return try await wrapped.decode(file, chunkFrames: chunkFrames, receive: receive)
    }
}

@MainActor
enum MeasurementProduction {

    /// Writes `spec` and inspects it through the real coordinator.
    ///
    /// `.wavFloat` is the group's default for the same reason the loudness harness gives: 16-bit
    /// quantisation would put a floor under a quiet band that a bandwidth or a level fixture may
    /// deliberately place below it.
    static func measure(
        _ spec: AudioFixtureSpec, in directory: URL, counting counts: ProductionReadCounts? = nil
    ) async throws -> MeasuredFile {
        try await measure(fileAt: writeAudioFixture(spec, in: directory), counting: counts)
    }

    /// The same for a file a caller already wrote — a rewrapped container, or one it had to normalise.
    static func measure(
        fileAt url: URL, counting counts: ProductionReadCounts? = nil
    ) async throws -> MeasuredFile {
        let coordinator = SourceInspectionCoordinator(makeDecoder: { url in
            let real = AVFoundationAudioDecoder(resolveURL: { _ in url })
            guard let counts else { return real }
            counts.decodersMade += 1
            return CountingDecoder(wrapped: real, counts: counts)
        })
        let outcome = await coordinator.inspect(url) { _ in }
        guard case let .inspected(report, analyses) = outcome else {
            Issue.record("\(url.lastPathComponent) was not inspected: \(outcome)")
            throw ProductionInspectionFailed()
        }
        // The collapse is `FeatureImport`'s. `nil` here would mean an outcome that never settled, which
        // a coordinator run cannot produce — so it is an error rather than an empty bundle.
        guard let measurements = analyses.settledMeasurements else {
            Issue.record("\(url.lastPathComponent) produced no settled measurement bundle")
            throw ProductionInspectionFailed()
        }
        return MeasuredFile(url: url, report: report, analyses: analyses, measurements: measurements)
    }

    /// Measures two specs and compares what they settled on.
    static func pair(
        _ first: AudioFixtureSpec, _ second: AudioFixtureSpec, in directory: URL
    ) async throws -> MeasuredPair {
        try await pair(
            await measure(first, in: directory), await measure(second, in: directory)
        )
    }

    /// The same for two files already measured — a pair whose second side needed writing by hand.
    static func pair(_ first: MeasuredFile, _ second: MeasuredFile) async throws -> MeasuredPair {
        MeasuredPair(
            first: first, second: second,
            comparison: MeasurementComparison(first: first.measurements, second: second.measurements)
        )
    }
}

struct ProductionInspectionFailed: Error {}

// MARK: - Reading a production comparison without restating its rule

extension BandwidthReadingComparison {
    /// The two readings, whichever side of the cell rule they landed on. `nil` when nothing compared.
    var readings: (first: SignificantBandwidth.Channel, second: SignificantBandwidth.Channel)? {
        switch self {
        case let .indistinguishable(a, b), let .separated(a, b): (a, b)
        case .incomparable: nil
        }
    }

    /// What the rule was applied to, spelled out for a failure message: the two centres, the two
    /// resolutions, their separation and the boundary it was tested against.
    var evidence: String {
        guard let (a, b) = readings else { return "\(self)" }
        let separation = abs(a.frequency - b.frequency)
        let boundary = (a.resolution + b.resolution) / 2
        return """
        f₁ \(a.frequency) Hz (r₁ \(a.resolution) Hz), f₂ \(b.frequency) Hz (r₂ \(b.resolution) Hz), \
        |f₁ − f₂| = \(separation) Hz against (r₁ + r₂)/2 = \(boundary) Hz
        """
    }
}

// MARK: - Reading a whole comparison without restating its rules

extension MeasurementComparison {
    /// Every gap this comparison reports, so a suite can say *"and nothing was incomparable"* over the
    /// whole value rather than field by field.
    ///
    /// It gathers rather than counts: a count would be an aggregate, and the type refuses those for a
    /// reason. What comes back is the list of reasons, which is what a failure message needs.
    var gaps: [MeasurementGap] {
        var found: [MeasurementGap] = []
        func take<Value>(_ comparison: MeasurementValueComparison<Value>) {
            if case let .incomparable(gap) = comparison { found.append(gap) }
        }
        func take(_ figures: SignalLevelFiguresComparison) {
            take(figures.peakSample); take(figures.rms)
            take(figures.dcOffset); take(figures.clippedSampleCount)
        }
        func take(_ reading: BandwidthReadingComparison) {
            if case let .incomparable(gap) = reading { found.append(gap) }
        }
        func take<C>(_ channels: ChannelComparison<C>, each: (C) -> Void) {
            switch channels {
            case let .byIndex(entries): entries.forEach(each)
            case .countsDiffer: break
            case let .incomparable(gap): found.append(gap)
            }
        }
        take(signalLevels.overall)
        take(signalLevels.channels, each: take)
        take(truePeak.overall)
        take(truePeak.channels, each: take)
        if case let .incomparable(gap) = loudness { found.append(gap) }
        take(programmeBandwidth.overall)
        take(programmeBandwidth.channels, each: take)
        return found
    }
}

extension ChannelComparison {
    /// The two counts a `countsDiffer` carries, or `nil` for every other case.
    ///
    /// A reader, not a rule: it exists so a suite can assert *"the mismatch was reported, and it was
    /// 1 against 2"* in one expression instead of pattern-matching three times over three metrics.
    var differingCounts: (first: Int, second: Int)? {
        if case let .countsDiffer(first, second) = self { (first, second) } else { nil }
    }
}
