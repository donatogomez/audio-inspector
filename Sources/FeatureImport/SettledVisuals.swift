import AudioInspectorDomain

// Where the **visualisations'** lifecycle stops.
//
// `SettledMeasurements.swift` next door does the same job for the four measurements, and the two are
// deliberately not one file: they collapse to different shapes for opposite reasons. A measurement
// collapses to `Value?` because *"the JSON and the comparison describe measurements, not why one does
// not exist"* — a failure and an absence are both `nil` there. **A drawing may not do that.** The
// surface has to say *no drawing for this file* and *producing it did not succeed* in different words,
// so the two survive the collapse as separate cases here.
//
// What is shared is the rule: five states reach this feature and **none of them belongs in a settled
// value.** `loading` is a state of the flow and never a result; `cancelled` belongs to an operation the
// user already replaced and says nothing about the file. Both mean *not settled*, and both are spelled
// as a `nil` from the collapse rather than as a case anyone downstream has to handle.

/// What became of a file's amplitude envelope, once its inspection is over.
///
/// The three answers `WaveformOutcome` and `WaveformState` already draw, with the two that are not
/// answers removed: no `loading`, because a drawing still being produced is not a result, and no
/// `cancelled`, because a replaced operation is not a statement about the file.
///
/// **`unavailable` and `failed` stay apart.** *The file offered nothing to build an envelope from* and
/// *producing one did not succeed* are different facts, and a paired surface has to say which.
public enum SettledWaveform: Sendable, Equatable {
    /// The file's amplitude envelope. An envelope with no buckets is a complete answer for a file with
    /// no frames, not an absence.
    case available(WaveformEnvelope)
    /// The file offered nothing to build an envelope from. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)

    /// The settled answer a first file's state carries, or `nil` while it is still being produced.
    public init?(_ state: WaveformState) {
        switch state {
        case .loading: return nil
        case let .available(envelope): self = .available(envelope)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        }
    }

