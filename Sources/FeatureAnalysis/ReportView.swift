import AudioInspectorDomain
import SwiftUI

/// A minimal, data-driven SwiftUI view that presents an already-available `InspectionReport`: the
/// file identity, the eight technical properties with their distinct states, the report's warnings,
/// and the global status — plus an export action.
///
/// It is **purely presentational**: it takes a non-optional report as input and never inspects a
/// file, selects a source, owns the report's lifecycle, or knows `AudioFilePropertyReading`. The
/// export work is an injected `ReportExportAction` (wired by the composition root); the view holds
/// only the transient export phase. No AppKit, no `URL`, no filesystem.
public struct ReportView: View {
    private let report: InspectionReport
    private let waveform: WaveformPresentation
    private let spectrogram: SpectrogramPresentation
    private let signalLevelMetrics: SignalLevelMetricsPresentation
    private let truePeak: TruePeakPresentation
    private let loudness: LoudnessPresentation
    private let programmeBandwidth: SignificantBandwidthPresentation
    private let comparison: ComparisonPresentation
    @State private var exportModel: ReportExportModel

    /// Every sample-based analysis is a **required** parameter with no default. A default would let a
    /// caller forget one and ship a report that silently shows nothing where a state belongs.
    public init(
        report: InspectionReport,
        waveform: WaveformPresentation,
        spectrogram: SpectrogramPresentation,
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation,
        comparison: ComparisonPresentation = .none,
        export: @escaping ReportExportAction
    ) {
        self.report = report
        self.waveform = waveform
        self.spectrogram = spectrogram
        self.signalLevelMetrics = signalLevelMetrics
        self.truePeak = truePeak
        self.loudness = loudness
        self.programmeBandwidth = programmeBandwidth
        self.comparison = comparison
        _exportModel = State(initialValue: ReportExportModel(action: export))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroHeader
                waveformSection
                // Directly beneath the waveform: both concern amplitude/level over the file, and read
                // together — the waveform shows it as a picture, these rows summarise it as numbers.
                // The spectrogram, which concerns frequency rather than level, follows both.
                signalLevelMetricsSection
                // **Beneath the signal levels, above the spectrogram.** It belongs with them because it
                // is amplitude, and after them because it is a different kind of amplitude: those rows
                // summarise the samples as stored, this estimates what the waveform reaches *between*
                // them. It is a section of its own rather than a fifth row up there, because it is
                // produced by a different method and that method has to travel with it (ADR-0019).
                truePeakSection
                // **Beneath the true peak, above the spectrogram.** It stays with the level sections
                // because it is about level, and it comes last of them because it is the least
                // sample-like: those two reduce the samples as stored or as reconstructed, this one
                // measures the *programme* through a frequency weighting and two gates. That is also
                // why it is a section of its own rather than a fifth signal-levels row — the method has
                // to travel with it (ADR-0006, ADR-0022), and a row has nowhere to put one.
                loudnessSection
                // **After the level sections, before the spectrogram.** It is the first measurement in
                // the report about *frequency* rather than level, so it leaves the three that reduce
                // amplitude behind it — and it comes before the spectrogram because it is a settled
                // number and that is a picture, the same order the waveform and the signal levels
                // already follow. It is a section of its own rather than a caption on the spectrogram
                // because it is a measurement with a method that has to travel with it (ADR-0023), and
                // because it is not a reading *of* that picture: the spectrogram is a different
                // transform at a different resolution, and putting them together would suggest one can
                // be checked against the other by eye.
                programmeBandwidthSection
                spectrogramSection
                propertiesSection
                // **After this file's own facts, before its warnings.** A comparison is a statement
                // about the properties just read, so it belongs next to them — and the report still
                // reads as a complete report first. When nothing is being compared this renders
                // nothing at all, so the surface is unchanged.
                ComparisonSection(presentation: comparison)
                warningsSection
                statusSection
                fileSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The export is an action, not a row of the report. `.toolbar` from here attaches it to the
        // window without moving `ReportExportModel` out of this view, so no ownership changes.
        .toolbar {
            ToolbarItem(placement: .primaryAction) { exportAction }
        }
    }

    // MARK: - Hero header — what this file is, at a glance

