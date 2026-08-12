import AudioInspectorDomain
import Foundation

/// The single, explicit coupling point between the domain `InspectionReport` and the `schemaVersion`
/// 1 wire DTOs (ADR-0009). It **only** maps: it does not serialize JSON, write files, recalculate
/// warnings or status, or invent information. Warnings and status are carried faithfully from the
/// report (they were already derived by the use case); a global `failed` is never rewritten to
/// `partial`. The report's ephemeral `file.id` is intentionally **not** exported.
enum InspectionReportMapper {
    /// The one and only definition of the export schema version.
    static let schemaVersion = 1

    /// Builds the full envelope. `generatedAt` (the export instant) and `generator` are supplied by
    /// the exporter — they belong to the envelope, not the domain report.
    ///
    /// `signalLevelMetrics` is `nil` whenever no measurement is available to export — the caller has
    /// already collapsed `loading`/`unavailable`/`failed`/`cancelled` to `nil` before this is reached,
    /// so this mapper only ever sees "a real measurement exists" or "there is nothing to report" and
    /// never has to decide what a UI-only state would mean on the wire.
    static func envelope(
        for report: InspectionReport,
        signalLevelMetrics: SignalLevelMetrics?,
        truePeak: TruePeakMeasurement?,
        generatedAt: Date,
        generator: ReportGenerator
    ) -> ReportEnvelopeDTO {
        ReportEnvelopeDTO(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            generator: GeneratorDTO(name: generator.name, version: generator.version),
            inspectedFile: inspectedFile(from: report.file),
            technicalProperties: technicalProperties(from: report),
            warnings: report.warnings.map(warning(from:)),
            inspectionStatus: status(from: report.status),
            measurements: measurements(from: signalLevelMetrics, truePeak: truePeak)
        )
    }

    // MARK: - inspectedFile

    private static func inspectedFile(from file: AudioFileReference) -> InspectedFileDTO {
        InspectedFileDTO(
            name: file.displayName,
            fileExtension: file.fileExtension,
            sizeBytes: file.sizeBytes,
            modifiedAt: file.modifiedAt,
            source: source(from: file.source)
        )
    }

    private static func source(from source: AudioFileSource) -> SourceDTO {
        switch source {
        case let .userSelectedLocalFile(displayName, disclosure):
            SourceDTO(
                kind: "userSelectedLocalFile",
                displayName: displayName,
                locationDisclosure: locationDisclosure(disclosure)
            )
        }
    }

    private static func locationDisclosure(_ disclosure: LocationDisclosure) -> String {
        switch disclosure {
        case .omitted: "omitted"
        }
    }

    // MARK: - technicalProperties

    /// `{}` **iff** the inspection failed globally (no property was inspected); otherwise the nine
    /// explicit entries, each in its wire state. The gate is the global `status`, never the content of
    /// `TechnicalProperties` — a global failure carries an all-`unavailable` set that must **not** be
    /// emitted as nine `unavailable` entries.
    private static func technicalProperties(from report: InspectionReport) -> TechnicalPropertiesDTO {
        if case .failed = report.status {
            return TechnicalPropertiesDTO(entries: [])
        }
        let p = report.properties
        return TechnicalPropertiesDTO(entries: [
            ("container", property(p.container, unit: nil, scalar: JSONScalar.string)),
            ("duration", property(p.duration, unit: "seconds", scalar: JSONScalar.double)),
            ("sampleRate", property(p.sampleRate, unit: "hertz", scalar: JSONScalar.int)),
            ("channelCount", property(p.channelCount, unit: nil, scalar: JSONScalar.int)),
            ("bitDepth", property(p.bitDepth, unit: "bits", scalar: JSONScalar.int)),
            ("codec", property(p.codec, unit: nil, scalar: JSONScalar.string)),
            ("declaredBitrate", property(p.declaredBitrate, unit: "bitsPerSecond", scalar: JSONScalar.int)),
            ("estimatedBitrate", property(p.estimatedBitrate, unit: "bitsPerSecond", scalar: JSONScalar.int)),
            ("averageFileBitrate", property(p.averageFileBitrate, unit: "bitsPerSecond", scalar: JSONScalar.int)),
        ])
    }

    /// Maps one `Property<Value>` into its flat wire form, preserving each state distinctly. `unit`
    /// accompanies a carried value only (there is nothing to give a unit to when `value` is `null`).
    private static func property<Value>(
        _ property: Property<Value>,
        unit: String?,
        scalar: (Value) -> JSONScalar
    ) -> PropertyDTO {
        switch property {
        case let .available(value):
            PropertyDTO(state: "available", value: scalar(value), unit: unit, reason: nil, error: nil)
        case let .unavailable(reason):
            PropertyDTO(state: "unavailable", value: nil, unit: nil, reason: reason, error: nil)
        case let .unsupported(reason):
            PropertyDTO(state: "unsupported", value: nil, unit: nil, reason: reason, error: nil)
        case let .uncertain(value, reason):
            uncertain(value: value.map(scalar), reason: reason, unit: unit)
        case let .failed(failure):
            PropertyDTO(
                state: "failed",
                value: nil,
                unit: nil,
                reason: nil,
                error: CodeMessageDTO(code: failure.code.rawValue, message: failure.message)
            )
        }
    }

