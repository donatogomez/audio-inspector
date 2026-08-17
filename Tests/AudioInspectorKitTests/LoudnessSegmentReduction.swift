import Foundation

// MARK: - Deliberately simplified reductions, for showing what a vector catches

/// Reductions over a vector's **segments**, used only to demonstrate that a vector discriminates.
///
/// **This is not BS.1770 and must never become it.** There is no K-weighting filter, no 400 ms block,
/// no 75 % overlap and no per-block loudness: it collapses each segment to its duration and level and
/// averages energy across them. It is the *wrong* implementation on purpose, so a test can show that a
/// published expectation rejects it.
///
/// It is calibrated by construction rather than by assumption: for a single segment it returns that
/// segment's level unchanged, which is exactly what a stereo 1 kHz sine measures, and
/// `LoudnessTestVectorTests` asserts that against the published tests before using it on anything else.
enum LoudnessSegmentReduction {
    private static func energy(_ dBFS: Double?) -> Double {
        guard let dBFS else { return 0 }
        return pow(10.0, dBFS / 10.0)
    }

    private static func level(ofEnergy energy: Double) -> Double {
        energy > 0 ? 10 * log10(energy) : -.infinity
    }

    /// Duration-weighted mean energy of `segments`, as a level. No gate at all.
    static func ungated(_ segments: [LoudnessSegmentSpec]) -> Double {
        let duration = segments.reduce(0.0) { $0 + $1.seconds }
        guard duration > 0 else { return -.infinity }
        let total = segments.reduce(0.0) { $0 + $1.seconds * energy($1.dBFS) }
        return level(ofEnergy: total / duration)
    }

    /// The same, over only the segments whose level clears `threshold`.
    static func gated(_ segments: [LoudnessSegmentSpec], above threshold: Double) -> Double {
        ungated(segments.filter { ($0.dBFS ?? -.infinity) > threshold })
    }

    /// The absolute gate alone, at BS.1770-5's −70.
    static func absoluteGated(_ segments: [LoudnessSegmentSpec]) -> Double {
        gated(segments, above: -70.0)
    }

    /// The threshold a meter derives: the absolutely-gated level minus `offset`.
    static func relativeThreshold(
        _ segments: [LoudnessSegmentSpec], offset: Double = 10.0, applyingAbsoluteGate: Bool = true
    ) -> Double {
        (applyingAbsoluteGate ? absoluteGated(segments) : ungated(segments)) - offset
    }

    /// Both gates, in the order BS.1770-5 applies them.
    static func fullyGated(
        _ segments: [LoudnessSegmentSpec], offset: Double = 10.0, applyingAbsoluteGate: Bool = true
    ) -> Double {
        let threshold = relativeThreshold(
            segments, offset: offset, applyingAbsoluteGate: applyingAbsoluteGate
        )
        let floor = applyingAbsoluteGate ? max(threshold, -70.0) : threshold
        return gated(segments, above: floor)
    }
}
