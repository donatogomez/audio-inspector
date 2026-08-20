import AudioInspectorDomain

// Where lifecycle stops.
//
// Four states reach this feature for every measurement — loading, available, unavailable, failed, and
// for a compared file also cancelled. **None of them reaches the domain.** `ReportMeasurements` holds
// four optionals where `nil` means *nothing to compare*, and the collapse happens here, once, for both
// sides: the primary file's `…State` values and the compared file's `…Outcome` values.
//
// It is the same rule the export path already applies (`ReportView`'s `exportable…` accessors), stated
// once more here because `FeatureAnalysis` and `FeatureImport` never see one another. **The JSON and the
// comparison describe measurements, not why one does not exist**, so a failure collapses to the same
// `nil` an absence does: *"this run's loudness failed"* is a fact about a run, and a comparison that
// reported it would be reporting on itself rather than on the two files.

extension InspectionPresentation {
    /// The measurements this file has **settled on**, or `nil` while any of them is still being
    /// produced.
    ///
    /// **`nil` means "not finished", never "nothing to compare"**, and the difference is the whole point
    /// of the optional. The compare action is offered the moment a report is on screen, which is before
    /// its own read has finished, so a file can genuinely still be measuring while the file it is being
    /// compared against has already finished. Publishing then would report the primary's loudness as
    /// *missing* when it is merely a second away — a statement about this run dressed up as a fact about
    /// the file.
    var settledMeasurements: ReportMeasurements? {
        guard case let .settled(levels) = SettledValue(signalLevelMetrics),
              case let .settled(peak) = SettledValue(truePeak),
              case let .settled(loudness) = SettledValue(self.loudness),
              case let .settled(bandwidth) = SettledValue(significantBandwidth)
        else { return nil }
        return ReportMeasurements(
            signalLevelMetrics: levels, truePeak: peak, loudness: loudness, programmeBandwidth: bandwidth
        )
    }
}

extension InspectionAnalyses {
    /// The measurements a compared file settled on, or `nil` when the inspection was cancelled.
    ///
    /// **The two visualisations are deliberately not here.** A waveform and a spectrogram are pictures
    /// of the samples rather than measurements of them, they have never appeared under `measurements` on
    /// the wire, and comparing them is `add-two-file-visual-comparison`'s. `ReportMeasurements` has no
    /// field either could occupy, so this is enforced by the type rather than by this comment.
    ///
    /// A **producer failure** turns every one of the four into `.failed` while the report survives — and
    /// that is exactly why a failure collapses to `nil` rather than to a failed comparison: the technical
    /// comparison stays as valid as it was, and the measurement comparison simply has nothing on that
    /// side.
    var settledMeasurements: ReportMeasurements? {
        guard case let .settled(levels) = SettledValue(signalLevelMetrics),
              case let .settled(peak) = SettledValue(truePeak),
              case let .settled(loudness) = SettledValue(self.loudness),
              case let .settled(bandwidth) = SettledValue(significantBandwidth)
        else { return nil }
        return ReportMeasurements(
            signalLevelMetrics: levels, truePeak: peak, loudness: loudness, programmeBandwidth: bandwidth
        )
    }
}

/// One side's lifecycle collapsed: either it has finished — with a value or without one — or it has not.
///
/// A named type rather than a pair of optionals, because *"finished with nothing"* and *"not finished"*
/// are two different answers and an `Optional<Optional<Value>>` spells them identically to a reader.
private enum SettledValue<Value> {
    case settled(Value?)
    case notSettled

    init(_ state: SignalLevelMetricsState) where Value == SignalLevelMetrics {
        switch state {
        case .loading: self = .notSettled
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        }
    }

    init(_ state: TruePeakState) where Value == TruePeakMeasurement {
        switch state {
        case .loading: self = .notSettled
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        }
    }

    init(_ state: LoudnessState) where Value == LoudnessMeasurement {
        switch state {
        case .loading: self = .notSettled
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        }
    }

    init(_ state: SignificantBandwidthState) where Value == SignificantBandwidth {
        switch state {
        case .loading: self = .notSettled
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        }
    }

    // A compared file's outcomes. `cancelled` is the only one that is not a settled answer: the
    // operation it belongs to was replaced, and it says nothing about the file.
    init(_ outcome: SignalLevelMetricsOutcome) where Value == SignalLevelMetrics {
        switch outcome {
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        case .cancelled: self = .notSettled
        }
    }

    init(_ outcome: TruePeakOutcome) where Value == TruePeakMeasurement {
        switch outcome {
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        case .cancelled: self = .notSettled
        }
    }

    init(_ outcome: LoudnessOutcome) where Value == LoudnessMeasurement {
        switch outcome {
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        case .cancelled: self = .notSettled
        }
    }

    init(_ outcome: SignificantBandwidthOutcome) where Value == SignificantBandwidth {
        switch outcome {
        case let .available(value): self = .settled(value)
        case .unavailable, .failed: self = .settled(nil)
        case .cancelled: self = .notSettled
        }
    }
}
