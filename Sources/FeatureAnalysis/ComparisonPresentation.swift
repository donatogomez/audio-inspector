import AudioInspectorDomain

/// What the surface can say about a comparison right now.
///
/// The presentation layer's own vocabulary, mirroring `SpectrogramPresentation`: the flow's states are
/// translated into this at the composition root, so `FeatureAnalysis` never learns about operations,
/// selections or the second file's inspection.
public enum ComparisonPresentation: Equatable, Sendable {
    /// Nothing has been asked for. The report reads exactly as it does without this feature.
    case none
    /// A second file is being chosen or inspected. The report stays fully visible.
    case loading
    /// A comparison of the report on screen against a second file.
    case ready(FileComparison)
    /// The second file could not be opened for inspection at all — a failure of the comparison, never
    /// of the report on screen.
    case failed(message: String)
}

/// What comparing one property established, in the user's terms.
///
/// A **closed** presentation enum, decoupled from `PropertyComparison` exactly as
/// `PropertyPresentationState` is decoupled from `Property`: renaming a domain case can never silently
/// change what a person reads. It carries no value, because the two values are already on the row.
enum ComparisonOutcomeDisplay: Equatable {
    case same
    case different
    /// Carries the reason, which always names what each side actually was.
    case notComparable(reason: String)

    /// Plain words, and deliberately flat ones.
    ///
    /// **No direction anywhere.** Not *higher*, *lower*, *improved*, *reduced*, *better* or *worse* —
    /// two values differing is an observation, and the moment the word implies a direction the surface
    /// has started ranking two files (ADR-0017).
    var text: String {
        switch self {
        case .same: "Same"
        case .different: "Different"
        case let .notComparable(reason): reason
        }
    }

    /// Whether the outcome is worth a quieter treatment. Never a colour that means good or bad — the
    /// text carries the whole meaning, and this only keeps an explanation from shouting.
    var isSecondary: Bool {
        if case .notComparable = self { return true }
        return false
    }
}

/// One property, as both files reported it, plus what comparing them established.
///
/// The two sides are full `PropertyDisplay` rows, which is what keeps **the values visible even when
/// nothing could be compared**: two uncertain estimates still show their numbers and still say they
/// were read but are not reliable — the surface simply declines to call them the same or different.
struct ComparisonRowDisplay: Equatable, Identifiable {
    let name: String
    let first: PropertyDisplay
    let second: PropertyDisplay
    let outcome: ComparisonOutcomeDisplay

    var id: String { name }

    /// One side as a phrase: the value it carries, and how it was read when that is worth saying.
    static func sideText(_ display: PropertyDisplay) -> String {
        let parts = [display.value, display.state.label].compactMap { $0 }
        return parts.isEmpty ? "No value" : parts.joined(separator: ", ")
    }

    /// One sentence for an assistive reader, in the order the row reads: the property, each file's
    /// value, then the outcome. **Nothing here characterises either file.**
    var accessibilityLabel: String {
        "\(name). First file: \(Self.sideText(first)). Second file: \(Self.sideText(second)). \(outcome.text)"
    }
}

/// Turns a `FileComparison` into presentable rows. Pure and deterministic, so it is unit-tested with no
/// view at all.
enum ComparisonFormatter {

    /// The eight rows, in the order the report already presents these properties.
    ///
    /// Both sides go through **`ReportPropertyFormatter.displays(for:)`**, the same function the report
    /// uses, so a value reads identically whether it appears in a report or in a comparison — and no
    /// second set of formatters can drift from the first.
    ///
    /// The outcomes are listed in that same order, which is the one coupling here; the order is pinned
    /// by a test rather than trusted.
    static func rows(for comparison: FileComparison) -> [ComparisonRowDisplay] {
        let first = ReportPropertyFormatter.displays(for: comparison.first.properties)
        let second = ReportPropertyFormatter.displays(for: comparison.second.properties)
        let outcomes: [ComparisonOutcomeDisplay] = [
            outcome(comparison.container),
            outcome(comparison.duration),
            outcome(comparison.sampleRate),
            outcome(comparison.channelCount),
            outcome(comparison.bitDepth),
            outcome(comparison.codec),
            outcome(comparison.declaredBitrate),
            outcome(comparison.estimatedBitrate),
        ]

        guard first.count == outcomes.count, second.count == outcomes.count else { return [] }

        return zip(zip(first, second), outcomes).map { sides, outcome in
            ComparisonRowDisplay(
                name: sides.0.name,
                first: sides.0,
                second: sides.1,
                outcome: outcome
            )
        }
    }

