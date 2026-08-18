import AudioInspectorDomain

/// What the report surface can say about a programme's integrated loudness right now.
///
/// It mirrors, rather than reuses, the flow's own state, for the reason `TruePeakPresentation` and its
/// two siblings already give: feature modules see `AudioInspectorDomain` and never one another, so the
/// surface that *presents* the measurement cannot see the type the surface that *obtains* it uses. The
/// composition root owns the translation.
///
/// There is no cancelled case. A cancelled measurement belongs to an operation the user already
/// replaced, so it never reaches a surface at all.
public enum LoudnessPresentation: Sendable, Equatable {
    /// The report is on screen and the samples are still being read and measured.
    case loading
    /// The measured integrated loudness, with the methodology that produced it.
    case measurement(LoudnessMeasurement)
    /// **No value exists for this file**, and this is where it differs from its siblings. A true peak is
    /// absent when the samples were not read; this is absent for that reason *and* for two the standard
    /// itself imposes — a programme too short to form a gating block, or one whose every block falls
    /// below the absolute gate — *and* for a configuration this measurement does not claim. All of them
    /// are an absence, never a defect of the audio and never a failure.
    case absent
    /// Measuring it did not succeed. The message arrives already human and carries no path, no framework
    /// text and no stable code.
    case failed(message: String)
}

/// The one presentable row: a name and its value.
///
/// **It has no `detail`**, unlike `TruePeakRow` and `SignalLevelMetricsRow`. Those carry a per-channel
/// breakdown; integrated loudness combines the channels *before* the quantity exists (`LoudnessMeasurement`'s
/// own contract), so there is no breakdown to carry and a field that could only ever be `nil` would be
/// an invitation to fill it. It is not `Identifiable` for the same reason: there is one row, never a
/// list.
struct LoudnessRow: Equatable {
    let name: String
    let value: String

    /// One sentence for an assistive reader, so the value and its unit are announced together — the
    /// rule true peak's row already follows.
    var accessibilityLabel: String { "\(name), \(value)" }
}

/// The words the loudness section shows when there is no row to display — loading, absent or failed.
/// `nil` for `.measurement`, where the row and the method line carry the section's whole content.
struct LoudnessSectionText: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String
}

/// Every string the integrated loudness surface can produce.
///
/// The rules `TruePeakCopy` states, plus the two this measurement adds — and it needs them more than
/// any other number in this report, because loudness is the one figure the surrounding industry
/// habitually attaches a target to:
///
/// - **No verdict and no target.** Nothing here calls a programme loud, quiet, hot or low; names a
///   platform; mentions normalisation; or compares the value against −14, −16, −23 or any other figure
///   — **including EBU R 128's own −23.0 LUFS**, which is a delivery requirement someone imposes on a
///   file, not a property this file has. A reader is told what was measured; what it is worth for their
///   purpose is theirs to decide.
/// - **No standard is worn as a seal.** The methodology is stated in plain words rather than by naming
///   a recommendation, so nothing on screen can read as certification, conformance or "EBU Mode". The
///   full identity — which algorithm, and where the weighting's coefficients came from — travels on the
///   wire, where it is an audit fact rather than a badge.
///
/// And the rule shared with every other measurement here: **absence is said in words and never as a
/// number.** −70 LUFS is the standard's absolute gate, not a result; the reference implementation's
/// −70.000 floor is a display convention this project does not copy (ADR-0022 §6).
enum LoudnessCopy {
    /// The section's title, used both as the visible heading, as the row's name, and as the first word
    /// an assistive reader hears, so the three never drift apart.
    static let title = "Integrated loudness"

    static func text(for presentation: LoudnessPresentation) -> LoudnessSectionText? {
        switch presentation {
        case .loading:
            sentence(headline: "Preparing the integrated loudness…", spoken: "Preparing the integrated loudness.")

        case .measurement:
            // The row and the method line are the content; there is no separate statement to make.
            nil

        case .absent:
            sentence(
                headline: "Not computable for this file.",
                detail: "Either it offers too little audio above the measurement's own threshold, or its "
                    + "channel count or sample rate is outside what this measurement covers. Everything "
                    + "else in this report is unchanged."
            )

        case let .failed(message):
            sentence(
                headline: message,
                detail: "This is a limit of measuring the integrated loudness, not something read from "
                    + "the audio. Everything else in this report is unchanged."
            )
        }
    }

    /// The single row: the programme's value, in LUFS, at the display precision the measurement is
    /// qualified to.
    ///
    /// It takes the value from the measurement and formats it — there is no branch here for a missing
    /// one, because `LoudnessMeasurement` cannot hold one. An unmeasurable file is `.absent`, and says
    /// so in the sentence above rather than as a row with a dash.
    static func row(for measurement: LoudnessMeasurement) -> LoudnessRow {
        LoudnessRow(name: title, value: HumanFormat.loudnessFullScale(measurement.integratedLoudness))
    }

    /// How the value was produced, in words, beside the value itself — the visible half of ADR-0006's
    /// "the constants are recorded with the result".
    ///
    /// ## Why the two known weightings read identically
    ///
    /// The domain records where the K-weighting coefficients came from: transcribed from the published
    /// 48 kHz tables, or derived to reproduce that same response at another rate. **That difference is
    /// deliberately not shown here.** It changes the provenance of the coefficients, not the quantity: the
    /// derivation exists precisely to give the same frequency response, and the measurement's
    /// rate-invariance is demonstrated rather than assumed. A reader interpreting the number gains
    /// nothing from it, while a line that varied by sample rate would suggest the two numbers mean
    /// different things. The full identity is exported, where it is an audit fact a consumer can act on.
    ///
    /// An identity this surface does **not** recognise is a different matter, and is named verbatim
    /// rather than described with the known one's words — the precedent `TruePeakCopy` set, for the case
    /// where inventing a description would mislead most.
    static func method(for measurement: LoudnessMeasurement) -> String {
        "Measured over the whole file with \(weightingPhrase(measurement.method.weighting)) and "
            + "\(gatingPhrase(measurement.method.algorithm))."
    }

    /// Spoken form of the method line. Identical words — it exists so the view never has to build one
    /// sentence for the eye and another for an assistive reader.
    static func methodAccessibilityLabel(for measurement: LoudnessMeasurement) -> String {
        "How it was measured. \(method(for: measurement))"
    }

    private static func weightingPhrase(_ weighting: LoudnessWeightingIdentifier) -> String {
        switch weighting {
        case .publishedAt48kHz, .derivedFrom48kHz: "K-weighting"
        default: "the \(weighting.rawValue) weighting"
        }
    }

    private static func gatingPhrase(_ algorithm: LoudnessAlgorithmIdentifier) -> String {
        switch algorithm {
        case .integratedBS1770v1: "programme gating"
        default: "the \(algorithm.rawValue) method"
        }
    }

    private static func sentence(
        headline: String, detail: String? = nil, spoken: String? = nil
    ) -> LoudnessSectionText {
        LoudnessSectionText(
            headline: headline,
            detail: detail,
            accessibilityLabel: (["\(title)."] + [spoken ?? headline, detail].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}
