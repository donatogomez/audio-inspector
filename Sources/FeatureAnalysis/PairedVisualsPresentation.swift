import AudioInspectorDomain

/// What became of one file's envelope, as a **paired** lane can hold it.
///
/// Three cases, and deliberately not four: a lane belongs to a pair, a pair exists only once both files
/// have settled, and *still being produced* is therefore not a state it can be in. Widening
/// `WaveformPresentation` would have let one in, so this is its own type — the same reason
/// `WaveformOutcome`, `WaveformState` and the flow's settled shape are three types and not one.
public enum PairedWaveformLane: Equatable {
    /// The envelope to draw. One with no buckets is a complete answer for a file with no frames.
    case envelope(WaveformEnvelope)
    /// The file offered nothing to build one from. Never presented as a defect of the audio.
    case absent
    /// Producing one did not succeed. The message arrives already human.
    case failed(message: String)

    /// The lane's three answers as the single-file section's four, so the drawing and its words are the
    /// ones a reader already knows.
    ///
    /// **Total, and `loading` is never produced**: a lane belongs to a pair, and a pair exists only once
    /// both files have settled.
    public var asSingle: WaveformPresentation {
        switch self {
        case let .envelope(envelope): .envelope(envelope)
        case .absent: .absent
        case let .failed(message): .failed(message: message)
        }
    }
}

/// What became of one file's spectral model, as a paired lane can hold it. The waveform's three cases,
/// for the same three reasons.
///
/// **A model with no columns is `model`, not `absent`** — a file shorter than one analysis window has
/// real audio and a complete answer, and the distinction survives this layer as it survives every other.
public enum PairedSpectrogramLane: Equatable {
    case model(Spectrogram)
    case absent
    case failed(message: String)
}

/// Two files' envelopes, and the one time axis they are laid out against.
///
/// The axis is optional for one reason only: neither file reported a stream, or both reported one
/// carrying no audio, so there is no extent to lay anything out against. That is **not** a reason to
/// fall back to a single drawing — the pair still exists, and each lane still states what became of its
/// own file.
public struct PairedWaveformPresentation: Equatable {
    public let axis: PairedWaveformAxis?
    public let first: PairedWaveformLane
    public let second: PairedWaveformLane

    public init(axis: PairedWaveformAxis?, first: PairedWaveformLane, second: PairedWaveformLane) {
        self.axis = axis
        self.first = first
        self.second = second
    }
}

/// Two files' spectral models, and the time and frequency axes they are laid out against.
public struct PairedSpectrogramPresentation: Equatable {
    public let axes: PairedSpectrogramAxes?
    public let first: PairedSpectrogramLane
    public let second: PairedSpectrogramLane

    public init(axes: PairedSpectrogramAxes?, first: PairedSpectrogramLane, second: PairedSpectrogramLane) {
        self.axes = axes
        self.first = first
        self.second = second
    }
}

/// Both paired drawings, as one value.
///
/// They travel together because they are one answer about one pair of files, published in one
/// assignment by the flow. Splitting them here would reintroduce, at the surface, exactly the mixing the
/// flow's single payload exists to prevent.
///
/// **It carries no outcome.** Nothing here says the two files are the same, different, similar or
/// matching, and there is no field one could be written in.
public struct PairedVisualsPresentation: Equatable {
    public let waveform: PairedWaveformPresentation
    public let spectrogram: PairedSpectrogramPresentation

    public init(waveform: PairedWaveformPresentation, spectrogram: PairedSpectrogramPresentation) {
        self.waveform = waveform
        self.spectrogram = spectrogram
    }
}

/// One visual section the report surface presents.
///
/// A case per drawing that is actually shown, so *how many* drawings are on screen is a value a test can
/// read rather than a property of a rendering nobody can assert.
public enum ReportVisualSection: Equatable {
    case singleWaveform(WaveformPresentation)
    case singleSpectrogram(SpectrogramPresentation)
    case pairedWaveform(PairedWaveformPresentation)
    case pairedSpectrogram(PairedSpectrogramPresentation)
}

/// Which drawings the report surface is presenting: one file's own, or two files' side by side.
///
/// **The choice is made once, for both drawings together.** A surface showing a paired waveform beside a
/// single spectrogram would be answering one question two ways, and this type makes that unrepresentable
/// rather than merely avoided: both sections read the same value, so they cannot disagree.
///
/// **Paired stands in for single; it is never added to it.** While a pair is on screen the first file
/// appears exactly once, inside the pair — showing it twice, at two different geometries, would put two
/// answers to one question in front of the reader (ADR-0025 §8, design §8).
public enum ReportVisuals: Equatable {
    /// One file's own drawings, exactly as they are presented without this capability.
    case single(waveform: WaveformPresentation, spectrogram: SpectrogramPresentation)
    /// Two files' drawings, on shared axes.
    case paired(PairedVisualsPresentation)

    /// The waveform sections to present — **exactly one**, always.
    ///
    /// A collection rather than a single value so that *how many* is something a test can assert. The
    /// property 6.3 asks for — the first file's envelope appears once — is not observable at all if the
    /// answer is a value that cannot be counted.
    public var waveformSections: [ReportVisualSection] {
        switch self {
        case let .single(waveform, _): [.singleWaveform(waveform)]
        case let .paired(paired): [.pairedWaveform(paired.waveform)]
        }
    }

    /// The spectral sections to present — exactly one, always, and chosen by the same value the
    /// waveform's was.
    public var spectrogramSections: [ReportVisualSection] {
        switch self {
        case let .single(_, spectrogram): [.singleSpectrogram(spectrogram)]
        case let .paired(paired): [.pairedSpectrogram(paired.spectrogram)]
        }
    }
}
