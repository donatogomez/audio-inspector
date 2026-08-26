import AudioInspectorDomain
import CoreGraphics

/// Two spectral models on one time axis and one frequency axis, as arithmetic.
///
/// Nothing here renders, and nothing here touches a `Spectrogram`. It answers three questions a
/// renderer laying out two grids has to ask, and answers them from the two files' own reads:
/// how much of the width each file's audio spans, how much of the height its own Nyquist reaches, and
/// what is left above it.
///
/// ## The defect it exists to prevent
///
/// `SpectrogramGeometry` maps band *i* of *n* across the **whole** height it is given, and its frequency
/// axis runs to the file's own Nyquist. Two equal lanes therefore put 22.05 kHz and 48 kHz at the same
/// top edge — the picture says the two files cover the same spectrum, and the labels quietly disagree
/// with it. Cropping both to the lower Nyquist would hide the higher file's upper range, which is
/// exactly what `SpectrogramAxes` refuses to do for one file: *"A 96 kHz file that holds nothing above
/// 22 kHz is showing exactly the thing a collector is looking for."*
///
/// So the shared axis reaches the **higher** Nyquist, each grid occupies its own share of it from 0 Hz
/// up, and the rest of that lane is **not part of the drawing at all** (ADR-0025 §9).
///
/// ## Two absences, kept apart
///
/// - **Above a file's own Nyquist** — the file *cannot represent* that range. No cell exists there, and
///   the region is given a treatment that is not a level on the ramp.
/// - **At the ramp's floor, inside the grid** — the file *was measured* there and is very quiet.
///
/// They are different facts and must not look the same, which is why `outOfRangeTreatment` is
/// deliberately **achromatic**: no colour the ramp produces ever is.
///
/// ## Time is not recomputed here
///
/// It is `PairedWaveformAxis`'s, unchanged and composed rather than copied, so a waveform lane and a
/// spectrogram lane for the same file **cannot** disagree about how long it is (task 5.1). The name
/// belongs to the drawing it was written for; its content is purely temporal.
struct PairedSpectrogramAxes: Equatable {

    /// Which of the two files a lane belongs to. Position, and nothing more.
    typealias Side = PairedWaveformAxis.Side

    /// One file's share of the two shared axes.
    struct Lane: Equatable {
        /// The highest frequency this file can represent, from the stream its samples were read from.
        let nyquist: Double
        /// Its share of the shared frequency axis: `nyquist / sharedNyquist`, in `0...1`. The
        /// higher-rate file's is exactly `1`.
        let frequencyFraction: Double
        /// What this file's own audio lasts.
        let seconds: Double
        /// Its share of the shared time axis, from `PairedWaveformAxis` and computed nowhere else.
        let timeFraction: Double

        /// The share of the frequency axis above this file's own Nyquist.
        ///
        /// It means *this file cannot represent this range*. It is not quiet, it was not measured, and
        /// no cell exists in it.
        var outOfRangeFraction: Double { 1 - frequencyFraction }
    }

    /// The frequency extent both lanes are measured against: the higher of the two Nyquists.
    let sharedNyquist: Double
    /// The time extent both lanes are measured against, from `PairedWaveformAxis`.
    let sharedSeconds: Double
    let first: Lane?
    let second: Lane?

    /// Fails when there is no pair of axes to build.
    ///
    /// It delegates the time axis to `PairedWaveformAxis` and fails wherever that does — neither file
    /// reported a stream, or both reported one carrying no audio. That is not a shortcut: a file with no
    /// audio yields a model with no columns, so there is nothing to lay out in either direction, and
    /// requiring the time axis is what makes task 5.1 true **by construction** rather than by agreement.
    ///
    /// A rate is never zero or negative here, because `PCMStreamDescription` refuses one at
    /// construction — so a Nyquist is always positive and the frequency division is always valid.
    init?(first: PCMStreamDescription?, second: PCMStreamDescription?) {
        guard let time = PairedWaveformAxis(first: first, second: second) else { return nil }
        let firstNyquist = first.map(Self.nyquist)
        let secondNyquist = second.map(Self.nyquist)
        guard let shared = [firstNyquist, secondNyquist].compactMap({ $0 }).max(), shared > 0 else {
            return nil
        }
        sharedNyquist = shared
        sharedSeconds = time.sharedSeconds
        self.first = Self.lane(nyquist: firstNyquist, time: time.first, sharedNyquist: shared)
        self.second = Self.lane(nyquist: secondNyquist, time: time.second, sharedNyquist: shared)
    }

