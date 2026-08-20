/// The settled measurements one inspection derived from a file's samples, gathered so that adding one
/// more does not lengthen a signature.
///
/// **It has two consumers, and export is only the first.** It was introduced for the export chain and
/// its shape is what a comparison needs too — four optionals where `nil` means *nothing to report*, no
/// lifecycle, no defaults, four distinct types. `MeasurementComparison` takes two of these, so the
/// collapse from loading/absent/failed/cancelled happens once, in the feature, rather than once per
/// consumer.
///
/// **This is the container the export chain's own notes said the fourth measurement would have to
/// bring**, and it brings it. Three positional optionals were past the shape's comfortable width;
/// `ReportExporting`, `ReportExportAction` and `ReportExportModel` each carried a note saying so and
/// each deferred the work to whoever added a fourth, so that a refactor touching every call site of the
/// chain would not be hidden inside the change that added a measurement. It was introduced on its own,
/// against a byte-identity proof, before programme bandwidth was added to it.
///
/// ## What belongs here, and what deliberately does not
///
/// Only **settled domain measurements**. Three things are kept out on purpose:
///
/// - **The report.** It is not a measurement, it exists before the first sample is read, and folding it
///   in would suggest it waits for the audio. It stays its own parameter.
/// - **The visualisations.** `WaveformEnvelope` and `Spectrogram` are pictures of the samples, not
///   measurements of them, and neither has ever appeared under `measurements` on the wire. This is why
///   `InspectionAnalyses` is **not** reused here despite grouping the same producers: that type is the
///   *flow's* bundle, it carries both visualisations, and its fields are `…Outcome` values that model
///   lifecycle — `.failed`, `.cancelled` — which must never reach the wire.
/// - **Lifecycle of any kind.** Each field is `nil` when there is nothing to report, and `nil` is the
///   only absence there is. The caller collapses loading, absent, failed and cancelled to `nil` before
///   this value is built, so the export layer never has to decide what a half-finished measurement
///   serialises as.
///
/// It is not `Codable`. The wire shape is the export layer's own DTO, and a domain type that knew its
/// JSON form would put serialization in the domain.
public struct ReportMeasurements: Sendable, Equatable {
    /// Peak, RMS, DC offset and clipped-sample counts, per channel and overall.
    public var signalLevelMetrics: SignalLevelMetrics?
    /// The estimate of what the reconstructed waveform reaches between samples.
    public var truePeak: TruePeakMeasurement?
    /// The programme's gated loudness.
    public var loudness: LoudnessMeasurement?
    /// How far up the programme reaches persistently, inside its declared budget.
    public var programmeBandwidth: SignificantBandwidth?

    /// **No defaults.** A container exists so a signature stops growing, not so a field can be
    /// forgotten: every call site names every measurement, and omitting one is a compile error. This is
    /// the rule `InspectionAnalyses` already established for the flow's own bundle, applied here for the
    /// same reason — the four types are all distinct, so a swapped pair is a compile error too.
    public init(
        signalLevelMetrics: SignalLevelMetrics?,
        truePeak: TruePeakMeasurement?,
        loudness: LoudnessMeasurement?,
        programmeBandwidth: SignificantBandwidth?
    ) {
        self.signalLevelMetrics = signalLevelMetrics
        self.truePeak = truePeak
        self.loudness = loudness
        self.programmeBandwidth = programmeBandwidth
    }

    /// Nothing was measured. Named rather than spelled out at each call site, because "no measurements"
    /// is a state several callers genuinely have and repeating three `nil`s obscures it.
    public static let none = ReportMeasurements(
        signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil
    )
}
