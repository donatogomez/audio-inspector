import AudioInspectorDomain

/// What one lane of a paired drawing says.
///
/// Four written parts and one spoken one, built from the same words so a change to what is read cannot
/// leave what is heard behind — the rule `WaveformCopy` and `SpectrogramCopy` already follow.
struct PairedLaneText: Equatable {
    /// Which file this lane belongs to, by **position**.
    let attribution: String
    /// The single-file sentence for this lane's state, where there is one.
    let headline: String?
    /// Its supporting line.
    let detail: String?
    /// What the part of the axis this file does not reach means — or `nil` when it reaches all of it.
    let outOfRange: String?
    /// The whole lane, spoken as one element.
    let accessibilityLabel: String
}

/// The words a paired drawing may use.
///
/// ## It borrows rather than invents
///
/// A lane's three states are the three the single-file surfaces already have sentences for, and those
/// sentences are reused verbatim: *"No waveform for this file."*, the failure's own message, *"This file
/// is too short to analyse as a spectrogram."* Writing a second set for the same facts would let the two
/// drift, and would say the same thing twice in two voices.
///
/// What this adds is exactly what a pair needs and one file does not: **which file** a lane is, and
/// **what the part of the axis it does not reach means**.
///
/// ## The two absences are different facts and get different sentences
///
/// - Past a file's own last frame, *it carries no audio there*. That is not silence — a silent bucket is
///   a **measured** zero, and nothing was measured here.
/// - Above a file's own Nyquist, *it cannot represent that range*. That is not quiet either: the ramp's
///   floor means measured-and-very-quiet, and this range was never available to measure.
///
/// A reader has to be able to tell them apart (group 10's second manual check), so they are two
/// sentences and never one.
///
/// ## What it may not say
///
/// Nothing here states, implies or scores a relationship between the two files. Not *same*, *different*,
/// *identical*, *similar*, *matching*; not *louder* or *quieter*; not *more* or *less* high-frequency
/// content; not *source*, *original*, *copy*, *derived*, *master*, *remaster*, *transcode* or *upsample*;
/// not *quality*, *better*, *worse* or which to keep (ADR-0025 §12). A differing channel count produces
/// no statement at all — each lane says what its own file carries, and comparing the counts is
/// `MeasurementComparison`'s where a per-channel measurement exists (ADR-0024 §7).
enum PairedVisualsCopy {

    /// Past this file's own audio. **Never** *silence*, *empty*, or *no signal*.
    static let outsideAudio = "This file carries no audio beyond here."

    /// Above this file's own Nyquist. **Never** *floor*, *no energy*, *truncated*, or a word about rate
    /// being better or worse.
    static let outsideRepresentableRange = "This file cannot represent this range."

    /// Which file a lane is — by position, and by nothing else.
    ///
    /// `ComparisonCopy`'s own wording, reused rather than restated: the rule that neither file is
    /// *original*, *copy*, *source* or *derived* is one rule, and it lives in one place.
    static func attribution(_ side: PairedWaveformAxis.Side) -> String {
        switch side {
        case .first: ComparisonCopy.firstFile
        case .second: ComparisonCopy.secondFile
        }
    }

    /// One waveform lane's words.
    ///
    /// - Parameter beyondItsAudio: whether this file's audio ends before the shared axis does.
    static func waveform(
        _ lane: PairedWaveformLane, for side: PairedWaveformAxis.Side, beyondItsAudio: Bool
    ) -> PairedLaneText {
        let single = WaveformCopy.text(for: lane.asSingle)
        return text(
            side: side,
            headline: single.headline,
            detail: single.detail,
            outOfRange: beyondItsAudio ? outsideAudio : nil,
            spoken: single.accessibilityLabel
        )
    }

    /// One spectral lane's words.
    ///
    /// - Parameter aboveItsNyquist: whether this file's own Nyquist is below the shared one.
    static func spectrogram(
        _ lane: PairedSpectrogramLane, for side: PairedWaveformAxis.Side, aboveItsNyquist: Bool
    ) -> PairedLaneText {
        let single = SpectrogramCopy.text(for: lane.asSingle)
        return text(
            side: side,
            headline: single.headline,
            detail: single.detail,
            outOfRange: aboveItsNyquist ? outsideRepresentableRange : nil,
            spoken: single.accessibilityLabel
        )
    }

    /// The shared time axis, in words, so nothing about it is available only as a picture.
    static func timeAxis(_ seconds: Double) -> String {
        "Time axis: 0 to \(HumanFormat.durationExact(seconds)), shared by both files."
    }

    /// The shared frequency axis, in words, for the same reason.
    static func frequencyAxis(_ hertz: Double) -> String {
        "Frequency axis: 0 Hz to \(HumanFormat.frequency(hertz)), shared by both files."
    }

    private static func text(
        side: PairedWaveformAxis.Side,
        headline: String?, detail: String?, outOfRange: String?, spoken: String
    ) -> PairedLaneText {
        let attribution = attribution(side)
        return PairedLaneText(
            attribution: attribution,
            headline: headline,
            detail: detail,
            outOfRange: outOfRange,
            // One element for the whole lane: the file it belongs to, then the drawing's own sentence,
            // then what the part of the axis it does not reach means. A drawing cannot be read, and
            // announcing 2 048 buckets or 524 288 cells in sequence would be far worse than silence.
            accessibilityLabel: (["\(attribution)."] + [spoken, outOfRange].compactMap { $0 })
                .joined(separator: " ")
        )
    }
}

extension PairedSpectrogramLane {
    /// The lane's three answers as the single-file section's four.
    ///
    /// **Total, and `loading` is never produced**: a lane belongs to a pair, and a pair exists only once
    /// both files have settled. A model with **no columns** stays a model, so the surface keeps saying
    /// *too short to analyse* rather than *no spectrogram for this file*.
    var asSingle: SpectrogramPresentation {
        switch self {
        case let .model(model): .model(model)
        case .absent: .absent
        case let .failed(message): .failed(message: message)
        }
    }
}