    /// The highest frequency a stream can represent.
    ///
    /// **From the stream description, and from nothing else.** `Spectrogram` carries the same rate — it
    /// is built from this very description — and consulting it instead would tie the *axis* to a
    /// *drawing*: a file whose spectral model is absent or failed still has a Nyquist, and the shared
    /// axis the other file is drawn against must survive that (ADR-0025 §6). One source for both axes
    /// also makes mixing them unrepresentable rather than merely unlikely.
    ///
    /// Never derived from `bandCount`, which is the grid's resolution and says nothing about frequency.
    private static func nyquist(_ stream: PCMStreamDescription) -> Double {
        stream.sampleRate / 2
    }

    private static func lane(
        nyquist: Double?, time: PairedWaveformAxis.Lane?, sharedNyquist: Double
    ) -> Lane? {
        guard let nyquist, let time else { return nil }
        return Lane(
            nyquist: nyquist,
            frequencyFraction: nyquist / sharedNyquist,
            seconds: time.seconds,
            timeFraction: time.fraction
        )
    }

    func lane(_ side: Side) -> Lane? {
        switch side {
        case .first: first
        case .second: second
        }
    }

    /// The area one file's grid is drawn into, inside an area holding both.
    ///
    /// **0 Hz is at the bottom**, the convention `SpectrogramGeometry.verticalBand` already imposes, so
    /// a file that reaches less far up occupies the **lower** part of the lane and leaves the top empty.
    /// Handing this rect's size to `SpectrogramGeometry` is what makes its band→Y arithmetic land inside
    /// the file's own range, unchanged.
    func occupiedRect(_ side: Side, in size: CGSize) -> CGRect? {
        guard let lane = lane(side) else { return nil }
        let height = size.height * CGFloat(lane.frequencyFraction)
        return CGRect(
            x: 0,
            y: size.height - height,
            width: size.width * CGFloat(lane.timeFraction),
            height: height
        )
    }

    /// The area above this file's own Nyquist: the range it cannot represent.
    ///
    /// It spans the file's **own** time, not the shared width, because past its last frame there is a
    /// different absence — *no audio at all* — and Group 4's time remainder already names that one.
    /// Collapsing the two would state one fact where there are two.
    func outOfRangeRect(_ side: Side, in size: CGSize) -> CGRect? {
        guard let lane = lane(side) else { return nil }
        return CGRect(
            x: 0,
            y: 0,
            width: size.width * CGFloat(lane.timeFraction),
            height: size.height * CGFloat(lane.outOfRangeFraction)
        )
    }

    /// The energy scale a lane is drawn against.
    ///
    /// **The same for both, and the same as a single model's.** It is a property of the scale, not of a
    /// file: re-ranging one lane to its own loudest cell would make a quiet file look like a loud one,
    /// which is the comparison a pair of drawings exists to make possible (ADR-0025 §7). The parameter
    /// exists so the rule is asked and answered per lane rather than assumed.
    func energyRange(for side: Side) -> ClosedRange<Float> {
        _ = side
        return SpectrogramColourRamp.range
    }

    /// The floor a lane's values are read against. One value, shared, and the domain's own.
    func floorDecibels(for side: Side) -> Float {
        _ = side
        return Spectrogram.floorDecibels
    }

    /// How the region above a file's Nyquist is drawn — and it is **not a level**.
    ///
    /// Deliberately **achromatic**, which no colour on the ramp ever is: every stop and every
    /// interpolation between them separates red from blue, so an equal-component treatment cannot be
    /// mistaken for any energy the ramp can show, least of all the near-black it draws at the floor.
    /// *This file cannot represent this range* and *this file was measured here and is very quiet* are
    /// different facts, and this is what keeps them from looking the same.
    ///
    /// `SpectrogramColourRamp` is read here and never modified.
    static let outOfRangeTreatment: (red: Double, green: Double, blue: Double) = (0.32, 0.32, 0.32)
}