    /// Total over the three cases, with no `default`: a case added to the domain fails to compile here
    /// rather than falling into a catch-all that says something vague.
    static func outcome<Value>(_ comparison: PropertyComparison<Value>) -> ComparisonOutcomeDisplay {
        switch comparison {
        case .same: .same
        case .different: .different
        case let .incomparable(gap): .notComparable(reason: reason(for: gap))
        }
    }

    /// **Why nothing could be compared, named from the states themselves.**
    ///
    /// Not one generic sentence: `ComparisonGap` knows which side was which and what each one was, so
    /// the surface says it. *"This format cannot express bit depth"* and *"reading it failed"* are
    /// different things to tell a person, and the domain already keeps them apart.
    static func reason(for gap: ComparisonGap) -> String {
        switch gap {
        case let .firstAvailable(second):
            "Not comparable — \(clause(second, isFirst: false))."
        case let .secondAvailable(first):
            "Not comparable — \(clause(first, isFirst: true))."
        case let .neitherAvailable(first, second) where first == second:
            "Not comparable — \(sharedClause(first))."
        case let .neitherAvailable(first, second):
            "Not comparable — \(clause(first, isFirst: true)) and \(clause(second, isFirst: false))."
        }
    }

    /// One side's situation, said about that side.
    private static func clause(_ state: NonAvailableState, isFirst: Bool) -> String {
        let file = isFirst ? "the first file" : "the second file"
        switch state {
        case .unavailable: return "\(file) does not carry this property"
        case .unsupported: return "\(file)'s format cannot express it"
        case .uncertain: return "\(file)'s value was read but is not reliable"
        case .failed: return "\(file)'s value could not be read"
        }
    }

    /// Both sides in the same situation, said once rather than twice.
    private static func sharedClause(_ state: NonAvailableState) -> String {
        switch state {
        case .unavailable: "neither file carries this property"
        case .unsupported: "neither format can express it"
        case .uncertain: "neither value is reliable"
        case .failed: "neither value could be read"
        }
    }
}

/// The words the comparison surface uses for everything that is not a row.
///
/// Every state the surface can be in is **said in text**; none of them is conveyed by a colour, an
/// icon or an empty area.
enum ComparisonCopy {
    static let title = "Comparison"

    /// What the section is, stated once so the reader knows what they are looking at — and what it is
    /// not, because that is the part a comparison table invites people to assume.
    static let subtitle =
        "The technical facts of both files, side by side. This says what is the same and what differs; "
            + "it does not say which file is better, or whether they hold the same recording."

    static let loading = "Inspecting the second file…"

    static let contextTitle = "Shown for context, not compared"

    /// Why some facts appear without an outcome, so their absence from the comparison reads as a
    /// decision rather than an omission.
    static let contextDetail =
        "A file's extension and size are facts about the file rather than about its audio, and two "
            + "copies of the same audio routinely differ in both. They are shown for each file and "
            + "left unjudged."

    static let firstFile = "First file"
    static let secondFile = "Second file"
    static let outcomeColumn = "Comparison"

    /// The heading a failed second inspection gets. The message beneath it comes from the flow.
    static let failedHeadline = "The second file could not be inspected."

    /// How one file's own inspection ended, said in the report's own words rather than in a new set.
    static func statusLine(for report: InspectionReport) -> String {
        ReportPropertyFormatter.outcome(
            for: report.status,
            properties: ReportPropertyFormatter.displays(for: report.properties)
        ).text
    }
}
