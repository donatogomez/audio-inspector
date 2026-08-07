import AudioInspectorDomain

/// What the report surface can say about a spectrogram right now.
///
/// It mirrors, rather than reuses, the flow's own spectrogram state, for the same reason
/// `WaveformPresentation` does: feature modules depend on `AudioInspectorDomain` and never on one
/// another, so the surface that *draws* a model cannot see the type the surface that *obtains* one
/// uses. The composition root owns the translation.
///
/// There is no cancelled case. A cancelled generation belongs to an operation the user already
/// replaced, so it never reaches a surface at all.
public enum SpectrogramPresentation: Sendable, Equatable {
    /// The report is on screen and the samples are still being read and transformed.
    case loading
    /// The model to draw. A model with no columns is a complete answer for a file with no audio, or
    /// one shorter than a single analysis window — not an absence. See `SpectrogramCopy`.
    case model(Spectrogram)
    /// No model was produced. Caused by the file offering nothing to size an analysis against, and
    /// never presented as a defect of the audio.
    case absent
    /// Producing one did not succeed. The message arrives already human and carries no path, no
    /// framework text and no stable code.
    case failed(message: String)
}

/// The words the spectrogram section shows, separated from the view so they can be asserted directly.
struct SpectrogramSectionText: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String
}

/// Every string the spectrogram surface can produce.
///
/// The rules are the waveform's, sharpened by what this particular picture invites a reader to
/// conclude:
///
/// - **It states what the drawing is, never what it implies.** Nothing here says lossy, transcoded,
///   fake, compressed, damaged, authentic or original; names no probable encoder or bitrate; and never
///   presents the drawing as a measurement. A cutoff is compatible with lossy encoding, with the master
///   and with deliberate filtering, and separating those is a different capability's job.
/// - **Absence is said in words.** An empty area would leave the reader to guess, and a failure to draw
///   is not a finding about the file.
///
/// The column and band counts are never mentioned. They are caps on resolution, not promises, and are
/// not exported, persisted or shown anywhere else either.
enum SpectrogramCopy {
    /// The section's title, used both as the visible heading and as the first word an assistive reader
    /// hears, so the two never drift apart.
    static let title = "Spectrogram"

    /// The floor and ceiling the legend states. They are the **legend's** range, not the model's: the
    /// domain keeps values above 0 dBFS exactly as measured.
    static let legendRange: ClosedRange<Float> = -120 ... 0

    static func text(for presentation: SpectrogramPresentation) -> SpectrogramSectionText {
        switch presentation {
        case .loading:
            sentence(headline: "Preparing the spectrogram…", spoken: "Preparing the spectrogram.")

        case let .model(model) where model.columnCount == 0:
            // A valid model with no columns: either the file holds no audio, or it is shorter than one
            // analysis window. Both are complete answers, and neither is a fault.
            sentence(
                headline: "This file is too short to analyse as a spectrogram.",
                detail: "It contains less than one full analysis window, so there is nothing to draw. "
                    + "Everything else in this report is unchanged."
            )

        case let .model(model):
            // The only case where the drawing itself is the content.
            SpectrogramSectionText(
                headline: nil,
                detail: description(of: model),
                accessibilityLabel: "\(title). \(spokenDescription(of: model))"
            )

        case .absent:
            sentence(
                headline: "No spectrogram for this file.",
                detail: "Its samples were not read. Everything else in this report is unchanged."
            )

        case let .failed(message):
            sentence(
                headline: message,
                detail: "This is a limit of producing the drawing, not something read from the audio. "
                    + "Everything else in this report is unchanged."
            )
        }
    }

    /// The written line beneath a drawing: what it covers and how the axes read.
    static func description(of model: Spectrogram) -> String {
        "Energy over the whole file, 0 Hz to \(HumanFormat.frequency(model.nyquist)), "
            + "\(combinedChannels(model))."
    }

    /// The spoken form, which carries what the eye gets from the legend and the axes.
    ///
    /// **Its length does not depend on the model's size.** One cell or 524 288, the sentence is the
    /// same shape: a drawing cannot be read aloud cell by cell, and attempting it would be worse than
    /// silence.
    static func spokenDescription(of model: Spectrogram) -> String {
        "A spectrogram of the whole file. Frequency runs from 0 Hz to "
            + "\(HumanFormat.frequency(model.nyquist)), and colour shows energy from "
            + "\(Int(legendRange.lowerBound)) to \(Int(legendRange.upperBound)) dBFS, "
            + "\(combinedChannels(model)). It shows where energy is present and does not, on its own, "
            + "establish how the file was produced."
    }

    /// How the channels were folded together, said without the words the domain forbids: the model is
    /// the maximum across every channel taken per frequency, and calling it a mix or a downmix would
    /// describe an operation that never happened.
    private static func combinedChannels(_ model: Spectrogram) -> String {
        "combined across \(HumanFormat.channelsExact(model.channelCount))"
    }

    private static func sentence(headline: String, detail: String? = nil, spoken: String? = nil) -> SpectrogramSectionText {
        SpectrogramSectionText(
            headline: headline,
            detail: detail,
            accessibilityLabel: (["\(title)."] + [spoken ?? headline, detail].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}
