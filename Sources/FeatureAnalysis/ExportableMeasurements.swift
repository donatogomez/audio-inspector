import AudioInspectorDomain

/// Where the **report surface's** lifecycle stops and the domain's four optionals begin.
///
/// Each of the four measurements reaches this feature as a presentation with four states — `loading`,
/// the measured value, `absent` and `failed` — and `ReportMeasurements` holds four optionals where
/// `nil` means *there is nothing to report for this one*. The collapse between them is a decision
/// about **what a UI-only state means on the wire**, and ADR-0009 puts that decision in this feature:
/// the export layer takes a domain value or nothing, and never has to interpret a state it cannot see.
///
/// ## Why it is here and not in the view
///
/// It used to be four computed properties on `ReportView`, which made a SwiftUI view the only place
/// that knew how to build an export payload — and made it unreachable from a headless test, so three
/// tests and one production harness **reproduced the rule by hand** rather than calling it. A rule
/// with four copies is four rules that happen to agree today. This is the one they all call.
///
/// ## Why it is not shared with `FeatureImport`'s collapse
///
/// `SettledMeasurements` next door performs a collapse that looks the same and is not, and the two
/// modules deliberately cannot see each other. It answers a different question — *has this file
/// finished measuring?* — so `loading` is `notSettled` there and must be waited for, while here it is
/// simply nothing to export. It also has no reason to know about a bandwidth measurement carrying no
/// reading. Merging them would force one of those two answers to be wrong.
///
/// No `Codable`, no JSON, no encoder, no export type: this produces a **domain** value, and what
/// happens to it afterwards is not this feature's business.
enum ExportableMeasurements {

    /// The four measurements to export, as the domain holds them.
    ///
    /// Every parameter is required and none has a default: a default would let a caller forget one and
    /// ship a document silently missing a measurement the file really produced.
    static func measurements(
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation
    ) -> ReportMeasurements {
        ReportMeasurements(
            signalLevelMetrics: value(of: signalLevelMetrics),
            truePeak: value(of: truePeak),
            loudness: value(of: loudness),
            programmeBandwidth: value(of: programmeBandwidth)
        )
    }

    /// The metrics to export, or `nil` when there is nothing to report.
    ///
    /// `loading`, `absent` and `failed` all collapse to `nil`: **the document describes measurements,
    /// never why one does not exist.** A failure in particular is a fact about this run rather than
    /// about the file, and putting it on the wire would be the document reporting on itself.
    ///
    /// A file with no audio frames is **not** an absence: it produces metrics whose every value reports
    /// as not computable, and those are exported as the complete answer they are.
    static func value(of presentation: SignalLevelMetricsPresentation) -> SignalLevelMetrics? {
        guard case let .metrics(metrics) = presentation else { return nil }
        return metrics
    }

    /// The same rule for the true peak, for the same reason.
    static func value(of presentation: TruePeakPresentation) -> TruePeakMeasurement? {
        guard case let .measurement(measurement) = presentation else { return nil }
        return measurement
    }

    /// And again for the integrated loudness, whose `absent` carries more causes than its siblings' —
    /// too short to form a gating block, every block below the absolute gate, an unsupported
    /// configuration — and none of them survives to the wire. They are all the key simply not being
    /// there.
    static func value(of presentation: LoudnessPresentation) -> LoudnessMeasurement? {
        guard case let .measurement(measurement) = presentation else { return nil }
        return measurement
    }

    /// The same rule again for the programme bandwidth, **plus one this measurement needs on its own,
    /// which is why the four are not one function over a generic.**
    ///
    /// A measurement can exist and carry no reading at all — its windows were eligible and no bin met
    /// the persistence criterion — and that is an absence to anyone reading either surface. The section
    /// says so in the report's not-computable words and the document says so by omitting the key, so
    /// the two never disagree.
    static func value(of presentation: SignificantBandwidthPresentation) -> SignificantBandwidth? {
        guard case let .measurement(measurement) = presentation, measurement.overall != nil else {
            return nil
        }
        return measurement
    }
}
