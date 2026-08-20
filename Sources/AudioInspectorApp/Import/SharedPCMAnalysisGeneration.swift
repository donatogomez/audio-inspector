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
/// the same three updates it would have emitted from three separate reads, so presentation, flow state
/// and export never learn that the read is shared.
///
/// **A third analysis was added by adding a field**, which is the property the design claimed for this
/// shape and is now demonstrated rather than asserted: no protocol, no generic machinery, no widening
/// of an existing analysis. **A fourth cost the same**, and it is the one that reduces an inspection to
/// a single read of the file. **The fifth cost the same again** — and it is the first whose accumulator
/// declines to be built for some perfectly valid streams, which the shape absorbed as an absence rather
/// than a fault, exactly as the waveform's own already does.
struct SharedPCMAnalysisOutcome {
    /// **Not yet what the user sees.** The waveform still has its own read in
    /// `SourceInspectionCoordinator`, and that one is what reaches the surface; this is the same
    /// envelope produced from the shared chunks, kept beside it so the two can be compared on real
    /// files before the old path is retired (`share-waveform-pcm-read`, groups 2 and 3). Retiring it is
    /// a separate change precisely so the equivalence is provable while both exist.
    let waveform: WaveformOutcome
    let spectrogram: SpectrogramOutcome
    let signalLevelMetrics: SignalLevelMetricsOutcome
    let truePeak: TruePeakOutcome
    let loudness: LoudnessOutcome
    let significantBandwidth: SignificantBandwidthOutcome
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
///   once every consumer has failed, or on cancellation. Today all three consumers need every sample, so
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
/// type and would buy generic machinery for known consumers (`add-shared-pcm-read` design §7). That
/// design said a third consumer would cost a field and a call rather than an abstraction; true peak is
/// that third consumer, and it cost exactly that.
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
    /// The waveform's resolution, taken from the same place the legacy generator takes it so the two
    /// produce the same envelope. Exposed only so a test can vary it exactly as
    /// `AVFoundationWaveformGenerator` already allows; production passes neither.
    private let maximumBucketCount: Int

    init(
        decoder: any AudioDecoding,
        chunkFrames: Int = AVFoundationAudioDecoder.defaultChunkFrames,
        maximumBucketCount: Int = WaveformBucketMapping.defaultMaximumBucketCount
    ) {
        self.decoder = decoder
        self.chunkFrames = chunkFrames
        self.maximumBucketCount = maximumBucketCount
    }

