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
    @State private var exportModel: ReportExportModel

    public init(report: InspectionReport, export: @escaping ReportExportAction) {
        self.report = report
        _exportModel = State(initialValue: ReportExportModel(action: export))
    }

    public var body: some View {
        Form {
            fileSection
            propertiesSection
            warningsSection
            statusSection
            exportSection
        }
        .formStyle(.grouped)
    }

    // MARK: - File identity (safe metadata only — never a location)

    private var fileSection: some View {
        Section("File") {
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

    private var propertiesSection: some View {
        Section("Technical properties") {
            ForEach(ReportPropertyFormatter.displays(for: report.properties)) { property in
                PropertyRow(property: property)
            }
        }
    }

    // MARK: - Warnings (hidden entirely when there are none)

    @ViewBuilder private var warningsSection: some View {
        let warnings = ReportPropertyFormatter.displays(for: report.warnings)
        if !warnings.isEmpty {
            Section("Notes") {
                ForEach(warnings) { warning in
                    VStack(alignment: .leading, spacing: 2) {
                        if let subject = warning.subject {
                            Text(subject).font(.callout)
                        }
                        Text(warning.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Outcome (about the reading, never about the audio)

    private var statusSection: some View {
        Section("Result") {
            Text(ReportPropertyFormatter.outcome(
                for: report.status,
                properties: ReportPropertyFormatter.displays(for: report.properties)
            ).text)
            .font(.callout)
        }
    }

    // MARK: - Export action (transient phase only)

    private var exportSection: some View {
        Section("Export") {
            Button("Export JSON…") {
                Task { await exportModel.export(report) }
            }
            .disabled(exportModel.phase == .exporting)

            switch exportModel.phase {
            case .idle:
                EmptyView()
            case .exporting:
                Text("Exporting…").foregroundStyle(.secondary)
            case .succeeded:
                Text("Exported").foregroundStyle(.secondary)
            case let .failed(message):
                Text(message).foregroundStyle(.red)
            }
        }
    }
}

/// One technical-property row: name, state, value (+ unit) when present, and a reason/error detail.
private struct PropertyRow: View {
    let property: PropertyDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(property.name) {
                Text(valueText)
            }
            // A cleanly measured value carries no state label — the value speaks for itself.
            if let label = property.state.label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let detail = property.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

#Preview {
    ReportView(report: .preview, export: { _ in .succeeded })
}
#endif