    private static func uncertain(value: JSONScalar?, reason: String, unit: String?) -> PropertyDTO {
        PropertyDTO(state: "uncertain", value: value, unit: value == nil ? nil : unit, reason: reason, error: nil)
    }

    // MARK: - measurements (additive — DSP-derived, never metadata; ADR-0018)

    /// `nil` when there is **nothing at all** to report — the resulting envelope omits `measurements`
    /// entirely (`ReportEnvelopeDTO`'s own synthesized `Encodable` drops a `nil` optional key), so a
    /// report exported without any measurement is byte-identical to one from before these capabilities
    /// existed.
    ///
    /// Each measurement is independently optional inside it, so adding true peak did not make signal
    /// levels conditional on it or the other way round: a report with only one of them carries only
    /// that one, and neither key is ever present as `null`.
    private static func measurements(
        from metrics: SignalLevelMetrics?,
        truePeak measurement: TruePeakMeasurement?
    ) -> MeasurementsDTO? {
        guard metrics != nil || measurement != nil else { return nil }
        return MeasurementsDTO(
            signalLevels: metrics.map(signalLevels(from:)),
            truePeak: measurement.map(truePeak(from:))
        )
    }

    /// `Float` → `Double` for the wire only, exactly as `signalLevels` does, and **linear throughout**:
    /// the dBTP conversion lives in `FeatureAnalysis` and this layer does not import it.
    ///
    /// The factor and the filter are read from the measurement's **own** recorded method rather than
    /// from the accumulator's constants, so the document describes the measurement that actually
    /// happened. Nothing about the filter's design is exported — the identifier is a stable name for a
    /// methodology, not a recipe for re-running one.
    private static func truePeak(from measurement: TruePeakMeasurement) -> TruePeakDTO {
        TruePeakDTO(
            overall: measurement.overallTruePeak.map(Double.init),
            channels: measurement.channels.map { channel in
                TruePeakChannelDTO(
                    sampleCount: channel.sampleCount,
                    truePeak: channel.truePeak.map(Double.init)
                )
            },
            method: TruePeakMethodDTO(
                oversamplingFactor: measurement.method.oversamplingFactor,
                filter: measurement.method.filter.rawValue
            )
        )
    }

    /// `Float` → `Double` for the wire only; the domain keeps `Float` throughout (matching
    /// `PCMChunk`'s own sample type), and JSON does not distinguish the two widths regardless. No
    /// clipping threshold is exported: it is a named constant of the analysis engine
    /// (`SignalLevelMetricsAccumulator.clippingThreshold`, in `AudioInspectorAnalysis`), not a fact
    /// this file's own measurement carries, and this project has no engine-version wire convention yet
    /// for a constant like it to be meaningfully anchored to — adding one in isolation here would be a
    /// stray field, not a considered contract addition.
    private static func signalLevels(from metrics: SignalLevelMetrics) -> SignalLevelsDTO {
        SignalLevelsDTO(
            overall: SignalLevelOverallDTO(
                peakSample: metrics.overallPeakSample.map(Double.init),
                rms: metrics.overallRMS.map(Double.init),
                dcOffset: metrics.overallDCOffset.map(Double.init),
                clippedSampleCount: metrics.overallClippedSampleCount
            ),
            channels: metrics.channels.map { channel in
                SignalLevelChannelDTO(
                    sampleCount: channel.sampleCount,
                    peakSample: channel.peakSample.map(Double.init),
                    rms: channel.rms.map(Double.init),
                    dcOffset: channel.dcOffset.map(Double.init),
                    clippedSampleCount: channel.clippedSampleCount
                )
            }
        )
    }

    // MARK: - warnings & status

    private static func warning(from warning: InspectionWarning) -> WarningDTO {
        WarningDTO(
            code: warning.code.rawValue,
            field: warning.field,
            kind: kind(warning.kind),
            message: warning.message
        )
    }

    private static func kind(_ kind: WarningKind) -> String {
        switch kind {
        case .unavailable: "unavailable"
        case .unsupported: "unsupported"
        case .uncertain: "uncertain"
        case .failed: "failed"
        }
    }

    private static func status(from status: InspectionStatus) -> InspectionStatusDTO {
        switch status {
        case .completed:
            InspectionStatusDTO(state: "completed", message: nil, error: nil)
        case let .partial(message):
            InspectionStatusDTO(state: "partial", message: message, error: nil)
        case let .failed(error):
            InspectionStatusDTO(
                state: "failed",
                message: error.message,
                error: CodeMessageDTO(code: error.code.rawValue, message: error.message)
            )
        }
    }
}
