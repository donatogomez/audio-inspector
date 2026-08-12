import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
import FeatureImport

/// The results of one shared read: one outcome per analysis, exactly the outcomes each analysis had
/// when it read the file on its own.
///
/// It is **not** a domain aggregate and never becomes one. It carries no value of its own — no combined
/// status, no shared error, no "the analyses succeeded" — because nothing downstream should be able to
/// ask a question about the analyses *together*. The coordinator destructures it immediately and emits
/// the same two updates it always emitted, so presentation, flow state and export never learn that the
/// read is shared.
struct SharedPCMAnalysisOutcome {
    let spectrogram: SpectrogramOutcome
    let signalLevelMetrics: SignalLevelMetricsOutcome
}

/// Reads a file's PCM **once** and folds every chunk into several analyses, each of which keeps its own
/// accumulation, its own failure and its own outcome.
///
/// ## Why one read, when ADR-0016 chose one per analysis
///
/// ADR-0016 decision 15 required independent operations and rejected a shared pass — *and wrote the
/// condition for revisiting it*: "possible **on top of** this seam if measurement ever justifies one."
/// The measurement arrived (`docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md`): one more read
/// of a compressed file costs about a quarter of an inspection, and the redundancy grows with every
/// metric added. **ADR-0020** records what that changed and what it did not: *independent analyses* is
/// the invariant; *independent decodes* was the implementation chosen while a decode looked free.
///
/// ## What "independent" means here, since it is no longer a separate decoder
///
/// - **A consumer's failure is its own.** It stops receiving chunks, the read continues, and every
///   other consumer settles exactly as it would have on its own. Nothing about one consumer's state is
///   readable by another — they share a loop, not a result.
/// - **The read ends when nobody needs it**, never when *someone* is done: `.stop` is returned only
///   once every consumer has failed, or on cancellation. Today both consumers need every sample, so
///   that condition is not reachable through normal completion — it is written so the contract does not
///   quietly depend on that staying true.
/// - **A decoder failure is not a consumer failure.** No more PCM will exist, so every unfinished
///   consumer ends — but each reports its own outcome, so a caller reading one never has to consult
///   another to learn what happened.
///
/// ## It is a composition, not a port and not a protocol
///
/// The same reasoning `SpectrogramGeneration` already records: what follows is "ask for chunks, hand
/// them to the folds, take the results", so a port would have one implementer and one consumer. And the
/// consumers are held **concretely** rather than behind a `PCMConsumer` abstraction: their `finish()`
/// results are unrelated types with unrelated optionality rules, so a protocol would need an associated
/// type and would buy generic machinery for two known consumers (`design.md` §7). A third consumer adds
/// a field and a call, not an abstraction.
///
/// ## It opens nothing
///
/// No `URL`, no security scope, no bookmark. The caller owns the access window and this runs inside it;
/// the decode finishes before `run` returns, so no chunk and no accumulator outlives that window
/// (ADR-0010). The callback stays synchronous for the same reason, which is also why no consumer runs
/// concurrently: the measured ceiling for that was ~0.28 s against three deliberately non-`Sendable`
/// accumulators (`design.md` §4).
struct SharedPCMAnalysisGeneration {
    private let decoder: any AudioDecoding
    private let chunkFrames: Int

    init(decoder: any AudioDecoding, chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames) {
        self.decoder = decoder
        self.chunkFrames = chunkFrames
    }

    func run(for file: AudioFileReference) async -> SharedPCMAnalysisOutcome {
        // One `Consumers` value holds every analysis's accumulator and its own recorded fault. It is a
        // plain `var` on this call's stack: nothing here is `Sendable`, nothing escapes, and the
        // compiler enforces both.
        var consumers = Consumers()
        var cancelled = false

        do {
            let stream = try await decoder.decode(file, chunkFrames: chunkFrames) { stream, chunk in
                // Cancellation is observed at chunk boundaries. The adapter checks it too, but a fake
                // or a future implementation need not, and a cancelled read must never leave a model
                // finished as though the user had waited for it.
                if Task.isCancelled {
                    cancelled = true
                    return .stop
                }

                // Built from the first chunk's stream rather than in advance, because that is the
                // earliest moment the shape is known — and from **one** description, so two consumers
                // can never disagree about the file they are reading. The port guarantees the same
                // description on every call, so this happens exactly once.
                consumers.prepare(for: stream)

                // A chunk that does not match the stream it claims to come from would be folded into
                // the wrong channels, or past the end of a grid. Each accumulator ignores such a chunk
                // silently — which is right for it and wrong here, because silence would leave a model
                // that looks like a successful reading of the whole file. It faults **every** consumer,
                // because the fault is in the audio they all just received, not in any one of them.
                guard chunk.channelCount == stream.channelCount, chunk.fits(stream) else {
                    consumers.failAll(with: "The file produced audio that does not match the stream it declares.")
                    return .stop
                }

                // **The same value, handed to each in turn.** `PCMChunk` is an immutable struct over
                // copy-on-write arrays, so this copies a few words per consumer and never a sample.
                consumers.accumulate(chunk)

                // Only when nobody is left to feed. A consumer that failed does not end the read for
                // the others — that is the whole point of this type.
                return consumers.allFailed ? .stop : .continue
            }

            // **The remembered faults are answered for here, before anything else.** A `.stop` returned
            // by the callback ends the decode *normally*, so without this each fault would arrive as a
            // description and be turned into a model of whatever had been read so far.
            if cancelled {
                return SharedPCMAnalysisOutcome(spectrogram: .cancelled, signalLevelMetrics: .cancelled)
            }
            guard let stream else {
                // The file exposed no usable frame count, so there was nothing to size an analysis
                // against. An absence caused by the file, never dressed up as a failure — and it is
                // every consumer's absence, because none of them got a stream.
                return SharedPCMAnalysisOutcome(spectrogram: .unavailable, signalLevelMetrics: .unavailable)
            }
            return consumers.finish(stream: stream)
        } catch {
            // A **producer** failure: no more PCM will exist for anyone. Every consumer ends, and each
            // reports its own outcome rather than a shared one — a caller reading one result must not
            // have to consult another to learn what happened.
            if error.code == .cancelled {
                return SharedPCMAnalysisOutcome(spectrogram: .cancelled, signalLevelMetrics: .cancelled)
            }
            // Human, neutral, and carrying no path, no framework text and no stable code — those stay
            // where they are meaningful (ADR-0011). Each analysis keeps the wording it had when it read
            // the file alone, so nothing downstream can tell the difference.
            return SharedPCMAnalysisOutcome(
                spectrogram: .failed(message: "The spectrogram for this file could not be produced."),
                signalLevelMetrics: .failed(message: "The signal level metrics for this file could not be produced.")
            )
        }
    }
}

