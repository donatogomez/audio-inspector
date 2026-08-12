import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
import FeatureImport

/// One signal-level-metrics generation: decode → accumulate → finish, and nothing else.
///
/// ## No longer wired into an inspection — kept as the equivalence reference
///
/// `SourceInspectionCoordinator` now produces this analysis through `SharedPCMAnalysisGeneration`, which
/// reads the file once for several analyses (ADR-0020). This type is retained deliberately, not
/// forgotten: `SharedPCMAnalysisTests.equivalenceWithSeparateReads` runs it against the same input and
/// asserts the shared read produces **exactly** the same outcome, which is the evidence that sharing
/// changed the transport and not the analysis. Deleting it would remove that oracle, so it is a separate
/// decision rather than a side effect of this change.
///
/// Mirrors `SpectrogramGeneration` line for line — same composition, same reasons (task 4.1 of
/// `add-computed-technical-properties` names this mechanical composition explicitly). It is not a
/// domain port for the same reason `SpectrogramGeneration` is not one: the composition holds no logic
/// beyond "ask for chunks, hand them to the fold, take the result," and a port here would have exactly
/// one implementer and one consumer.
///
/// ## Confined to one operation
///
/// The decoder is supplied by the caller and the accumulator is created **inside** `run` — a fresh one
/// per operation, never reused, never shared. The accumulator is not `Sendable` (it owns unsynchronised
/// per-channel state), which the compiler enforces, so it cannot escape this call even by accident.
///
/// ## It opens nothing
///
/// No `URL`, no security scope, no bookmark. The caller owns the access window and this runs inside it;
/// the decode finishes before `run` returns, so nothing outlives that window (ADR-0010).
///
/// ## Independent of the waveform and the spectrogram
///
/// This is a **third** independent operation over the shared `AudioDecoding` port, with its own decoder
/// instance and its own cancellation — never sharing an accumulator, a decoder, or a result with either
/// sibling (ADR-0016 decision 15, design.md §10). It does not hook into the waveform's own,
/// deliberately-unmigrated generator.
struct SignalLevelMetricsGeneration {
    private let decoder: any AudioDecoding
    private let chunkFrames: Int

    init(decoder: any AudioDecoding, chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames) {
        self.decoder = decoder
        self.chunkFrames = chunkFrames
    }

    func run(for file: AudioFileReference) async -> SignalLevelMetricsOutcome {
        // Everything the callback needs to report back. It cannot throw — the port's callback returns a
        // disposition, not a result — so a fault it detects has to be *remembered* and answered for
        // after `decode` returns. Forgetting that check is the one way this composition could turn a
        // failure into a partial success, so it is written as a value that must be inspected.
        var accumulator: SignalLevelMetricsAccumulator?
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
                    guard let made = SignalLevelMetricsAccumulator(channelCount: stream.channelCount) else {
                        fault = "The file describes a stream no analysis can be built for."
                        return .stop
                    }
                    accumulator = made
                }

                // A chunk that does not match the stream it claims to come from, or that runs past the
                // stream's own declared length, would be folded into the wrong channel or counted past
                // what the file actually contains. The accumulator ignores a wrong channel count
                // silently — which is right for it and wrong here, because silence would leave a model
                // that looks like a successful reading of the whole file.
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

            // A file with no audio delivers no chunk, so no accumulator was ever built. Its metrics are
            // a complete, empty answer — every channel reports "not computable" — rather than a missing
            // one.
            guard let accumulator else {
                guard let empty = SignalLevelMetricsAccumulator(channelCount: stream.channelCount),
                      let model = empty.finish() else {
                    return .failed(message: "The signal level metrics for this file could not be produced.")
                }
                return .available(model)
            }

            guard let model = accumulator.finish() else {
                return .failed(message: "The signal level metrics for this file could not be produced.")
            }
            return .available(model)
        } catch {
            // Cancellation is the user replacing this operation, so it says nothing about the file and
            // must not be dressed up as a limitation of it.
            if error.code == .cancelled { return .cancelled }
            // Human, neutral, and carrying no path, no framework text and no stable code — those stay
            // where they are meaningful (ADR-0011).
            return .failed(message: "The signal level metrics for this file could not be produced.")
        }
    }
}
