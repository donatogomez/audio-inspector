import AudioInspectorDomain
import CoreGraphics

/// One time axis for two files' envelopes, and the share of it each of them occupies.
///
/// Deliberately outside the view, for the reason `WaveformGeometry` already gives: every property worth
/// guaranteeing here is arithmetic that needs no rendering at all. Nothing in this file draws, and
/// nothing in it touches an envelope.
///
/// ## The defect it exists to prevent
///
/// `WaveformGeometry.horizontalBand(forBucket:)` places bucket *i* of *n* at `width · i/n` — so an
/// envelope handed a lane **fills it**, whatever its duration. Two equal lanes therefore assert, with no
/// words at all, that the two files are the same length. For a 3:00 file beside a 3:30 one that is
/// false, and it is false silently.
///
/// The fix is not to change that arithmetic: it is to hand it a **fraction** of the width. So each side
/// is drawn by exactly the code that draws one file alone, across the part of the axis its own audio
/// actually spans, and stops there (ADR-0025 §8).
///
/// ## What it does not do
///
/// It produces no bucket, changes no amplitude, and creates no second envelope. A file whose audio ends
/// before the shared extent has a **remainder**, and a remainder is not silence: `WaveformBucket.silent`
/// is a *measured* zero, and past a file's last frame nothing was measured. Nothing here can be mistaken
/// for one, because nothing here carries a sample at all.
struct PairedWaveformAxis: Equatable {

    /// Which of the two files a lane belongs to. Position in the comparison, and nothing more — never
    /// *original* and *copy*, never *source* and *derived*.
    enum Side: Equatable {
        case first
        case second
    }

    /// One file's share of the shared axis.
    struct Lane: Equatable {
        /// What this file's own audio lasts, from the stream its samples were read from.
        let seconds: Double
        /// The share of the shared extent it occupies: `seconds / sharedSeconds`, in `0...1`. The
        /// longer file's is exactly `1`.
        let fraction: Double

        /// The share of the axis this file's audio does **not** reach.
        ///
        /// It means *there is no audio here*, and it is not a quiet passage. Nothing is drawn in it —
        /// no bar, no baseline, no substituted bucket — and this value exists so the surface can say so
        /// rather than leave an unexplained gap.
        var remainderFraction: Double { 1 - fraction }
    }

    /// The extent both lanes are measured against: the longer of the two files' own extents.
    let sharedSeconds: Double
    /// The first file's lane, or `nil` when its read reported no stream at all.
    let first: Lane?
    /// The second file's lane, or `nil` for the same reason.
    let second: Lane?

    /// Fails when there is no axis to build.
    ///
    /// Two cases, and both are ordinary rather than errors: neither file reported a stream, or both
    /// reported one carrying no audio. A shared extent of zero is not an axis two drawings can be laid
    /// out against, and dividing by it would produce a fraction that is not a number — so it is refused
    /// here rather than propagated as one.
    ///
    /// **A side whose read reported no stream gets `nil`, never a lane of zero seconds.** *No extent was
    /// measured* and *this file lasts no time at all* are different statements, and a file that opened
    /// and holds no audio genuinely is the second one.
    init?(first: PCMStreamDescription?, second: PCMStreamDescription?) {
        let firstSeconds = first.map(Self.seconds)
        let secondSeconds = second.map(Self.seconds)
        guard let shared = [firstSeconds, secondSeconds].compactMap({ $0 }).max(), shared > 0 else {
            return nil
        }
        sharedSeconds = shared
        self.first = firstSeconds.map { Lane(seconds: $0, fraction: $0 / shared) }
        self.second = secondSeconds.map { Lane(seconds: $0, fraction: $0 / shared) }
    }

    /// How long the audio a read produced lasts.
    ///
    /// **Frames over the rate that read them, and never frames alone.** Two files of the same duration
    /// at 44.1 and 48 kHz hold different frame counts, so comparing frames would report a difference in
    /// time where there is none. The description is the one the decoder reported for that file's own
    /// read; nothing here consults the report's declared properties, which are what the header claims
    /// rather than what was decoded.
    private static func seconds(_ stream: PCMStreamDescription) -> Double {
        Double(stream.frameCount) / stream.sampleRate
    }

    func lane(_ side: Side) -> Lane? {
        switch side {
        case .first: first
        case .second: second
        }
    }

    /// The area one file's envelope is drawn into, inside an area holding both.
    ///
    /// The height is the whole of it — the axis is shared in **time**, not in amplitude — and the width
    /// is that file's own share. Handing this to `WaveformGeometry` is what makes a short file stop
    /// where its audio stops, using the same bucket arithmetic that draws a single file, unchanged.
    func laneSize(_ side: Side, in size: CGSize) -> CGSize? {
        guard let lane = lane(side) else { return nil }
        return CGSize(width: size.width * CGFloat(lane.fraction), height: size.height)
    }

    /// The amplitude scale a lane is drawn against.
    ///
    /// **The same for both, and the same as a single envelope's**, because it is a property of the scale
    /// rather than of either file. Scaling a lane to its own peak would make a quiet file look like a
    /// loud one and destroy the only comparison a pair of drawings can honestly support (ADR-0025 §7).
    /// The parameter exists so that rule is asked and answered per lane rather than assumed.
    func amplitudeRange(for side: Side) -> ClosedRange<Float> {
        _ = side
        return WaveformGeometry.drawnRange
    }
}
