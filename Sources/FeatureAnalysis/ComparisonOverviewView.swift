import AudioInspectorDomain
import SwiftUI

/// **Comparison Overview — the two files, and deliberately almost nothing else** (ADR-0026 §8).
///
/// It names which file is which and says that the sections carry both. It does not compare them, and it
/// is built so that it *cannot*.
///
/// ## Why it holds so little
///
/// §8 refused a count of `same`, a count of `different`, a percentage, a similarity, a confidence and a
/// summary verdict, because `audio-two-file-comparison` forbids an aggregate over a comparison. It also
/// refused the one that looks innocent — a list filtered to *properties that differ* — and on a narrower
/// ground than the others: such a list publishes nothing while it has rows, and **fails on its empty
/// state**, where the absence of rows is itself the phrase *the two files match* that the capability's
/// own scenario refuses. The emptiness *is* the statement.
///
/// ## So the answer here is structural, not lexical
///
/// **Nothing on this surface varies with any outcome.** Every element is present for every pair: two
/// identities, each with whichever facts its own report carries, and the framing. There is no element
/// whose appearance or disappearance could mean anything about whether the files are alike, because
/// there is no element that appears or disappears for that reason at all. A render of two identical
/// files and a render of two files with nothing in common differ only where the two files' own facts
/// differ — which is what the all-agree gate asserts.
///
/// ## What is not here, and where it is
///
/// No technical property, no measurement, no outcome, no difference — those are Details and Measurements,
/// where the reader goes by selecting them. **No notes and no count of notes**, which the report carries
/// per file and Details presents in words. **No result of either reading, and no comparison of the two**:
/// a result is a statement about a reading, and an outcome over two readings would be a verdict about
/// them rather than a fact about either file. No path, no URL, no directory — the domain carries none.
public struct ComparisonOverviewView: View {
    /// The file being inspected. It is the subject throughout, present in every comparison state — the
    /// second file's identity arrives only once its own inspection has settled.
    private let report: InspectionReport
    private let comparison: ComparisonPresentation

    public init(report: InspectionReport, comparison: ComparisonPresentation) {
        self.report = report
        self.comparison = comparison
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                framing
                identity(ComparisonCopy.firstFile, report.file)
                secondIdentity
            }
            // Details' reading measure, because this is the same kind of surface: a wider window gets
            // more space around the section, not longer lines.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
        }
    }

    /// The words that say what this is and what it is not — `ComparisonCopy`'s own, unchanged since the
    /// comparison shipped. They are what stops two identities side by side reading as a comparison of
    /// them.
    private var framing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ComparisonOverviewCopy.twoFilesAreOpen)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ComparisonOverviewCopy.whereEachSectionLooks)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The second file's own identity once it exists, and an honest sentence before then.
    ///
    /// **No placeholder identity.** A second column of dashes would be a value the surface does not have,
    /// and a reader cannot tell an invented blank from a file whose name is missing.
    @ViewBuilder
    private var secondIdentity: some View {
        switch comparison {
        case .none:
            // Not reachable: the composition root shows the inspection overview when there is no
            // comparison. Named rather than defaulted so a new state has to be answered here.
            EmptyView()
        case .loading:
            state(ComparisonCopy.loading, detail: nil, isFailure: false)
        case let .ready(comparison, _):
            identity(ComparisonCopy.secondFile, comparison.second.file)
        case let .failed(message):
            state(ComparisonCopy.failedHeadline, detail: message, isFailure: true)
        }
    }

    /// One file's identifying facts, under the label naming its **position**. Never *original* and
    /// *copy*, never *source* and *derived*: those name a relationship this surface cannot establish.
    private func identity(_ position: String, _ file: AudioFileReference) -> some View {
        ReportSection(position) {
            OverviewIdentityRow(name: "Name", value: file.displayName, selectable: true)
            if let ext = file.fileExtension {
                OverviewIdentityRow(name: "Extension", value: ext)
            }
            if let size = file.sizeBytes {
                OverviewIdentityRow(name: "Size", value: HumanFormat.byteCount(size))
            }
            if let modifiedAt = file.modifiedAt {
                OverviewIdentityRow(name: "Modified", value: HumanFormat.dateTime(modifiedAt))
            }
            OverviewIdentityRow(name: "Source", value: sourceDescription(file))
        }
    }

    /// Only the safe kind plus its disclosure — never the path, which the domain does not carry. The same
    /// sentence every other surface states, because it is the same fact.
    private func sourceDescription(_ file: AudioFileReference) -> String {
        switch file.source {
        case .userSelectedLocalFile:
            "User-selected local file (location omitted)"
        }
    }

    /// What is happening to the second file, where its identity would be. **The only emphasis on this
    /// surface**, and it is about an inspection rather than about either file's audio.
    private func state(_ headline: String, detail: String?, isFailure: Bool) -> some View {
        ReportSection(ComparisonCopy.secondFile) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(isFailure ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([ComparisonCopy.secondFile, headline, detail].compactMap { $0 }.joined(separator: ". "))
        }
    }
}

/// This surface's own words — and it needed its own.
///
/// **`ComparisonCopy.subtitle` was the obvious candidate and is wrong here.** It says *"The technical
/// facts of both files, side by side"*, which described the page this slice removed: this surface shows
/// no technical facts at all. It also carries *same*, *differs* and *better* — legitimately, as the
/// disclaimer it is, beside a table of outcomes — but a surface whose whole guarantee is that no outcome
/// can reach it should not open by naming three of them. The sentence keeps its place beside the rows it
/// was written for.
///
/// What is left says two things and neither is about the files: how many are open, and where to look.
enum ComparisonOverviewCopy {
    static let twoFilesAreOpen = "Two files are open. Each is named below by its position."

    static let whereEachSectionLooks =
        "Every section presents both of them: their technical facts in Details, their measurements in "
            + "Measurements, and their drawings in Waveform and Spectrum."
}

/// One identifying fact, against the section's shared label column.
///
/// Its own type rather than the inspection overview's row for the reason R5 gave for not reusing
/// `WaveformSection`: that row carries a property's certainty state, and an identity has none — giving it
/// a place for one would invite a later slice to fill it with an outcome.
private struct OverviewIdentityRow: View {
    let name: String
    let value: String
    var selectable = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Group {
                if selectable {
                    Text(value).font(.callout).textSelection(.enabled)
                } else {
                    Text(value).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(value)")
    }
}
