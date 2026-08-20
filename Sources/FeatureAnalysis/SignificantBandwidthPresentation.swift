import AudioInspectorDomain

/// What the report surface can say about a file's programme bandwidth right now.
///
/// It mirrors, rather than reuses, the flow's own state, for the reason `LoudnessPresentation` and its
/// three siblings already give: feature modules see `AudioInspectorDomain` and never one another, so the
/// surface that *presents* the measurement cannot see the type the surface that *obtains* it uses. The
/// composition root owns the translation.
///
/// **It carries the domain value rather than pre-formatted text**, exactly as its five siblings do, and
/// that is forced rather than chosen: the rounding rule depends on `HumanFormat`, which lives here, so a
/// presentation of finished strings would have to be built in `AudioInspectorApp` and would put
/// formatting in the composition root. The view never reads a field off this value — every string it
/// draws comes from `ProgrammeBandwidthCopy`.
///
/// There is no cancelled case. A cancelled measurement belongs to an operation the user already
/// replaced, so it never reaches a surface at all.
public enum SignificantBandwidthPresentation: Sendable, Equatable {
    /// The report is on screen and the samples are still being read and measured.
    case loading
    /// The measured programme bandwidth, with the methodology that produced it.
    ///
    /// A measurement can exist and still carry **no reading** — a file whose windows were all eligible
    /// but none of whose bins met the persistence criterion produces one. That is an absence to a
    /// reader, and `ProgrammeBandwidthCopy` says so in words; it is not a second enum case, because the
    /// distinction is about what to *show* and belongs with the rest of the wording decisions.
    case measurement(SignificantBandwidth)
    /// **No value exists for this file.** Too little audio to analyse, or nothing in it carrying energy
    /// the method counts. An absence caused by the file, never a defect of the audio and never a
    /// failure — and never a substituted zero, floor or Nyquist.
    case absent
    /// Measuring it did not succeed. The message arrives already human and carries no path, no framework
    /// text and no stable code.
    case failed(message: String)
}

/// One presentable row: a name and its value.
///
/// **It has no `detail`**, for `LoudnessRow`'s own reason — there is no per-channel breakdown to put
/// there. Programme bandwidth *is* measured per channel, and the surface deliberately shows only the
/// summary: a per-channel list would invite comparing one channel against another, which is a step
/// towards a verdict and is not what this row is for. The per-channel readings travel on the wire.
struct ProgrammeBandwidthRow: Equatable {
    let name: String
    let value: String

    /// One sentence for an assistive reader, so the value and its unit are announced together — the
    /// rule loudness's and true peak's rows already follow.
    var accessibilityLabel: String { "\(name), \(value)" }
}

/// The words the section shows when there is no row to display — loading, absent, failed, or a
/// measurement that carries no reading. `nil` where the rows and the method line are the whole content.
struct ProgrammeBandwidthSectionText: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String
}

/// Every string the programme bandwidth surface can produce.
///
/// The rules `LoudnessCopy` states, plus the three this measurement adds — and it needs them more than
/// any other number in this report, because a top frequency is the figure a reader is most likely to
/// convert into a story about where the file came from:
///
/// - **No verdict, and no comparison against the declared sample rate.** Nothing here compares the
///   reading to Nyquist, to the file's rate, or to any other file; nothing calls a result high, low,
///   full, limited or wasted; nothing changes colour, weight or wording as the value approaches the top
///   of the band. A reading of 20 kHz in a 192 kHz file is rendered exactly as one in a 44.1 kHz file.
/// - **It is not a cut-off.** The value is the centre of the highest bin that met the criterion, biased
///   *upward* by the window's own leakage. Calling it a cut-off, a limit, or a filter would assert
///   something about how the file was made, which this measurement cannot see.
/// - **It says nothing about provenance or quality.** No codec is named or guessed at, no encoding step
///   is inferred, and there is no sentence anywhere disclaiming one — a disclaimer would introduce the
///   very frame the measurement refuses, and would be longer than the fact it qualifies. The method
///   line states what was measured; what it is worth for a reader's purpose is theirs to decide.
///
/// And the rule shared with every other measurement here: **absence is said in words and never as a
/// number.** Zero is not a bandwidth, and Nyquist is not a result.
enum ProgrammeBandwidthCopy {
    /// The section's title, used as the visible heading, as the value row's name, and as the first word
    /// an assistive reader hears, so the three never drift apart.
    ///
    /// **"Programme bandwidth", never "significant bandwidth"** — the type keeps the domain's name for
    /// symmetry with its state and outcome, and the surface uses the product's. And none of the names
    /// that would overclaim: not "effective sample rate", not "real"/"true" bandwidth, not "audio
    /// resolution", not "cut-off frequency". It describes the measurement, not a property of the world.
    static let title = "Programme bandwidth"

