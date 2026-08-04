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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroHeader
                propertiesSection
                warningsSection
                statusSection
                fileSection
                exportSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            }
        }
    }

    // MARK: - File identity (safe metadata only — never a location)

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

    private var exportSection: some View {
        ReportSection("Export") {
            HStack(spacing: 10) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled block of the report. Replaces `Form` + `.formStyle(.grouped)`, whose grouped-inset look is
/// the idiom of a Preferences pane rather than of a document being examined.
private struct ReportSection<Content: View>: View {
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

/// One technical-property row: name, state, value (+ unit) when present, and a reason/error detail.
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