    /// The settled answer a compared file's outcome carries, or `nil` when it was cancelled.
    ///
    /// This is the same refusal `WaveformState.init?(_:)` already makes, for the same reason: rendering
    /// a cancelled operation as an absence would blame the file for the user's own action.
    public init?(_ outcome: WaveformOutcome) {
        switch outcome {
        case let .available(envelope): self = .available(envelope)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// What became of a file's spectral model, once its inspection is over.
///
/// The waveform's three answers, for the same three reasons, and kept a separate type for the same
/// reason `SpectrogramOutcome` is separate from `WaveformOutcome`: they carry different artefacts, and
/// unifying them would buy nothing but a generic parameter.
///
/// **A model with no columns is `available`.** A file shorter than one analysis window has real audio
/// and yields no complete window; that is a complete answer, and the surface already states it in its
/// own words. Collapsing it to `unavailable` here would destroy a distinction
/// `SpectrogramCopyTests` exists to protect.
public enum SettledSpectrogram: Sendable, Equatable {
    /// The file's spectral model. A model with no columns is a complete answer for a file with no
    /// audio, or one shorter than a single analysis window — not an absence.
    case available(Spectrogram)
    /// The file exposed no usable frame count. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)

    /// The settled answer a first file's state carries, or `nil` while it is still being produced.
    public init?(_ state: SpectrogramState) {
        switch state {
        case .loading: return nil
        case let .available(model): self = .available(model)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        }
    }

    /// The settled answer a compared file's outcome carries, or `nil` when it was cancelled.
    public init?(_ outcome: SpectrogramOutcome) {
        switch outcome {
        case let .available(model): self = .available(model)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// The pictures one inspection settled on, and the stream they were read from.
///
/// **A sibling of `ReportMeasurements`, never a field of it** (ADR-0025 §3). The container next door
/// already records why: *"`WaveformEnvelope` and `Spectrogram` are pictures of the samples, not
/// measurements of them, and neither has ever appeared under `measurements` on the wire."* Widening it
/// would put a drawing where the comparator, the export mapping and `SettledMeasurements` all agree
/// means numbers.
///
/// **Sibling, not neighbour: it lives here and not in the domain.** `ReportMeasurements` is a domain
/// type because the domain consumes it — `MeasurementComparison` takes two of them and the export DTO
/// maps from it. This has no domain consumer and never will: nothing compares two drawings, and nothing
/// serialises one. Its consumers are the flow and, later, the composition root.
///
/// ## Why the stream description travels with the pictures
///
/// Because one of them cannot state its own extent. `WaveformEnvelope` is deliberately poor — it
/// carries `frameCount` and `channelCount` and **no sample rate** — so an envelope alone cannot say how
/// long a file is, and two envelopes alone cannot share a time axis. `Spectrogram` carries `sampleRate`
/// and can. Taking both extents from **one** description the read already produced resolves that
/// asymmetry without adding a field to a domain type, and without a waveform lane and a spectrogram
/// lane ever disagreeing about how long the same file is.
///
/// It is **not** reconstructed from anything: it is the description `AudioDecoding` returned for that
/// read, or nothing.
///
/// It is not `Codable`, and there is no wire shape for it to have. A drawing never enters the
/// `schemaVersion` 1 export (ADR-0009), and conforming this would advertise a contract that does not
/// exist.
public struct FileVisuals: Sendable, Equatable {
    /// What became of the amplitude envelope.
    public let waveform: SettledWaveform
    /// What became of the spectral model.
    public let spectrogram: SettledSpectrogram
    /// The stream the artefacts above were read from, or `nil` when the read never had one.
    ///
    /// `nil` is not a defect: `AudioDecoding` reports no description exactly when the file exposed no
    /// usable frame count, and in that case there was nothing to size any analysis against, so every
    /// one of them is absent.
    public let stream: PCMStreamDescription?

    /// Fails on the one combination no read can produce: an artefact that exists, from a read that had
    /// no description.
    ///
    /// Failable rather than trusting the caller, for the reason `WaveformEnvelope` and `Spectrogram`
    /// are: a drawing whose axis cannot be stated is not a drawing anything can present, and making it
    /// unrepresentable is stronger than testing that it never happens.
    public init?(waveform: SettledWaveform, spectrogram: SettledSpectrogram, stream: PCMStreamDescription?) {
        if stream == nil {
            if case .available = waveform { return nil }
            if case .available = spectrogram { return nil }
        }
        self.waveform = waveform
        self.spectrogram = spectrogram
        self.stream = stream
    }
}

/// Two files' settled pictures, as **one value**.
///
/// The whole of its job is that there is no way to hold one side without the other. ADR-0024 §3 refused
/// the alternative for numbers, and the refusal is inherited unchanged: putting two sides on screen from
/// two places leaves them *"free to belong to two different operations"*. A consumer handed this cannot
/// assemble a mismatched pair, because it was never given the parts.
///
/// **It carries no outcome, and there is no field one could be written in.** Nothing here says the two
/// files are the same, different, similar, matching or comparable, and nothing ranks them. *First* and
/// *second* are **positions in the flow** — which report is on screen and which was chosen to compare
/// against it — never *original* and *copy*, never *source* and *derived* (ADR-0025 §1, §12).
///
/// It carries no operation number either. Which operation a pair belongs to is the flow's business and
/// is answered by where this value is stored, not by a token inside it; adding one now would be an
/// identifier kept in advance of a need.
public struct PairedVisuals: Sendable, Equatable {
    /// The pictures of the file whose report is on screen.
    public let first: FileVisuals
    /// The pictures of the file it is being compared against.
    public let second: FileVisuals

    public init(first: FileVisuals, second: FileVisuals) {
        self.first = first
        self.second = second
    }

    /// A pair, or nothing — the only two answers there are.
    ///
    /// **A side that has not settled is not a side with no pictures.** A first file may still be reading
    /// while the file it is compared against has finished, and publishing then would report its drawings
    /// as missing when they are a second away: a statement about this run dressed up as a fact about the
    /// file. That is the same reasoning `settledMeasurements` returns `nil` for *unfinished*, and it is
    /// why this initialiser takes optionals rather than leaving the check to each caller.
    public init?(first: FileVisuals?, second: FileVisuals?) {
        guard let first, let second else { return nil }
        self.init(first: first, second: second)
    }
}

extension InspectionPresentation {
    /// The pictures this file has **settled on**, or `nil` while either is still being produced.
    ///
    /// The stream description is passed in because neither this type nor `InspectionAnalyses` carries
    /// one: it belongs to the read, and the caller that owns the read is the one that has it. It is
    /// never derived from the report's declared properties — those are what the file's header claims,
    /// and the axes describe what was actually decoded.
    func settledVisuals(from stream: PCMStreamDescription?) -> FileVisuals? {
        guard let waveform = SettledWaveform(self.waveform),
              let spectrogram = SettledSpectrogram(self.spectrogram)
        else { return nil }
        return FileVisuals(waveform: waveform, spectrogram: spectrogram, stream: stream)
    }
}

extension InspectionAnalyses {
    /// The pictures a compared file settled on, or `nil` when its inspection was cancelled.
    ///
    /// **The four measurements are deliberately not here**, exactly as the two drawings are deliberately
    /// not in `settledMeasurements`. The two collapses read the same bundle and take different halves of
    /// it, and neither is derivable from the other.
    ///
    /// **It takes no stream description**, unlike the primary side's, and that is the point: the bundle
    /// carries the one it was produced from, so pairing an artefact with another read's description is
    /// unrepresentable here rather than merely unlikely.
    var settledVisuals: FileVisuals? {
        guard let waveform = SettledWaveform(self.waveform),
              let spectrogram = SettledSpectrogram(self.spectrogram)
        else { return nil }
        return FileVisuals(waveform: waveform, spectrogram: spectrogram, stream: stream)
    }
}
