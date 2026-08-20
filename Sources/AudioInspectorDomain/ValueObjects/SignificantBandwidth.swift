import Foundation

/// The whole methodology, named once, so that **the same identifier implies the same number**.
///
/// `LoudnessMethod`'s precedent exactly: identities, not editable configuration. Every parameter that
/// can move the answer is either pinned by the identifier or carried beside it, and nothing here is a
/// knob a caller may turn.
///
/// The parameters are `docs/adr/0023-significant-bandwidth-as-a-measured-fact.md` and
/// `docs/spikes/2026-08-19-significant-bandwidth-methodology.md`. The **60 dB programme budget is a
/// declared product parameter**, not a normative or perceptual boundary, which is why it is part of the
/// name rather than hidden inside the number.
public struct SignificantBandwidthMethod: Sendable, Equatable {
    /// The published identifier. `v1` is this project's own construction; there is no standard for this
    /// quantity and none is implied.
    public static let v1 = "programme-bandwidth-60db-v1"

    public let identifier: String
    /// Frames per transform. Fixed in **time**, not in samples, so the persistence criterion means the
    /// same thing at every sample rate.
    public let windowFrames: Int
    /// Frames advanced between transforms — a quarter of the window.
    public let hopFrames: Int
    /// The rate the analysis ran at, without which the two above are not interpretable.
    public let sampleRate: Double

    /// The window's duration, which is the parameter the method actually fixes.
    public var windowSeconds: Double { Double(windowFrames) / sampleRate }

    public init?(identifier: String = SignificantBandwidthMethod.v1, windowFrames: Int, hopFrames: Int, sampleRate: Double) {
        guard !identifier.isEmpty, windowFrames > 0, hopFrames > 0, hopFrames <= windowFrames,
              sampleRate.isFinite, sampleRate > 0 else { return nil }
        self.identifier = identifier
        self.windowFrames = windowFrames
        self.hopFrames = hopFrames
        self.sampleRate = sampleRate
    }
}

/// The highest frequency at which a file carries persistent, prominent energy — **a measured fact,
/// carrying no verdict of any kind.**
///
/// ## What it is not
///
/// - **Not a cut-off frequency.** On a graded roll-off the reading is where content stops crossing the
///   threshold, which is not the filter's corner: at 48 kHz with a 16 kHz knee, anything gentler than
///   about 85 dB/octave has no edge below Nyquist at all.
/// - **Not a claim about the whole file.** Only windows within the method's programme budget are
///   measured, and the budget is in the method's own name.
/// - **Not evidence of provenance.** Two files measuring the same extent says nothing about where
///   either came from, and `CLAUDE.md` forbids asserting transcoding from a frequency cut-off.
///
/// ## Zero and Nyquist
///
/// Neither is used as a floor or a sentinel: absence is `nil`, throughout. A *measured* value may
/// legitimately land on either end — a constant signal is DC and its highest qualifying bin is bin 0,
/// and a broadband noise floor genuinely reaches Nyquist. Those are readings, not stand-ins for
/// "nothing found", and a surface must not render them as absence.
public struct SignificantBandwidth: Sendable, Equatable {

    /// One channel's reading. Channels are measured **separately**: combining them before the
    /// threshold would let opposite-polarity content cancel, destroying evidence the file carries.
    public struct Channel: Sendable, Equatable {
        /// The centre of the highest qualifying bin.
        ///
        /// An **upper bound** on where the channel's content ends, overstating it by one bin when the
        /// edge falls on a bin and by up to `d(−50 dB) = 4.72` bins when it does not. The overstatement
        /// is one-sided and upward, and no surface may print more precision than `resolution` supports.
        public let frequency: Double
        /// `sampleRate / windowFrames`: the quantisation of the value above, **not** its uncertainty.
        public let resolution: Double

        public init?(frequency: Double, resolution: Double) {
            guard frequency.isFinite, frequency >= 0, resolution.isFinite, resolution > 0 else { return nil }
            self.frequency = frequency
            self.resolution = resolution
        }
    }

    /// One entry per channel, in the stream's own channel order. `nil` where that channel carried
    /// nothing meeting the criterion.
    ///
    /// **No layout is asserted.** The pipeline reads channel counts, never labels, so these are indices
    /// and nothing more: no front/left/centre, no assumption that two channels are a stereo pair.
    public let channels: [Channel?]

    /// The highest reading any channel produced — a **summary of the facts above**, not a claim about
    /// "the programme". The maximum rather than a mix, for the same reason the channels are separate.
    public let overall: Channel?

    public let method: SignificantBandwidthMethod

    /// Fails when the parts do not describe a possible measurement.
    public init?(channels: [Channel?], method: SignificantBandwidthMethod) {
        guard !channels.isEmpty else { return nil }
        self.channels = channels
        self.method = method
        overall = channels.compactMap { $0 }.max { $0.frequency < $1.frequency }
    }
}
