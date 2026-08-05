import AudioInspectorDomain

/// What the report surface can say about a waveform right now.
///
/// It deliberately mirrors, rather than reuses, the flow's own waveform state: feature modules depend
/// on `AudioInspectorDomain` and never on one another, so the surface that *draws* an envelope cannot
/// see the type the surface that *obtains* one uses. The composition root owns the translation, which
/// is also where the two vocabularies are allowed to differ — this one is about a drawing.
///
/// There is no cancelled case. A cancelled generation belongs to an operation the user already
/// replaced, so it never reaches a surface at all.
public enum WaveformPresentation: Sendable, Equatable {
    /// The report is on screen and the samples are still being read.
    case loading
    /// The envelope to draw. An envelope with no buckets is a complete answer for a file with no
    /// frames, not an absence — see `WaveformCopy`.
    case envelope(WaveformEnvelope)
    /// No envelope was produced. Caused by the file offering nothing to build one from, and never
    /// presented as a defect of the audio.
    case absent
    /// Producing one did not succeed. The message arrives already human and carries no path, no
    /// framework text and no stable code.
    case failed(message: String)
}

/// The words the waveform section shows, separated from the view so they can be asserted directly.
///
/// `headline` is the statement that stands **in place of** a drawing; `detail` is the quieter second
/// line beside it. `accessibilityLabel` is the whole section as one sentence, because a drawing cannot
/// be read and the section must be announced as a single element rather than as one per bucket.
struct WaveformSectionText: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String
}

/// Every string the waveform surface can produce.
///
/// Two rules, inherited from the report and sharpened by the fact that this one is a picture:
///
/// - **It states what the drawing is, never what it shows.** Nothing here calls the signal loud,
///   quiet, clipped, compressed, dynamic, healthy or damaged, and nothing presents the envelope as a
///   measurement or as evidence about bit depth, encoding or integrity.
/// - **Absence is said in words.** An empty area would leave the reader to guess, and a failure to
///   draw is not a finding about the file.
///
/// The bucket count is never mentioned. It is a cap on resolution, not a promise, and it is not
/// exported, persisted or shown anywhere else either.
enum WaveformCopy {
    /// The section's title, used both as the visible heading and as the first word an assistive reader
    /// hears, so the two never drift apart.
    static let title = "Waveform"

    static func text(for presentation: WaveformPresentation) -> WaveformSectionText {
        switch presentation {
        case .loading:
            sentence(headline: "Preparing the waveform…", spoken: "Preparing the waveform.")

        case let .envelope(envelope) where envelope.buckets.isEmpty:
            // A valid file with zero frames. The drawing would be a bare centre line, which says
            // nothing on its own, so the fact is stated instead.
            sentence(headline: "This file contains no audio frames, so there is nothing to draw.")

        case let .envelope(envelope):
            // The only case where the drawing itself is the content: the line beneath it names what it
            // is, and the spoken form is the same fact written as a full sentence.
            WaveformSectionText(
                headline: nil,
                detail: "Amplitude over the whole file, \(combinedChannels(envelope)).",
                accessibilityLabel:
                "\(title). An amplitude envelope of the whole file, \(combinedChannels(envelope))."
            )

        case .absent:
            sentence(
                headline: "No waveform for this file.",
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

    /// How the channels were folded together, said without the words the domain forbids: the envelope
    /// is the extremes across every channel, and calling it a mix or a downmix would describe an
    /// operation that never happened.
    private static func combinedChannels(_ envelope: WaveformEnvelope) -> String {
        "combined across \(HumanFormat.channelsExact(envelope.channelCount))"
    }

    /// Builds the two written lines and the spoken sentence from the same words, so a change to one
    /// cannot silently leave the other behind. `spoken` overrides the headline only where punctuation
    /// meant for the eye — an ellipsis — would be read aloud.
    private static func sentence(headline: String, detail: String? = nil, spoken: String? = nil) -> WaveformSectionText {
        WaveformSectionText(
            headline: headline,
            detail: detail,
            accessibilityLabel: (["\(title)."] + [spoken ?? headline, detail].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}