    /// The name, then the handful of facts that identify the file. Everything here also appears in full
    /// below: the header summarises, it does not replace. Nothing missing is filled in.
    private var heroHeader: some View {
        let summary = ReportPropertyFormatter.summary(for: report)
        return VStack(alignment: .leading, spacing: 6) {
            Text(summary.fileName)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            if !summary.highlights.isEmpty {
                Text(summary.highlights.joined(separator: "  ·  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // The interpunct is decoration; an assistive reader hears a list.
                    .accessibilityLabel(summary.highlights.joined(separator: ", "))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Waveform — a view of the whole file, at the same altitude as the header

    /// Placed directly under the summary and above the detail, because it answers the same
    /// glance-level question the header does: what is in this file, at a glance. Below the eight
    /// property rows it would sit under a scroll for no reason.
    ///
    /// It is a section like any other, and it is present in **every** state — including when there is
    /// nothing to draw — so an unavailable waveform is a sentence rather than a gap the reader has to
    /// interpret.
    private var waveformSection: some View {
        ReportSection(WaveformCopy.title) {
            WaveformSection(presentation: waveform)
        }
    }

    /// Directly beneath the waveform, and above the property rows, because the two drawings answer the
    /// same kind of question and are read together: the envelope says how loud the file is over time,
    /// the spectrogram says where its energy sits. For the question this whole slice exists to serve —
    /// *does this file's energy stop early?* — the spectrogram is the answer, and burying it under
    /// eight property rows would put the evidence below a scroll.
    ///
    /// Present in **every** state, including when there is nothing to draw, so an absent spectrogram is
    /// a sentence rather than a gap the reader has to interpret.
    private var spectrogramSection: some View {
        ReportSection(SpectrogramCopy.title) {
            SpectrogramSection(presentation: spectrogram)
        }
    }

    // MARK: - Signal levels — the numeric counterpart to the waveform's picture

    /// Present in **every** state, including when nothing was measured, so an absent or failed reading
    /// is a sentence rather than a gap the reader has to interpret — the same rule the waveform and the
    /// spectrogram already follow.
    private var signalLevelMetricsSection: some View {
        ReportSection(SignalLevelMetricsCopy.title) {
            SignalLevelMetricsSection(presentation: signalLevelMetrics)
        }
    }

    // MARK: - True peak — what the waveform reaches between the samples

    /// Present in **every** state, including when nothing was measured, so an absent or failed
    /// measurement is a sentence rather than a gap the reader has to interpret — the same rule every
    /// other analysis section already follows.
    private var truePeakSection: some View {
        ReportSection(TruePeakCopy.title) {
            TruePeakSection(presentation: truePeak)
        }
    }

    // MARK: - Integrated loudness — the programme's level, not the samples'

    /// Present in **every** state, including when nothing was measured, so an absent or failed
    /// measurement is a sentence rather than a gap the reader has to interpret — the same rule every
    /// other analysis section already follows.
    private var loudnessSection: some View {
        ReportSection(LoudnessCopy.title) {
            LoudnessSection(presentation: loudness)
        }
    }

    // MARK: - File identity (safe metadata only — never a location)

    /// Its own section, on `loudnessSection`'s precedent: one number, plus the resolution it sits on,
    /// plus the method that produced it. Present in every state, so an absence is a sentence rather than
    /// a gap the reader has to interpret.
    private var programmeBandwidthSection: some View {
        ReportSection(ProgrammeBandwidthCopy.title) {
            ProgrammeBandwidthSection(presentation: programmeBandwidth)
        }
    }

    private var fileSection: some View {
        ReportSection("File") {
            LabeledContent("Name", value: report.file.displayName)
            if let ext = report.file.fileExtension {
                LabeledContent("Extension", value: ext)
            }
            if let size = report.file.sizeBytes {
                LabeledContent("Size") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(HumanFormat.byteCount(size))
                        Text(HumanFormat.byteCountExact(size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let modifiedAt = report.file.modifiedAt {
                LabeledContent("Modified", value: HumanFormat.dateTime(modifiedAt))
            }
            LabeledContent("Source", value: sourceDescription)
        }
    }

    private var sourceDescription: String {
        switch report.file.source {
        case .userSelectedLocalFile:
            // Only the safe kind + disclosure — never the path/URL (which the domain does not carry).
            "User-selected local file (location omitted)"
        }
    }

    // MARK: - Technical properties (eight rows, states preserved)

    /// Grouped into what the file is and how it is encoded. Every one of the eight rows still appears.
    private var propertiesSection: some View {
        ForEach(ReportPropertyFormatter.groups(for: report.properties)) { group in
            ReportSection(group.name) {
                ForEach(group.properties) { property in
                    PropertyRow(property: property)
                }
            }
        }
    }

    // MARK: - Warnings (hidden entirely when there are none)

    @ViewBuilder private var warningsSection: some View {
        let warnings = ReportPropertyFormatter.displays(for: report.warnings)
        if !warnings.isEmpty {
            ReportSection("Notes") {
                ForEach(warnings) { warning in
                    VStack(alignment: .leading, spacing: 2) {
                        if let subject = warning.subject {
                            Text(subject).font(.callout.weight(.medium))
                        }
                        Text(warning.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(warning.accessibilityLabel)
                }
            }
        }
    }

    // MARK: - Outcome (about the reading, never about the audio)

    private var statusSection: some View {
        ReportSection("Result") {
            Text(ReportPropertyFormatter.outcome(
                for: report.status,
                properties: ReportPropertyFormatter.displays(for: report.properties)
            ).text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Export action (transient phase only)

    /// The transient phase sits beside the action rather than occupying a permanent row of the report.
    private var exportAction: some View {
        HStack(spacing: 8) {
            switch exportModel.phase {
            case .idle:
                EmptyView()
            case .exporting:
                Text("Exporting…").font(.callout).foregroundStyle(.secondary)
            case .succeeded:
                Text("Exported").font(.callout).foregroundStyle(.secondary)
            case let .failed(message):
                Text(message).font(.callout).foregroundStyle(.red)
            }

            Button("Export JSON…") {
                Task {
                    await exportModel.export(
                        report,
                        measurements: ReportMeasurements(
                            signalLevelMetrics: exportableSignalLevelMetrics,
                            truePeak: exportableTruePeak,
                            loudness: exportableLoudness
                        )
                    )
                }
            }
            .disabled(exportModel.phase == .exporting)
        }
    }

    /// The domain measurement to export, or `nil` when there is nothing to report — `loading`,
    /// `absent` and `failed` all collapse to `nil` here, so the export layer never has to decide what
    /// a UI-only state would mean on the wire (that decision belongs to this Feature, per ADR-0009).
    private var exportableSignalLevelMetrics: SignalLevelMetrics? {
        guard case let .metrics(metrics) = signalLevelMetrics else { return nil }
        return metrics
    }

    /// The same rule for the true peak: `loading`, `absent` and `failed` all collapse to `nil`, so the
    /// export layer never has to decide what a UI-only state would mean on the wire. **The JSON
    /// describes measurements, not lifecycle**, and a failure message in particular is a fact about this
    /// run rather than about the file.
    private var exportableTruePeak: TruePeakMeasurement? {
        guard case let .measurement(measurement) = truePeak else { return nil }
        return measurement
    }

    /// And the same rule again for the integrated loudness. Its `absent` carries more causes than its
    /// siblings' do — too short, too quiet to clear the gate, an unsupported configuration — and none of
    /// them survives to the wire: **the JSON describes measurements, not why one does not exist**, so
    /// every one of them collapses to the key simply not being there.
    private var exportableLoudness: LoudnessMeasurement? {
        guard case let .measurement(measurement) = loudness else { return nil }
        return measurement
    }
}

/// A titled block of the report. Replaces `Form` + `.formStyle(.grouped)`, whose grouped-inset look is
/// the idiom of a Preferences pane rather than of a document being examined.
struct ReportSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// One technical-property row: name, value, the state in words when it is not simply measured, and a
/// reason or exact figure as detail.
private struct PropertyRow: View {
    let property: PropertyDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The value carries more weight than its label — the opposite of a settings form.
            LabeledContent(property.name) {
                Text(valueText).fontWeight(.medium)
            }
            // A cleanly measured value carries no state label — the value speaks for itself.
            if let label = property.state.label {
                Label {
                    Text(label)
                } icon: {
                    if let symbol = property.state.symbolName {
                        Image(systemName: symbol)
                    }
                }
                .font(.caption)
                // Only a failure of the *reading* is alerting. An unreliable or undefined property is
                // an ordinary outcome, and colouring it would imply the file is worse.
                .foregroundStyle(property.state.isReadFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            if let detail = property.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element, one sentence — not four fragments read in sequence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(property.accessibilityLabel)
    }

    /// The value already carries its unit (`44.1 kHz`), so nothing is appended here.
    private var valueText: String {
        property.value ?? "—"
    }
}

#if DEBUG
// DEBUG-only sample for the Xcode preview canvas. It never enters the production flow.
private extension InspectionReport {
    static var preview: InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: "interview-side-a.m4a",
                fileExtension: "m4a",
                sizeBytes: 8_421_376,
                modifiedAt: Date(timeIntervalSince1970: 1_749_718_980),
                source: .userSelectedLocalFile(displayName: "interview-side-a.m4a", locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(
                container: .available("mpeg-4"),
                duration: .available(372.51),
                sampleRate: .available(44_100),
                channelCount: .available(2),
                bitDepth: .unsupported(reason: "AAC does not define a PCM bit depth"),
                codec: .available("aac"),
                declaredBitrate: .available(128_000),
                estimatedBitrate: .uncertain(value: 180_904, reason: "estimated from size and duration")
            ),
            warnings: [
                InspectionWarning(code: .propertyUnsupported, field: "bitDepth", kind: .unsupported, message: "Bit depth is not defined for this lossy codec."),
            ],
            status: .partial(message: "Some properties are not exposed by this format.")
        )
    }
}

private extension WaveformPresentation {
    /// A decaying tone, so the canvas shows something with a shape rather than a solid block.
    static var preview: WaveformPresentation {
        let buckets = (0 ..< 2_048).compactMap { index -> WaveformBucket? in
            let phase = Float(index) / 2_048
            let peak = (1 - phase) * abs(sin(phase * 24))
            return WaveformBucket(minimum: -peak, maximum: peak)
        }
        guard let envelope = WaveformEnvelope(buckets: buckets, frameCount: 13_230_000, channelCount: 2) else {
            return .absent
        }
        return .envelope(envelope)
    }
}

private extension SpectrogramPresentation {
    /// A band-limited sweep with an abrupt edge, so the preview shows the artefact the drawing exists
    /// to make visible rather than a solid block.
    static var preview: SpectrogramPresentation {
        let columns = 256
        let bands = 128
        let cutoffBand = bands * 3 / 4
        let values = (0 ..< columns * bands).map { index -> Float in
            let band = index % bands
            guard band < cutoffBand else { return Spectrogram.floorDecibels }
            let column = index / bands
            let sweep = Float(column) / Float(columns)
            return -100 + 90 * (1 - Float(band) / Float(cutoffBand)) * (0.4 + 0.6 * sweep)
        }
        guard let model = Spectrogram(
            values: values, columnCount: columns, bandCount: bands,
            sampleRate: 44_100, frameCount: 13_230_000, channelCount: 2
        ) else {
            return .absent
        }
        return .model(model)
    }
}

private extension SignalLevelMetricsPresentation {
    /// A stereo signal with an asymmetric peak between channels, so the preview shows the per-channel
    /// breakdown rather than two identical numbers.
    static var preview: SignalLevelMetricsPresentation {
        guard let left = SignalLevelMetrics.Channel(
                  sampleCount: 13_230_000, peakSample: 0.708, rms: 0.25, dcOffset: 0.0006, clippedSampleCount: 0
              ),
              let right = SignalLevelMetrics.Channel(
                  sampleCount: 13_230_000, peakSample: 0.501, rms: 0.18, dcOffset: -0.0011, clippedSampleCount: 12
              ),
              let metrics = SignalLevelMetrics(
                  channels: [left, right],
                  overallPeakSample: 0.708,
                  overallRMS: 0.22,
                  overallDCOffset: -0.0003,
                  overallClippedSampleCount: 12
              ) else {
            return .absent
        }
        return .metrics(metrics)
    }
}

private extension LoudnessPresentation {
    /// An ordinary programme level, negative and unremarkable — deliberately not a round number and
    /// deliberately not −23, so the canvas never shows the figure a target would be read into.
    static var preview: LoudnessPresentation {
        let method = LoudnessMethod(algorithm: .integratedBS1770v1, weighting: .publishedAt48kHz)
        guard let measurement = LoudnessMeasurement(integratedLoudness: -18.437, method: method) else {
            return .absent
        }
        return .measurement(measurement)
    }
}

private extension TruePeakPresentation {
    /// A stereo file whose reconstruction crosses full scale on one channel and not the other — the
    /// case this measurement exists for, shown as the plain fact it is.
    static var preview: TruePeakPresentation {
        guard let method = TruePeakMethod(oversamplingFactor: 8, filter: .polyphaseFIRv1),
              let left = TruePeakMeasurement.Channel(sampleCount: 13_230_000, truePeak: 1.087),
              let right = TruePeakMeasurement.Channel(sampleCount: 13_230_000, truePeak: 0.932),
              let measurement = TruePeakMeasurement(channels: [left, right], method: method) else {
            return .absent
        }
        return .measurement(measurement)
    }
}

extension SignificantBandwidthPresentation {
    /// A 48 kHz programme reading 16.1 kHz on a 23 Hz grid — an ordinary measurement, shown as the
    /// plain fact it is, with nothing about it treated as remarkable.
    static var preview: SignificantBandwidthPresentation {
        guard let method = SignificantBandwidthMethod(windowFrames: 2_048, hopFrames: 512, sampleRate: 48_000),
              let channel = SignificantBandwidth.Channel(frequency: 16_101.5625, resolution: 23.4375),
              let measurement = SignificantBandwidth(channels: [channel, channel], method: method) else {
            return .absent
        }
        return .measurement(measurement)
    }
}

#Preview {
    ReportView(
        report: .preview, waveform: .preview, spectrogram: .preview, signalLevelMetrics: .preview,
        truePeak: .preview, loudness: .preview, programmeBandwidth: .preview,
        export: { _, _ in .succeeded }
    )
}
#endif
