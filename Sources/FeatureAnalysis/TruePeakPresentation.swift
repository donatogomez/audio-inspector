import AudioInspectorDomain

/// What the report surface can say about a true peak right now.
///
/// It mirrors, rather than reuses, the flow's own state, for the reason `SignalLevelMetricsPresentation`
/// already gives: feature modules see `AudioInspectorDomain` and never one another, so the surface that
/// *presents* the measurement cannot see the type the surface that *obtains* it uses. The composition
/// root owns the translation.
///
/// There is no cancelled case. A cancelled measurement belongs to an operation the user already
/// replaced, so it never reaches a surface at all.
public enum TruePeakPresentation: Sendable, Equatable {
    /// The report is on screen and the samples are still being read and measured.
    case loading
    /// The measured true peak. A file with no audio frames is a complete answer — every channel reports
    /// as not computable — not an absence. See `TruePeakCopy`.
    case measurement(TruePeakMeasurement)
    /// No measurement was produced. Caused by the file offering nothing to measure, and never presented
    /// as a defect of the audio.
    case absent
    /// Measuring it did not succeed. The message arrives already human and carries no path, no framework
    /// text and no stable code.
    case failed(message: String)
}

/// One presentable row: a name, its value (or none, when not computable), and a detail carrying either
/// the per-channel breakdown or the reason the value is absent. The shape
/// `SignalLevelMetricsRow` established, reused deliberately so the two sections read alike.
struct TruePeakRow: Equatable, Identifiable {
    let name: String
    let value: String?
    let detail: String?

    var id: String { name }

    /// One sentence for an assistive reader, so a row is announced as a coherent whole.
    var accessibilityLabel: String {
        [name, value, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The words the true peak section shows when there is no row to display — loading, absent or failed.
/// `nil` for `.measurement`, where the row and the method line carry the section's whole content.
struct TruePeakSectionText: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String
}

/// Every string the true peak surface can produce.
///
/// The rules `SignalLevelMetricsCopy` states, plus the one this measurement adds:
///
/// - **It states what was measured, never what it means.** A true peak above full scale is a technical
///   fact and is shown as one: no warning, no colour, no badge, no comparison against the sample peak,
///   and none of the vocabulary — *clipping detected*, *inter-sample clipping*, *overs*, *unsafe*, *too
///   hot* — that would turn a number into a diagnosis. The reader is told what the waveform reaches;
///   what that is worth is theirs to decide.
/// - **"Not computable" is never a measured zero.** A channel with no samples has no maximum; a channel
///   of genuine silence has a real, computed one that floors like every other level in this report.
/// - **The method travels with the value** (ADR-0006, ADR-0019). It is stated in words, taken from the
///   measurement's own recorded method rather than from a constant repeated here, and it claims **no
///   standard**: this filter was designed to recorded parameters and validated against analytic truth
///   and an independent meter, not built from BS.1770 Annex 2's own coefficients, so nothing here may
///   read as conformance to it.
enum TruePeakCopy {
    /// The section's title, used both as the visible heading and as the first word an assistive reader
    /// hears, so the two never drift apart.
    static let title = "True peak"

    /// The one phrase this project already uses for a value no audio could produce. Reused rather than
    /// reworded, so the same state never has two voices (task 7.3).
    static let notComputable = "Not computable — this file has no audio frames."

    static func text(for presentation: TruePeakPresentation) -> TruePeakSectionText? {
        switch presentation {
        case .loading:
            sentence(headline: "Preparing the true peak…", spoken: "Preparing the true peak.")

        case .measurement:
            // The row and the method line are the content; there is no separate statement to make.
            nil

        case .absent:
            sentence(
                headline: "No true peak for this file.",
                detail: "Its samples were not read. Everything else in this report is unchanged."
            )

        case let .failed(message):
            sentence(
                headline: message,
                detail: "This is a limit of measuring the true peak, not something read from the audio. "
                    + "Everything else in this report is unchanged."
            )
        }
    }

    /// The single row: the overall value, with the per-channel breakdown beneath it when there is more
    /// than one channel.
    ///
    /// **The overall value is the measurement's own.** `TruePeakMeasurement.overallTruePeak` is a
    /// computed maximum over the channels, so recomputing it here would be a second implementation free
    /// to drift from the first.
    static func rows(for measurement: TruePeakMeasurement) -> [TruePeakRow] {
        let perChannel = measurement.channels.map(\.truePeak)
        guard let overall = measurement.overallTruePeak else {
            // No channel carried a sample. Not a silent file — a file with nothing to measure.
            return [TruePeakRow(name: title, value: nil, detail: notComputable)]
        }
        return [
            TruePeakRow(
                name: title,
                value: HumanFormat.decibelsTruePeak(overall),
                detail: perChannel.count > 1 ? perChannelDetail(perChannel) : nil
            ),
        ]
    }

    /// How the value was produced, in words, beside the value itself.
    ///
    /// The factor comes from the measurement, never from a constant repeated here, so a file measured
    /// under a different method could not be described under this one. The filter is named in words for
    /// the identity the domain records; an identity this surface does not recognise is shown as it is
    /// rather than guessed at, because an unrecognised methodology is exactly the case where inventing a
    /// description would mislead.
    static func method(for measurement: TruePeakMeasurement) -> String {
        "Estimated by reconstructing the waveform between the stored samples, at "
            + "\(measurement.method.oversamplingFactor)× oversampling with \(filterPhrase(measurement.method.filter))."
    }

    /// Spoken form of the method line. Identical words — it exists so the view never has to build one
    /// sentence for the eye and another for an assistive reader.
    static func methodAccessibilityLabel(for measurement: TruePeakMeasurement) -> String {
        "How it was measured. \(method(for: measurement))"
    }

    private static func filterPhrase(_ filter: TruePeakFilterIdentifier) -> String {
        switch filter {
        case .polyphaseFIRv1: "a polyphase FIR reconstruction filter"
        default: "the \(filter.rawValue) reconstruction filter"
        }
    }

    /// `Channel 1: …, Channel 2: …` — never `Left`/`Right`: the domain reports a **count** of channels
    /// and never a layout, so nothing here may assert a pair the file never declared.
    private static func perChannelDetail(_ values: [Float?]) -> String {
        values.enumerated()
            .map { index, value in
                "Channel \(index + 1): \(value.map(HumanFormat.decibelsTruePeak) ?? "not computable")"
            }
            .joined(separator: " · ")
    }

    private static func sentence(headline: String, detail: String? = nil, spoken: String? = nil) -> TruePeakSectionText {
        TruePeakSectionText(
            headline: headline,
            detail: detail,
            accessibilityLabel: (["\(title)."] + [spoken ?? headline, detail].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}
