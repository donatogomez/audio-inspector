import AudioInspectorDomain

/// What producing a waveform actually yielded, once it is over.
///
/// It has no "still working" case on purpose: this is the *result* of a generation, and a result that
/// has not happened yet is not a result. Waiting is a state of the flow, not of the outcome — see
/// `WaveformState`.
public enum WaveformOutcome: Sendable, Equatable {
    /// The file's amplitude envelope. An envelope with no buckets is a complete answer for a file
    /// with no frames, not an absence.
    case available(WaveformEnvelope)
    /// The file offered nothing to build an envelope from. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file. It says
    /// nothing about the file and must never be shown as a limitation of it.
    case cancelled
}

/// What the surface can say about a waveform right now.
///
/// The extra case over `WaveformOutcome` is `loading`, which exists only between the report arriving
/// and the generation finishing. `cancelled` is deliberately **absent**: a cancelled generation
/// belongs to an operation the user already replaced, so its result is discarded rather than shown.
public enum WaveformState: Sendable, Equatable {
    case loading
    case available(WaveformEnvelope)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into.
    ///
    /// Returns `nil` for `cancelled`, because there is nothing to show: the operation that produced
    /// it has been superseded, and rendering it as an absence would blame the file for the user's
    /// own action.
    public init?(_ outcome: WaveformOutcome) {
        switch outcome {
        case let .available(envelope): self = .available(envelope)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// What producing a spectrogram actually yielded, once it is over.
///
/// The waveform's four outcomes, for the same four reasons. Cancellation is separate from absence and
/// from failure because it says nothing whatever about the file — it is the user replacing an
/// operation.
public enum SpectrogramOutcome: Sendable, Equatable {
    /// The file's spectral model. A model with no columns is a complete answer for a file with no
    /// audio, or one shorter than a single analysis window — not an absence.
    case available(Spectrogram)
    /// The file exposed no usable frame count. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file.
    case cancelled
}

/// What the surface can say about a spectrogram right now.
///
/// The extra case over `SpectrogramOutcome` is `loading`, which exists between the report arriving and
/// the generation finishing. `cancelled` is deliberately **absent**, exactly as it is for the waveform:
/// a cancelled generation belongs to an operation the user already replaced, so its result is discarded
/// rather than shown.
public enum SpectrogramState: Sendable, Equatable {
    case loading
    case available(Spectrogram)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into.
    ///
    /// Returns `nil` for `cancelled`, because there is nothing to show: the operation that produced it
    /// has been superseded, and rendering it as an absence would blame the file for the user's own
    /// action.
    public init?(_ outcome: SpectrogramOutcome) {
        switch outcome {
        case let .available(spectrogram): self = .available(spectrogram)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// What producing signal level metrics actually yielded, once it is over.
///
/// The waveform's and the spectrogram's four outcomes, for the same four reasons. Cancellation is
/// separate from absence and from failure because it says nothing whatever about the file — it is the
/// user replacing an operation. `SignalLevelMetrics` never joins `TechnicalProperties` (ADR-0018): it
/// travels beside the report exactly as this outcome's siblings do.
public enum SignalLevelMetricsOutcome: Sendable, Equatable {
    /// The file's peak/RMS/DC-offset/clipping metrics. A channel with no samples reports `nil` for its
    /// per-sample values rather than being absent — a complete answer for a file with no audio, not an
    /// absence.
    case available(SignalLevelMetrics)
    /// The file exposed no usable frame count. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file.
    case cancelled
}

/// What the surface can say about signal level metrics right now.
///
/// The extra case over `SignalLevelMetricsOutcome` is `loading`, which exists between the report
/// arriving and the generation finishing. `cancelled` is deliberately **absent**, exactly as it is for
/// the waveform and the spectrogram: a cancelled generation belongs to an operation the user already
/// replaced, so its result is discarded rather than shown.
public enum SignalLevelMetricsState: Sendable, Equatable {
    case loading
    case available(SignalLevelMetrics)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into.
    ///
    /// Returns `nil` for `cancelled`, because there is nothing to show: the operation that produced it
    /// has been superseded, and rendering it as an absence would blame the file for the user's own
    /// action.
    public init?(_ outcome: SignalLevelMetricsOutcome) {
        switch outcome {
        case let .available(metrics): self = .available(metrics)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// What producing a true peak measurement actually yielded, once it is over.
///
/// The same four outcomes its three siblings have, for the same four reasons — and it is a fourth
/// **outcome**, not a fourth field on one of theirs. `TruePeakMeasurement` never joins
/// `SignalLevelMetrics` (ADR-0018's rule applied by ADR-0019): a sample peak is a direct reduction over
/// stored values and a true peak is an estimate of a reconstruction that has to say which filter
/// produced it, so they are two measurements that happen to travel together, never one.
///
/// **Sharing a read does not merge outcomes.** True peak is folded from the same pass as the
/// spectrogram and the signal level metrics (ADR-0020), and it still answers entirely on its own: one
/// of the three failing says nothing about the other two.
public enum TruePeakOutcome: Sendable, Equatable {
    /// The file's true peak, per channel and overall. A channel that carried no samples reports `nil`
    /// rather than a measured zero — a complete answer for a file with no audio, not an absence.
    case available(TruePeakMeasurement)
    /// The file exposed no usable frame count. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file.
    case cancelled
}

/// What the surface can say about a true peak right now.
///
/// The extra case over `TruePeakOutcome` is `loading`, which exists between the report arriving and the
/// shared read finishing. `cancelled` is deliberately **absent**, exactly as it is for the other three:
/// a cancelled generation belongs to an operation the user already replaced, so its result is discarded
/// rather than shown.
public enum TruePeakState: Sendable, Equatable {
    case loading
    case available(TruePeakMeasurement)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into.
    ///
    /// Returns `nil` for `cancelled`, because there is nothing to show: the operation that produced it
    /// has been superseded, and rendering it as an absence would blame the file for the user's own
    /// action.
    public init?(_ outcome: TruePeakOutcome) {
        switch outcome {
        case let .available(measurement): self = .available(measurement)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// What producing an integrated loudness actually yielded, once it is over.
///
/// The same four outcomes as its siblings, for the same four reasons — and one of them carries more
/// weight here than anywhere else. **`unavailable` is the answer to two different questions**, and
/// deliberately only one case:
///
/// - a **configuration this measurement cannot describe honestly**: a sample rate whose weighting has
///   not been derived, or more than two channels, where BS.1770-5 weights by position and the pipeline
///   has no layout;
/// - a **file it could describe but the standard defines no value for**: shorter than one 400 ms gating
///   block, or with no block clearing the absolute gate.
///
/// They stay one case because the capability's own contract makes them one: a measurement that could not
/// be produced is reported as **not computable**, never as a floor value, a substituted number or a
/// zero. Splitting them would put a distinction on screen that the report has no sentence for, and the
/// causes are kept where they are actually known — in the accumulator and the composition.
///
/// **−70 LUFS never appears here.** It is the standard's absolute gate, not a result, and the reference
/// implementation's −70.000 floor is a display convention this project does not copy (ADR-0022 §6).
public enum LoudnessOutcome: Sendable, Equatable {
    /// The programme's integrated loudness, with the methodology that produced it.
    case available(LoudnessMeasurement)
    /// No value: either the configuration is one this measurement does not claim, or the standard
    /// defines no result for this file. Caused by the file or by our own declared scope, and **not** a
    /// failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file.
    case cancelled
}

/// What became of the programme bandwidth — the highest frequency carrying persistent, prominent
/// energy, measured within 60 dB of the file's own programme peak.
///
/// Shaped exactly like `LoudnessOutcome`, and for the same reason: its accumulator declines to be
/// built for a stream it does not claim, which is an absence rather than a failure.
public enum SignificantBandwidthOutcome: Sendable, Equatable {
    /// The measurement, with the methodology that produced it.
    case available(SignificantBandwidth)
    /// No value: the configuration is one this measurement does not claim, or the file carried no
    /// window the method could use. Caused by the file or by our own declared scope, **not** a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file.
    case cancelled
}

/// What the surface can say about a programme bandwidth right now.
///
/// It carries the measurement from the flow to the surface, which renders it as its own section
/// between the integrated loudness and the spectrogram. It was deliberately introduced one group
/// *before* that view existed, so that a value which reached the model and stopped there would be a
/// wiring bug the flow tests could see rather than one hidden behind a missing surface.
public enum SignificantBandwidthState: Sendable, Equatable {
    case loading
    case available(SignificantBandwidth)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into; `nil` for `cancelled`, exactly as its five siblings.
    public init?(_ outcome: SignificantBandwidthOutcome) {
        switch outcome {
        case let .available(model): self = .available(model)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// What the surface can say about an integrated loudness right now.
///
/// The extra case over `LoudnessOutcome` is `loading`; `cancelled` is deliberately **absent**, exactly
/// as it is for the other four.
public enum LoudnessState: Sendable, Equatable {
    case loading
    case available(LoudnessMeasurement)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into.
    ///
    /// Returns `nil` for `cancelled`, because there is nothing to show: the operation that produced it
    /// has been superseded, and rendering it as an absence would blame the file for the user's own
    /// action.
    public init?(_ outcome: LoudnessOutcome) {
        switch outcome {
        case let .available(measurement): self = .available(measurement)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// A report together with whatever is currently known about its visualisations.
///
/// All four are **beside** each other, never nested: neither the waveform nor the spectrogram nor the
/// signal level metrics nor the true peak is part of `InspectionReport`, so the report's meaning, its
/// warnings, its status and the `schemaVersion` 1 export are untouched by anything here (ADR-0009,
/// ADR-0016 decision 14, ADR-0018). This type is not `Codable` and is never persisted.
///
/// The four are also beside **each other**: they settle independently, and none's state is derived
/// from another's. Three of them now come from one read of the file (ADR-0020), which changes when
/// they settle and nothing about what any of them means.
///
/// It knows no `URL`, no AVFoundation type and no filesystem: the location stays in
/// `AudioInspectorApp` (ADR-0010).
public struct InspectionPresentation: Sendable, Equatable {
    /// The inspection's own result, complete on its own. A visualisation that is loading, absent or
    /// failed never withholds it.
    public let report: InspectionReport
    public var waveform: WaveformState
    public var spectrogram: SpectrogramState
    public var signalLevelMetrics: SignalLevelMetricsState
    public var truePeak: TruePeakState
    public var loudness: LoudnessState
    /// Shown as its own section, and asserted by the flow tests to arrive here before it can be.
    public var significantBandwidth: SignificantBandwidthState
    /// The stream this file's samples were read from, once the read has finished — `nil` before that,
    /// and `nil` for a file that exposed no usable frame count.
    ///
    /// **It arrives with the settled outcome, not with the report**, because that is when it exists: the
    /// report is published before the first sample is read. It is what `AudioDecoding` reported, carried
    /// here unchanged from `InspectionAnalyses`, and it is **never** derived from `report.properties` —
    /// those are what the file's header declares, and this is what was actually decoded.
    ///
    /// It exists so this file's drawings can state their own extent. `WaveformEnvelope` carries a frame
    /// count and no sample rate, so an envelope alone cannot say how long a file is; taking both
    /// drawings' extents from one description is what stops a waveform lane and a spectrogram lane
    /// disagreeing about the same file.
    public var stream: PCMStreamDescription?

    public init(
        report: InspectionReport,
        waveform: WaveformState,
        spectrogram: SpectrogramState = .loading,
        signalLevelMetrics: SignalLevelMetricsState = .loading,
        truePeak: TruePeakState = .loading,
        loudness: LoudnessState = .loading,
        significantBandwidth: SignificantBandwidthState = .loading,
        stream: PCMStreamDescription? = nil
    ) {
        self.report = report
        self.waveform = waveform
        self.spectrogram = spectrogram
        self.signalLevelMetrics = signalLevelMetrics
        self.truePeak = truePeak
        self.loudness = loudness
        self.significantBandwidth = significantBandwidth
        self.stream = stream
    }
}