    func run(for file: AudioFileReference) async -> SharedPCMAnalysisOutcome {
        // One `Consumers` value holds every analysis's accumulator and its own recorded fault. It is a
        // plain `var` on this call's stack: nothing here is `Sendable`, nothing escapes, and the
        // compiler enforces both.
        var consumers = Consumers(maximumBucketCount: maximumBucketCount)
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
                return SharedPCMAnalysisOutcome(
                    waveform: .cancelled, spectrogram: .cancelled,
                    signalLevelMetrics: .cancelled, truePeak: .cancelled, loudness: .cancelled,
                    significantBandwidth: .cancelled
                )
            }
            guard let stream else {
                // The file exposed no usable frame count, so there was nothing to size an analysis
                // against. An absence caused by the file, never dressed up as a failure — and it is
                // every consumer's absence, because none of them got a stream. It is also exactly what
                // the waveform's own port reports for this file: `makeWaveform` returns `nil`.
                return SharedPCMAnalysisOutcome(
                    waveform: .unavailable, spectrogram: .unavailable,
                    signalLevelMetrics: .unavailable, truePeak: .unavailable, loudness: .unavailable,
                    significantBandwidth: .unavailable
                )
            }
            return consumers.finish(stream: stream)
        } catch {
            // A **producer** failure: no more PCM will exist for anyone. Every consumer ends, and each
            // reports its own outcome rather than a shared one — a caller reading one result must not
            // have to consult another to learn what happened.
            if error.code == .cancelled {
                return SharedPCMAnalysisOutcome(
                    waveform: .cancelled, spectrogram: .cancelled,
                    signalLevelMetrics: .cancelled, truePeak: .cancelled, loudness: .cancelled,
                    significantBandwidth: .cancelled
                )
            }
            // Human, neutral, and carrying no path, no framework text and no stable code — those stay
            // where they are meaningful (ADR-0011). Each analysis keeps the wording it had when it read
            // the file alone, so nothing downstream can tell the difference — the waveform's sentence is
            // the one `SourceInspectionCoordinator` already produces for a failed generation.
            return SharedPCMAnalysisOutcome(
                waveform: .failed(message: "The waveform for this file could not be produced."),
                spectrogram: .failed(message: "The spectrogram for this file could not be produced."),
                signalLevelMetrics: .failed(message: "The signal level metrics for this file could not be produced."),
                truePeak: .failed(message: "The true peak for this file could not be measured."),
                loudness: .failed(message: "The integrated loudness for this file could not be measured."),
                significantBandwidth: .failed(message: "The programme bandwidth for this file could not be measured.")
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
        private var truePeak: TruePeakAccumulator?
        private var loudness: LoudnessAccumulator?
        private var significantBandwidth: SignificantBandwidthAccumulator?
        private var waveform: WaveformEnvelopeAccumulator?
        private var spectrogramFault: String?
        private var signalLevelMetricsFault: String?
        private var truePeakFault: String?
        private var waveformFault: String?
        /// Loudness's own **absence**, kept apart from a fault for the reason the waveform's is: a
        /// stream whose sample rate has no derived weighting, or that carries more than two channels,
        /// is one this measurement does not claim rather than one it failed at. Reporting it as a
        /// failure would blame the file for a scope we chose (ADR-0022 §3, §4).
        private var loudnessAbsent = false
        /// Programme bandwidth's own **absence**, kept apart from a fault for loudness's reason: its
        /// accumulator declines to be built for a stream it does not claim, which is scope rather than
        /// failure. It has no individual fault of its own because none is reachable — the accumulator
        /// ignores a chunk that does not match the stream, exactly as its siblings do.
        private var significantBandwidthAbsent = false
        /// The waveform's one **absence**, kept apart from its faults on purpose: a stream this
        /// resolution cannot be mapped to buckets is a file that offered nothing to size an envelope
        /// against, which its own port reports by returning `nil`. Reporting it as a failure would
        /// blame the file for a limit that is not one.
        private var waveformAbsent = false
        private let maximumBucketCount: Int
        private var prepared = false

        init(maximumBucketCount: Int) {
            self.maximumBucketCount = maximumBucketCount
        }

        /// Whether no consumer can still use a chunk. The read ends only on this, never on one
        /// consumer being done.
        var allFailed: Bool {
            spectrogramFault != nil && signalLevelMetricsFault != nil
                && truePeakFault != nil && (waveformFault != nil || waveformAbsent)
                && loudnessAbsent && significantBandwidthAbsent
        }

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
            // The methodology is the accumulator's own and is not configurable: 8× oversampling and
            // `polyphase_fir_v1` are constants it owns and records inside the measurement it returns
            // (ADR-0006, ADR-0019). Nothing here chooses them, passes them, or repeats them — the only
            // thing this composition knows is how many channels the stream has, exactly as for the
            // other two.
            truePeak = TruePeakAccumulator(channelCount: stream.channelCount)
            if truePeak == nil {
                truePeakFault = "The file describes a stream no analysis can be built for."
            }
            // Sized from the **same** description as the others, which is what makes the shared envelope
            // comparable to the one the waveform's own read produces: that read sizes itself from
            // `AVAudioFile.length`, and this stream's `frameCount` is that same number.
            //
            // Its failure is an **absence**, not a fault. The only way this initialiser can fail here is
            // a frame count the bucket mapping cannot be computed for — `channelCount` is at least one
            // by `PCMStreamDescription`'s own guarantee — and that is exactly the case the legacy port
            // answers with `nil`.
            // Built from the same description as the others, and the **only** consumer that declines
            // for reasons that are not a defect: BS.1770-5 publishes coefficients for 48 kHz alone and
            // weights channels by position, so a rate whose weighting has not been derived and a stream
            // past stereo are both outside what this measurement claims. Neither is a fault — nothing
            // here resamples, guesses a layout, or fabricates a value, and the other four consumers do
            // not notice.
            //
            // The methodology is the accumulator's own, exactly as true peak's is: which coefficients
            // ran is recorded inside the measurement it returns, and nothing in this composition
            // chooses, passes or repeats it.
            loudness = LoudnessAccumulator(
                sampleRate: stream.sampleRate, channelCount: stream.channelCount
            )
            if loudness == nil {
                loudnessAbsent = true
            }
            // Built from the **same** stream description, and nothing about the method crosses this
            // seam: the composition asks "can you measure this stream?" and never names a threshold, a
            // persistence fraction, a budget, a window length or a bucket width.
            significantBandwidth = SignificantBandwidthAccumulator(
                sampleRate: stream.sampleRate, channelCount: stream.channelCount
            )
            if significantBandwidth == nil {
                significantBandwidthAbsent = true
            }
            waveform = WaveformEnvelopeAccumulator(
                totalFrameCount: stream.frameCount,
                channelCount: stream.channelCount,
                maximumBucketCount: maximumBucketCount
            )
            if waveform == nil {
                waveformAbsent = true
            }
        }

        /// Hands the same chunk to every consumer still in the read.
        ///
        /// **The same value, not a copy per consumer**: `PCMChunk` is an immutable struct over
        /// copy-on-write arrays, so a third consumer costs a few more words of struct and not one more
        /// sample. Nothing here converts, re-lays-out or re-materialises the audio for true peak — its
        /// 8× reconstruction is evaluated phase by phase inside the accumulator and never built as a
        /// buffer.
        mutating func accumulate(_ chunk: PCMChunk) {
            if spectrogramFault == nil { spectrogram?.accumulate(chunk) }
            if signalLevelMetricsFault == nil { signalLevelMetrics?.accumulate(chunk) }
            if truePeakFault == nil { truePeak?.accumulate(chunk) }
            if !loudnessAbsent { loudness?.accumulate(chunk) }
            if !significantBandwidthAbsent { significantBandwidth?.accumulate(chunk) }
            if waveformFault == nil, !waveformAbsent { accumulateWaveform(chunk) }
        }

        /// The waveform's fold: the one consumer that takes **runs** rather than whole chunks, and the
        /// one that can **throw**.
        ///
        /// ## The buffer is borrowed, and that is a requirement rather than a flourish
        ///
        /// `accumulate` takes `some Collection<Float>`. Handing it `chunk.channels[channel]` — the
        /// `[Float]` itself — was measured at **3.79–3.81 s** for ten minutes of stereo against
        /// **0.28–0.33 s** for an `UnsafeBufferPointer` view of that same array: a **12× penalty**,
        /// constant across WAV, FLAC and AAC and therefore per-sample rather than anything to do with
        /// decoding. Written the obvious way, sharing the read would make an inspection *slower*. The
        /// pointer form is also exactly what the legacy generator hands its accumulator, so this is the
        /// established shape rather than a new trick.
        ///
        /// Nothing is copied and nothing is allocated: the pointer borrows the chunk's own storage for
        /// the duration of a synchronous call, and `accumulate` cannot outlive it.
        ///
        /// ## Its `startingAtFrame` is the chunk's own `startFrame`
        ///
        /// No parallel counter. `PCMChunk.startFrame` is the absolute frame its first sample sits at,
        /// counted from the start of the file, which is the number this accumulator asks for — the same
        /// number the legacy loop tracks as `framesRead`.
        ///
        /// ## A throw here is the waveform's own failure
        ///
        /// It stops receiving chunks and nothing else changes: the read continues and the other three
        /// consumers settle exactly as they would have. Given the guards the caller already applies,
        /// none of the reachable causes should occur — the channel index comes from the chunk, the
        /// range is checked against the same stream, and `PCMChunk` refuses non-finite samples at
        /// construction — so this is a backstop rather than a path the arithmetic can reach.
        private mutating func accumulateWaveform(_ chunk: PCMChunk) {
            for channel in 0 ..< chunk.channelCount {
                do {
                    // Mutated **in place** through the optional. Lifting the accumulator into a local
                    // would leave two references to its bucket arrays, so the first write would deep-copy
                    // 2 048 floats twice per chunk — the same class of mistake as passing the array.
                    try chunk.channels[channel].withUnsafeBufferPointer { samples throws(WaveformError) in
                        try waveform?.accumulate(
                            samples, ofChannel: channel, startingAtFrame: chunk.startFrame
                        )
                    }
                } catch {
                    waveformFault = "The waveform for this file could not be produced."
                    waveform = nil
                    return
                }
            }
        }

        /// Faults every consumer at once. Used only when the fault is in the audio itself, which none
        /// of them can proceed past — never to propagate one consumer's own failure to another.
        mutating func failAll(with message: String) {
            if spectrogramFault == nil { spectrogramFault = message }
            if signalLevelMetricsFault == nil { signalLevelMetricsFault = message }
            if truePeakFault == nil { truePeakFault = message }
            // Loudness has no fault of its own to set — see `finishLoudness`. A stream whose audio does
            // not match its description leaves it absent, which is what an unmeasurable file already is.
            loudnessAbsent = true
            significantBandwidthAbsent = true
            // Not applied to a waveform that is **absent**: that is not a fault waiting to be
            // overwritten, and turning it into one would report a failure for a file that simply
            // offered nothing to size against.
            if waveformFault == nil, !waveformAbsent { waveformFault = message }
        }

        /// Each consumer's own result, computed independently of the others.
        ///
        /// A file with no audio delivers no chunk, so nothing was ever prepared: each consumer's empty
        /// model is built here from the stream and reported as **available**, because an empty answer is
        /// a complete one rather than a missing one — the rule each analysis already followed alone.
        func finish(stream: PCMStreamDescription) -> SharedPCMAnalysisOutcome {
            SharedPCMAnalysisOutcome(
                waveform: finishWaveform(stream: stream),
                spectrogram: finishSpectrogram(stream: stream),
                signalLevelMetrics: finishSignalLevelMetrics(stream: stream),
                truePeak: finishTruePeak(stream: stream),
                loudness: finishLoudness(stream: stream),
                significantBandwidth: finishSignificantBandwidth(stream: stream)
            )
        }

        /// The waveform's own result, mapped onto the three meanings its port already keeps apart.
        ///
        /// A file with **no audio** delivers no chunk, so nothing was prepared: the accumulator is built
        /// here from the stream and finished immediately, which yields an envelope with **no buckets**.
        /// That is `available`, not absent — the legacy generator takes the identical shortcut
        /// (`if frameCount == 0 { return try accumulator.finished() }`), and an empty answer is a
        /// complete one.
        ///
        /// A frame count this resolution cannot map to buckets is the **absence** the legacy port
        /// reports by returning `nil`, and it stays an absence here.
        ///
        /// `finished()` throwing is a failure of the waveform alone — it means a bucket went uncovered,
        /// which is the accumulator refusing to invent a flat stretch the file may not contain.
        private func finishWaveform(stream: PCMStreamDescription) -> WaveformOutcome {
            if waveformAbsent { return .unavailable }
            if let waveformFault { return .failed(message: waveformFault) }
            guard let accumulator = waveform ?? WaveformEnvelopeAccumulator(
                totalFrameCount: stream.frameCount,
                channelCount: stream.channelCount,
                maximumBucketCount: maximumBucketCount
            ) else {
                return .unavailable
            }
            guard let envelope = try? accumulator.finished() else {
                return .failed(message: "The waveform for this file could not be produced.")
            }
            return .available(envelope)
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

        /// True peak's own result.
        ///
        /// **A `finish()` that can refuse its own result**, like both of its siblings now: `PCMChunk`
        /// refuses `NaN` and infinity at the boundary but keeps finite samples of any magnitude, and a
        /// 48-tap convolution over finite-but-enormous values can overflow to a value the domain model
        /// refuses. The accumulator says so by returning `nil`, and it becomes **true peak's** failure
        /// and nobody else's — the spectrogram and the signal level metrics settle from the same chunks
        /// exactly as they would have.
        ///
        /// The accumulator is a `var` because its `finish()` flushes the tail through the trailing
        /// zero-extension, which mutates. It is a struct, so this works on this function's own copy and
        /// leaves the stored one alone.
        private func finishTruePeak(stream: PCMStreamDescription) -> TruePeakOutcome {
            if let truePeakFault { return .failed(message: truePeakFault) }
            guard var accumulator = truePeak ?? TruePeakAccumulator(channelCount: stream.channelCount) else {
                return .failed(message: "The true peak for this file could not be measured.")
            }
            guard let model = accumulator.finish() else {
                return .failed(message: "The true peak for this file could not be measured.")
            }
            return .available(model)
        }

        /// Integrated loudness's own result — and the one consumer with **no reachable failure of its
        /// own**, which is stated rather than left to be inferred from the absence of a fault field.
        ///
        /// Every way this can end without a value is an **absence**:
        ///
        /// - the accumulator declined to be built, because the rate has no derived weighting or the
        ///   stream carries more than two channels;
        /// - `finish()` returned `nil`, which the standard's own definition produces for a programme
        ///   shorter than one 400 ms gating block and for one where no block clears the −70 LKFS
        ///   absolute gate. That is **a complete answer from the algorithm**, not a malfunction of it.
        ///
        /// The one path that would be a genuine failure — an energy sum so large that the loudness came
        /// out non-finite and the domain model refused it — **is unreachable given the inputs**:
        /// `PCMChunk` admits only finite `Float`s, whose square is at most ~1.2 × 10⁷⁷, and a mean over
        /// blocks cannot exceed that. `Double` overflows at ~1.8 × 10³⁰⁸. So the guard inside
        /// `LoudnessMeasurement` is a backstop the arithmetic cannot reach from here.
        ///
        /// This mirrors the limitation `SignalLevelMetricsAccumulator` already documents for its own
        /// `nil`: recorded honestly rather than met with an invented failure path.
        /// Programme bandwidth's own result. The methodology is the accumulator's own and is not
        /// configurable here: the composition asks only whether this stream can be measured, never what
        /// the threshold, the persistence fraction, the budget or the window length are.
        private func finishSignificantBandwidth(stream: PCMStreamDescription) -> SignificantBandwidthOutcome {
            if significantBandwidthAbsent { return .unavailable }
            let accumulator = significantBandwidth ?? SignificantBandwidthAccumulator(
                sampleRate: stream.sampleRate, channelCount: stream.channelCount
            )
            guard let model = accumulator?.finish() else { return .unavailable }
            return .available(model)
        }

        private func finishLoudness(stream: PCMStreamDescription) -> LoudnessOutcome {
            if loudnessAbsent { return .unavailable }
            let accumulator = loudness ?? LoudnessAccumulator(
                sampleRate: stream.sampleRate, channelCount: stream.channelCount
            )
            guard let model = accumulator?.finish() else { return .unavailable }
            return .available(model)
        }
    }
}
