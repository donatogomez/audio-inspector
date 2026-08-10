import AudioInspectorDomain

/// What the report surface can say about signal level metrics right now.
///
/// It mirrors, rather than reuses, the flow's own state, for the same reason `WaveformPresentation` and
/// `SpectrogramPresentation` do: feature modules depend on `AudioInspectorDomain` and never on one
/// another, so the surface that *presents* the metrics cannot see the type the surface that *obtains*
/// them uses. The composition root owns the translation.
///
/// There is no cancelled case. A cancelled generation belongs to an operation the user already
/// replaced, so it never reaches a surface at all.
public enum SignalLevelMetricsPresentation: Sendable, Equatable {
    /// The report is on screen and the samples are still being read and measured.
    case loading
    /// The measured metrics. A file with no audio frames is a complete answer (every value reports as
    /// not computable) — not an absence. See `SignalLevelMetricsCopy`.
    case metrics(SignalLevelMetrics)
    /// No metrics were produced. Caused by the file offering nothing to measure, and never presented as
    /// a defect of the audio.
    case absent
    /// Measuring them did not succeed. The message arrives already human and carries no path, no
    /// framework text and no stable code.
    case failed(message: String)
}

/// One presentable row: a name, its overall value (or none, when not computable), and a detail carrying
/// either the per-channel breakdown or the reason the overall value is absent. Mirrors `PropertyDisplay`'s
/// own shape — a value that speaks for itself, a detail that never hides the reason behind it.
struct SignalLevelMetricsRow: Equatable, Identifiable {
    let name: String
    let value: String?
    let detail: String?

    var id: String { name }

    /// One sentence for an assistive reader, so a row is announced as a coherent whole.
    var accessibilityLabel: String {
        [name, value, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The words the signal levels section shows when there are no rows to display — loading, absent or
/// failed. `nil` for `.metrics`, where the rows themselves carry the section's whole content.
struct SignalLevelMetricsSectionText: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String
}

/// Every string and every row the signal levels surface can produce.
///
/// The same two rules `WaveformCopy`/`SpectrogramCopy` state, sharpened for numbers rather than a
/// picture:
///
/// - **It states what was measured, never what it means.** Nothing here calls a level loud, quiet,
///   healthy, damaged, clean or distorted, and a non-zero clipped-sample count is reported as a count,
///   never as a diagnosis ("clipping detected").
/// - **Absence is said in words, and "not computable" is never confused with a measured zero.** A
///   channel with no samples reports as not computable; a channel with real silence reports a genuine,
///   computed zero. Collapsing the two into the same dash would lose exactly the distinction the domain
///   type exists to preserve.
enum SignalLevelMetricsCopy {
    /// The section's title, used both as the visible heading and as the first word an assistive reader
    /// hears, so the two never drift apart.
    static let title = "Signal levels"

    static func text(for presentation: SignalLevelMetricsPresentation) -> SignalLevelMetricsSectionText? {
        switch presentation {
        case .loading:
            sentence(headline: "Preparing the signal levels…", spoken: "Preparing the signal levels.")

        case .metrics:
            // The rows are the content; there is no separate section-level statement to make.
            nil

        case .absent:
            sentence(
                headline: "No signal level metrics for this file.",
                detail: "Its samples were not read. Everything else in this report is unchanged."
            )

        case let .failed(message):
            sentence(
                headline: message,
                detail: "This is a limit of measuring these levels, not something read from the audio. "
                    + "Everything else in this report is unchanged."
            )
        }
    }

    /// The four rows, in a fixed order: peak, RMS, DC offset, clipped-sample count.
    static func rows(for metrics: SignalLevelMetrics) -> [SignalLevelMetricsRow] {
        [
            row(
                name: "Peak sample",
                overall: metrics.overallPeakSample,
                perChannel: metrics.channels.map(\.peakSample),
                format: HumanFormat.decibelsFullScale
            ),
            row(
                name: "RMS level",
                overall: metrics.overallRMS,
                perChannel: metrics.channels.map(\.rms),
                format: HumanFormat.decibelsFullScale
            ),
            row(
                name: "DC offset",
                overall: metrics.overallDCOffset,
                perChannel: metrics.channels.map(\.dcOffset),
                format: HumanFormat.linearOffset
            ),
            clippedSamplesRow(metrics),
        ]
    }

    /// One row for a metric that can be "not computable": present when every channel carried at least
    /// one sample, `nil` (with a reason, never a bare dash) when none did.
    ///
    /// The per-channel breakdown appears only when there is more than one channel — for a single
    /// channel it would repeat the overall value with no new information, exactly the "unnecessary wall
    /// of numbers" this surface avoids for stereo and beyond.
    private static func row(
        name: String,
        overall: Float?,
        perChannel: [Float?],
        format: (Float) -> String
    ) -> SignalLevelMetricsRow {
        guard let overall else {
            return SignalLevelMetricsRow(
                name: name,
                value: nil,
                detail: "Not computable — this file has no audio frames."
            )
        }
        return SignalLevelMetricsRow(
            name: name,
            value: format(overall),
            detail: perChannel.count > 1 ? perChannelDetail(perChannel, format: format) : nil
        )
    }

    /// `clippedSampleCount` is always a plain, defined count — never absent, even for a channel with no
    /// samples — so this row never has a "not computable" state the way the other three do.
    private static func clippedSamplesRow(_ metrics: SignalLevelMetrics) -> SignalLevelMetricsRow {
        let perChannel = metrics.channels.count > 1
            ? metrics.channels.enumerated()
                .map { index, channel in "Channel \(index + 1): \(count(channel.clippedSampleCount))" }
                .joined(separator: " · ")
            : nil
        let explanation = "Samples at or beyond full scale."
        return SignalLevelMetricsRow(
            name: "Clipped samples",
            value: count(metrics.overallClippedSampleCount),
            detail: perChannel.map { "\($0). \(explanation)" } ?? explanation
        )
    }

    /// `Channel 1: …, Channel 2: …` — never `Left`/`Right`: the domain reports a **count** of channels,
    /// never a layout (the same reasoning `HumanFormat.channels(_:)` already states), so nothing here
    /// may assert a stereo pair the file never declared.
    private static func perChannelDetail(_ values: [Float?], format: (Float) -> String) -> String {
        values.enumerated()
            .map { index, value in "Channel \(index + 1): \(value.map(format) ?? "not computable")" }
            .joined(separator: " · ")
    }

    private static func count(_ value: Int) -> String {
        value.formatted(.number.locale(HumanFormat.locale))
    }

    private static func sentence(headline: String, detail: String? = nil, spoken: String? = nil) -> SignalLevelMetricsSectionText {
        SignalLevelMetricsSectionText(
            headline: headline,
            detail: detail,
            accessibilityLabel: (["\(title)."] + [spoken ?? headline, detail].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}
