import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia

/// What producing a spectrogram actually yielded, once it is over.
///
/// Four outcomes, kept apart because they mean four different things to a user: a model, a file that
/// offered nothing to size an analysis against, something going wrong, and the user replacing the
/// operation. Collapsing any two would tell them something untrue — most of all cancellation, which
/// says nothing whatever about their file.
///
/// It has no "still working" case: this is the *result* of a generation, and a result that has not
/// happened yet is not a result. That distinction is the waveform's too, and is kept deliberately.
///
/// It lives here rather than in a feature module because nothing outside the composition root consumes
/// it yet; carrying it beside the report is group 6's job, and moving it then will have a reason.
enum SpectrogramOutcome: Sendable, Equatable {
    /// The file's spectral model. A model with no columns is a complete answer for a file with no
    /// audio, or for one shorter than a single analysis window — not an absence.
    case available(Spectrogram)
    /// The file exposed no usable frame count, so there was nothing to size an analysis against.
    /// Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path, no framework and no
    /// stable code (ADR-0011).
    case failed(message: String)
    /// The operation was cancelled — by the user replacing it, never by the file.
    case cancelled
}

/// One spectrogram generation: decode → accumulate → finish, and nothing else.
///
/// ## Why this is not a domain port
///
/// `docs/architecture.md` names a `SpectrogramGenerating` port, and task 2.7 declined to create it with
/// a written reversal criterion: introduce it *if* the real composition turns out to hold non-trivial
/// logic that does not belong in the composition root. This is that composition, and the criterion is
/// not met — what follows is "ask for chunks, hand them to the fold, take the result", plus the
/// bookkeeping the port's non-throwing callback forces. A port here would have exactly one implementer
/// and one consumer, and would add a translation layer over an error space that already exists.
///
/// ## Confined to one operation
///
/// The decoder is supplied by the caller and the accumulator is created **inside** `run` — a fresh one
/// per operation, never reused, never shared. The accumulator is not `Sendable` (it owns the transform
/// setup), which the compiler enforces, so it cannot escape this call even by accident.
///
/// ## It opens nothing
///
/// No `URL`, no security scope, no bookmark. The caller owns the access window and this runs inside it;
/// the decode finishes before `run` returns, so nothing outlives that window (ADR-0010).
struct SpectrogramGeneration {
    private let decoder: any AudioDecoding
    private let chunkFrames: Int

    init(decoder: any AudioDecoding, chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames) {
        self.decoder = decoder
        self.chunkFrames = chunkFrames
    }

    func run(for file: AudioFileReference) async -> SpectrogramOutcome {
        // Everything the callback needs to report back. It cannot throw — the port's callback returns a
        // disposition, not a result — so a fault it detects has to be *remembered* and answered for
        // after `decode` returns. Forgetting that check is the one way this composition could turn a
        // failure into a partial success, so it is written as a value that must be inspected.
        var accumulator: SpectrogramAccumulator?
        var fault: String?
        var cancelled = false

        do {
            let stream = try await decoder.decode(file, chunkFrames: chunkFrames) { stream, chunk in
                // Cancellation is observed at chunk boundaries. The adapter checks it too, but a fake
                // or a future implementation need not, and a cancelled operation must never finish a
                // model as though the user had waited for it.
                if Task.isCancelled {
                    cancelled = true
                    return .stop
                }

                // The accumulator is built from the first chunk's stream rather than in advance,
                // because that is the earliest moment the shape is known. The port guarantees the same
                // description on every call, so this happens exactly once.
                if accumulator == nil {
                    guard let made = SpectrogramAccumulator(
                        sampleRate: stream.sampleRate,
                        channelCount: stream.channelCount,
                        frameCount: stream.frameCount
                    ) else {
                        fault = "The file describes a stream no analysis can be built for."
                        return .stop
                    }
                    accumulator = made
                }

                // A chunk that does not match the stream it claims to come from would be folded into
                // the wrong channels, or past the end of the grid. The accumulator ignores such a chunk
                // silently — which is right for it and wrong here, because silence would leave a model
                // at the floor looking like a successful reading of a quiet file.
                guard chunk.channelCount == stream.channelCount, chunk.fits(stream) else {
                    fault = "The file produced audio that does not match the stream it declares."
                    return .stop
                }

                accumulator?.accumulate(chunk)
                return .continue
            }

            // **The remembered fault is answered for here, before anything else.** A `.stop` returned
            // by the callback ends the decode *normally*, so without this check a fault would arrive
            // as a description and be turned into a model of whatever had been read so far.
            if cancelled { return .cancelled }
            if let fault { return .failed(message: fault) }

            guard let stream else {
                // The file exposed no usable frame count. An absence caused by the file, never dressed
                // up as a failure.
                return .unavailable
            }

            // A file with no audio delivers no chunk, so no accumulator was ever built. Its model is an
            // empty one, which is a complete answer rather than a missing one.
            guard let accumulator else {
                guard let empty = SpectrogramAccumulator(
                    sampleRate: stream.sampleRate,
                    channelCount: stream.channelCount,
                    frameCount: stream.frameCount
                )?.finish() else {
                    return .failed(message: "The spectrogram for this file could not be produced.")
                }
                return .available(empty)
            }

            guard let spectrogram = accumulator.finish() else {
                return .failed(message: "The spectrogram for this file could not be produced.")
            }
            return .available(spectrogram)
        } catch {
            // Cancellation is the user replacing this operation, so it says nothing about the file and
            // must not be dressed up as a limitation of it.
            if error.code == .cancelled { return .cancelled }
            // Human, neutral, and carrying no path, no framework text and no stable code — those stay
            // where they are meaningful (ADR-0011).
            return .failed(message: "The spectrogram for this file could not be produced.")
        }
    }
}