// MARK: - The consumers, held concretely

private extension SharedPCMAnalysisGeneration {
    /// Every analysis fed by the shared read: its accumulator, and the fault that took it out of the
    /// read if one did.
    ///
    /// A `nil` accumulator before `prepare(for:)` means "not built yet"; a non-`nil` fault means "out",
    /// and the two are never both meaningful — a consumer that faulted stops being fed and its
    /// accumulator is never read again. Adding a third analysis is a stored property, one line in each
    /// method, and one more field in the outcome.
    struct Consumers {
        private var spectrogram: SpectrogramAccumulator?
        private var signalLevelMetrics: SignalLevelMetricsAccumulator?
        private var spectrogramFault: String?
        private var signalLevelMetricsFault: String?
        private var prepared = false

        /// Whether no consumer can still use a chunk. The read ends only on this, never on one
        /// consumer being done.
        var allFailed: Bool { spectrogramFault != nil && signalLevelMetricsFault != nil }

        /// Builds each accumulator once, from the one stream description the read reports.
        ///
        /// A consumer whose accumulator cannot be built for this stream faults **alone**: the others
        /// are built and fed exactly as they would have been.
        mutating func prepare(for stream: PCMStreamDescription) {
            guard !prepared else { return }
            prepared = true
            spectrogram = SpectrogramAccumulator(
                sampleRate: stream.sampleRate,
                channelCount: stream.channelCount,
                frameCount: stream.frameCount
            )
            if spectrogram == nil {
                spectrogramFault = "The file describes a stream no analysis can be built for."
            }
            signalLevelMetrics = SignalLevelMetricsAccumulator(channelCount: stream.channelCount)
            if signalLevelMetrics == nil {
                signalLevelMetricsFault = "The file describes a stream no analysis can be built for."
            }
        }

        /// Hands the same chunk to every consumer still in the read.
        mutating func accumulate(_ chunk: PCMChunk) {
            if spectrogramFault == nil { spectrogram?.accumulate(chunk) }
            if signalLevelMetricsFault == nil { signalLevelMetrics?.accumulate(chunk) }
        }

        /// Faults every consumer at once. Used only when the fault is in the audio itself, which none
        /// of them can proceed past — never to propagate one consumer's own failure to another.
        mutating func failAll(with message: String) {
            if spectrogramFault == nil { spectrogramFault = message }
            if signalLevelMetricsFault == nil { signalLevelMetricsFault = message }
        }

        /// Each consumer's own result, computed independently of the others.
        ///
        /// A file with no audio delivers no chunk, so nothing was ever prepared: each consumer's empty
        /// model is built here from the stream and reported as **available**, because an empty answer is
        /// a complete one rather than a missing one — the rule each analysis already followed alone.
        func finish(stream: PCMStreamDescription) -> SharedPCMAnalysisOutcome {
            SharedPCMAnalysisOutcome(
                spectrogram: finishSpectrogram(stream: stream),
                signalLevelMetrics: finishSignalLevelMetrics(stream: stream)
            )
        }

        private func finishSpectrogram(stream: PCMStreamDescription) -> SpectrogramOutcome {
            if let spectrogramFault { return .failed(message: spectrogramFault) }
            let accumulator = spectrogram ?? SpectrogramAccumulator(
                sampleRate: stream.sampleRate,
                channelCount: stream.channelCount,
                frameCount: stream.frameCount
            )
            guard let model = accumulator?.finish() else {
                return .failed(message: "The spectrogram for this file could not be produced.")
            }
            return .available(model)
        }

        private func finishSignalLevelMetrics(stream: PCMStreamDescription) -> SignalLevelMetricsOutcome {
            if let signalLevelMetricsFault { return .failed(message: signalLevelMetricsFault) }
            let accumulator = signalLevelMetrics ?? SignalLevelMetricsAccumulator(
                channelCount: stream.channelCount
            )
            guard let model = accumulator?.finish() else {
                return .failed(message: "The signal level metrics for this file could not be produced.")
            }
            return .available(model)
        }
    }
}