    /// The resolution's own row name. **Deliberately not "±"**: see `resolutionRow(for:)`.
    static let resolutionTitle = "Analysis resolution"

    static func text(for presentation: SignificantBandwidthPresentation) -> ProgrammeBandwidthSectionText? {
        switch presentation {
        case .loading:
            sentence(headline: "Preparing the programme bandwidth…", spoken: "Preparing the programme bandwidth.")

        case let .measurement(measurement) where measurement.overall == nil:
            // A measurement that produced no reading reads to a person exactly as an absence does, and
            // is said in the same words. Nothing here reports it as zero.
            notComputable

        case .measurement:
            // The two rows and the method line are the content; there is no separate statement to make.
            nil

        case .absent:
            notComputable

        case let .failed(message):
            sentence(
                headline: message,
                detail: "This is a limit of measuring the programme bandwidth, not something read from "
                    + "the audio. Everything else in this report is unchanged."
            )
        }
    }

    private static var notComputable: ProgrammeBandwidthSectionText {
        sentence(
            headline: "Not computable for this file.",
            detail: "Either it offers too little audio to analyse, or no part of it carries energy this "
                + "measurement counts. Everything else in this report is unchanged."
        )
    }

    /// The value row, or `nil` where the measurement carries no reading — in which case `text(for:)`
    /// supplies the sentence instead. There is no branch here that invents a number.
    static func row(for measurement: SignificantBandwidth) -> ProgrammeBandwidthRow? {
        guard let overall = measurement.overall else { return nil }
        return ProgrammeBandwidthRow(
            name: title,
            value: HumanFormat.programmeBandwidth(overall.frequency, resolution: overall.resolution)
        )
    }

    /// The resolution, as **its own row and its own quantity**.
    ///
    /// This is the one presentation decision this measurement could most easily get wrong, so it is
    /// stated here rather than left to a reader of the view. `resolution` is the **width of an analysis
    /// bin** — the grid the answer is quantised onto. It is *not* an uncertainty, a confidence interval
    /// or an error bar, and ADR-0023 refuses to publish a false bound of uncertainty. So it is never
    /// rendered as `16.1 ± 0.02 kHz`: that form says "the true value lies in this interval", which is a
    /// claim this measurement does not make and could not support. The reading is already biased one
    /// way — upward, by the window's leakage — so a symmetric interval around it would be wrong twice.
    ///
    /// Two rows, two names, no operator between them.
    static func resolutionRow(for measurement: SignificantBandwidth) -> ProgrammeBandwidthRow? {
        guard let overall = measurement.overall else { return nil }
        return ProgrammeBandwidthRow(
            name: resolutionTitle, value: HumanFormat.frequency(overall.resolution)
        )
    }

    /// How the value was produced, in words, beside the value itself — the visible half of ADR-0006's
    /// "the constants are recorded with the result", as loudness and true peak already do it.
    ///
    /// **Three ideas, and only three**: the highest frequency, that it is carried *persistently*, and
    /// that "persistently" is judged within 60 dB of the programme's own strongest spectral level. The
    /// prominence threshold, the persistence fraction, the window shape, its length and its hop are all
    /// part of the method's identity and all travel on the wire — none of them helps a person read the
    /// number, and a line naming them would read as a specification rather than a sentence.
    ///
    /// "Spectral level" rather than "peak" is load-bearing: the true peak section sits two sections
    /// above this one and is a peak of the *samples*. Sharing a word would suggest the budget is
    /// measured against that, which it is not.
    ///
    /// An identity this surface does **not** recognise is named verbatim rather than described with the
    /// known one's words — the precedent true peak set and loudness followed, for the case where
    /// inventing a description would mislead most.
    static func method(for measurement: SignificantBandwidth) -> String {
        guard measurement.method.identifier == SignificantBandwidthMethod.v1 else {
            return "Measured with the \(measurement.method.identifier) method."
        }
        return "The highest frequency this programme carries persistently, within 60 dB of its own "
            + "strongest spectral level."
    }

    /// Spoken form of the method line. Identical words — it exists so the view never has to build one
    /// sentence for the eye and another for an assistive reader.
    static func methodAccessibilityLabel(for measurement: SignificantBandwidth) -> String {
        "How it was measured. \(method(for: measurement))"
    }

    private static func sentence(
        headline: String, detail: String? = nil, spoken: String? = nil
    ) -> ProgrammeBandwidthSectionText {
        ProgrammeBandwidthSectionText(
            headline: headline,
            detail: detail,
            accessibilityLabel: (["\(title)."] + [spoken ?? headline, detail].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}
