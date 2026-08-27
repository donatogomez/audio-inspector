import AudioInspectorDomain

/// The outcome of one "pick a file and inspect it" attempt, expressed **outside Domain** and free of
/// `URL`, AppKit, and filesystem types. The Feature only needs these three cases to drive its state;
/// the panel, the security-scoped access, the metadata read, and the reader all live in
/// `AudioInspectorApp`, which produces one of these values.
///
/// A **global** inspection failure is *not* one of these cases: it arrives as an `InspectionReport`
/// whose `status` is `.failed`, because the domain already models it that way. `preparationFailed`
/// covers only the failures that happen *before* an inspection can be attempted at all.
public enum SourceInspectionOutcome: Sendable, Equatable {
    /// The user dismissed the picker — **not** an error.
    case cancelled
    /// A file was inspected; the report carries the outcome, including a global failure. The analyses
    /// travel **beside** it in one value, and whatever became of any of them never changes the report.
    ///
    /// **The container arrived with the sixth analysis, as the previous note said it must.** Five
    /// labelled payloads were at the edge of what is comfortable to read, and appending a sixth would
    /// have made the signature the thing a reader has to parse before the meaning. `InspectionAnalyses`
    /// groups them without inventing architecture: the report stays outside it because it has a
    /// different lifecycle — it exists before any sample is read — and `InspectionPresentation` stays
    /// separate because it models *states* that change as results arrive, not final values.
    case inspected(InspectionReport, analyses: InspectionAnalyses)
    /// The selection could not be turned into an inspectable file at all.
    case preparationFailed
}

/// Everything an inspection derived **from the file's samples**, and the stream they were read from,
/// gathered so that adding one more does not lengthen a signature.
///
/// Only sample-derived results belong here. `InspectionReport` does not: it is read from the file's
/// metadata, it exists before the first chunk, and folding it in would suggest it waits for the audio.
/// Presentation state does not either: `InspectionPresentation` holds `…State` values that move from
/// `.loading` as results arrive, where these are the settled outcomes.
///
/// **`stream` is the one member that is not a result**, and it is here rather than beside this value
/// because it is what makes an artefact readable: an envelope carries a frame count and no sample rate,
/// so it cannot state its own duration, and a description that travelled separately could be paired
/// with a different read's. Inside, that pairing is unrepresentable. It is what the decoder reported,
/// never rebuilt from the report's declared properties — those are what the header claims, and this is
/// what was decoded.
///
/// Each analysis still settles **on its own** — that was the reason five separate payloads were
/// defensible for as long as they were, and grouping them changes nothing about it. A failure in one is
/// still a failure in one.
public struct InspectionAnalyses: Sendable, Equatable {
    /// What became of the amplitude envelope.
    public var waveform: WaveformOutcome
    /// What became of the spectral model.
    public var spectrogram: SpectrogramOutcome
    /// What became of the signal level metrics.
    public var signalLevelMetrics: SignalLevelMetricsOutcome
    /// What became of the true peak measurement.
    public var truePeak: TruePeakOutcome
    /// What became of the integrated loudness.
    public var loudness: LoudnessOutcome
    /// What became of the programme bandwidth.
    ///
    /// **No default.** A container exists so a signature stops growing, not so a field can be
    /// forgotten: omitting this is a compile error, which is the strongest form of "the tests fail".
    public var significantBandwidth: SignificantBandwidthOutcome
    /// The stream the six results above were produced from, or `nil` when the read never had one —
    /// which `AudioDecoding` reports exactly when the file exposed no usable total frame count, and
    /// which leaves every result absent anyway.
    ///
    /// **It carries a default, and the six results deliberately do not.** The rule above exists so an
    /// *analysis* cannot be forgotten, and this is not one: production builds this value in a single
    /// place, and a caller that omits it does not get a quietly wrong axis — it gets no visual bundle at
    /// all, because `FileVisuals` refuses an artefact whose stream is unknown. The failure is loud and
    /// the tests that would catch it are the ones that read the bundle.
    public var stream: PCMStreamDescription?

    public init(
        waveform: WaveformOutcome,
        spectrogram: SpectrogramOutcome,
        signalLevelMetrics: SignalLevelMetricsOutcome,
        truePeak: TruePeakOutcome,
        loudness: LoudnessOutcome,
        significantBandwidth: SignificantBandwidthOutcome,
        stream: PCMStreamDescription? = nil
    ) {
        self.waveform = waveform
        self.spectrogram = spectrogram
        self.signalLevelMetrics = signalLevelMetrics
        self.truePeak = truePeak
        self.loudness = loudness
        self.significantBandwidth = significantBandwidth
        self.stream = stream
    }
}

/// One thing an inspection has finished, delivered the moment it is known.
///
/// A single channel rather than one handler per result, so adding a third visualisation later cannot
/// mean a third parameter threaded through every call site. Each case updates **only** its own part of
/// the presentation: a waveform that arrives first does not wait for the spectrogram, and neither
/// waits for the other to fail.
public enum InspectionUpdate: Sendable {
    /// The report, the moment it exists — before either visualisation has been produced.
    case report(InspectionReport)
    /// What became of the amplitude envelope.
    case waveform(WaveformOutcome)
    /// What became of the spectral model.
    case spectrogram(SpectrogramOutcome)
    /// What became of the signal level metrics.
    case signalLevelMetrics(SignalLevelMetricsOutcome)
    /// What became of the true peak measurement.
    case truePeak(TruePeakOutcome)
    /// The integrated loudness, once the shared read has finished.
    case loudness(LoudnessOutcome)
    /// The programme bandwidth, once the shared read has finished.
    case significantBandwidth(SignificantBandwidthOutcome)
}

/// Receives each part of an inspection as it settles, on the main actor.
///
/// It exists so the report is not held hostage by optional extras: reading samples takes longer than
/// reading metadata, and the report is complete without either visualisation. `report` arrives at most
/// once per operation, and each visualisation at most once.
public typealias InspectionUpdateHandler = @MainActor (InspectionUpdate) -> Void

/// The action the import feature receives as an injected dependency from the composition root.
///
/// `@MainActor` (it drives a native panel) and `async` (it awaits the user's choice, the inspection and
/// then the visualisations). It reports each part through the given handler as soon as that part is
/// known, and returns the complete outcome once everything has settled. The Feature never learns how
/// the file is chosen, accessed, or read.
public typealias SourceInspectionAction = @MainActor (InspectionUpdateHandler) async -> SourceInspectionOutcome
