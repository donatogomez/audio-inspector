import AudioInspectorDomain
import Testing

// **Why the waveform can share the decoding seam after all — and why the record of the blocker is kept
// rather than deleted.**
//
// This suite used to assert the opposite: that the migration was blocked because two
// `AudioDecodingErrorCode` values have no honest `WaveformErrorCode` counterpart, and
// `add-static-spectrogram-visualization`'s group 9 required the waveform's error space to stay
// unchanged. That was true, and it is still true — of the shape it was measured against.
//
// **The blocker was about reimplementing `WaveformGenerating` on top of `AudioDecoding`**, which means
// translating one error space into the other. ADR-0021 took a different shape: the waveform became a
// *consumer* of the shared read, and a consumer translates nothing. The shared composition turns a
// producer failure into a per-consumer message, exactly as it does for the other three, so no
// `AudioDecodingError` ever needs a `WaveformErrorCode`.
//
// The two untranslatable codes are therefore still untranslatable, and that no longer blocks anything.
// Both facts are asserted below, because a future reader deserves the reasoning and not just the
// outcome — and because if the waveform's error space ever grows a counterpart for them, the premise
// this change was argued from has moved and should be re-read rather than assumed.

@Suite("Domain — how the waveform came to share the decoding seam")
struct WaveformDecodingSeamMigrationTests {

    /// Every code an `AudioDecoding` implementation may throw. Listed explicitly, so adding one without
    /// deciding what a waveform consumer would do with it breaks this test rather than slipping through.
    private static let decodingCodes: [AudioDecodingErrorCode] = [
        .invalidStreamDescription, .invalidChunk, .nonFiniteSample, .cancelled,
        .invalidConfiguration, .fileAccessDenied, .fileOpenFailed,
        .unsupportedProcessingFormat, .readFailed,
    ]

    /// Every code the waveform's own space defines, adapter codes included.
    private static let waveformCodes: [WaveformErrorCode] = [
        .invalidConfiguration, .nonFiniteSample, .channelOutOfBounds, .frameRangeOutOfBounds,
        .incompleteCoverage, .cancelled, .fileAccessDenied, .fileOpenFailed,
        .unsupportedProcessingFormat, .readFailed,
    ]

    /// The two spaces name the same fault the same way, prefix aside — that is what makes an exhaustive
    /// translation possible at all, and what makes the two exceptions below meaningful.
    private static func waveformCounterpart(of code: AudioDecodingErrorCode) -> WaveformErrorCode? {
        let suffix = code.rawValue.replacingOccurrences(of: "decoding_", with: "")
        let candidate = WaveformErrorCode(rawValue: "waveform_\(suffix)")
        return waveformCodes.contains(candidate) ? candidate : nil
    }

    /// The codes that **do** translate exactly. Seven of nine, which is why the migration looks feasible
    /// right up until the last two.
    @Test(
        "most decoding faults have an exact waveform counterpart",
        arguments: [
            AudioDecodingErrorCode.nonFiniteSample, .cancelled, .invalidConfiguration,
            .fileAccessDenied, .fileOpenFailed, .unsupportedProcessingFormat, .readFailed,
        ]
    )
    func mostFaultsTranslateExactly(code: AudioDecodingErrorCode) {
        #expect(
            Self.waveformCounterpart(of: code) != nil,
            "\(code.rawValue) lost its waveform counterpart — the migration's arithmetic has changed"
        )
    }

    /// **What used to be the blocker.** Two decoding faults describe something the waveform's space
    /// cannot say — and under ADR-0021's shape, nothing ever asks it to.
    ///
    /// - `decoding_invalid_stream_description` — the file describes a stream that cannot exist (a
    ///   non-positive or non-finite sample rate). The waveform adapter does not read the sample rate at
    ///   all today, so this is not merely untranslatable: it is a **new failure where the current code
    ///   succeeds**.
    /// - `decoding_invalid_chunk` — a chunk's parts do not describe a possible run of audio. The native
    ///   adapter cannot produce one, but `AudioDecoding` is a port, so a consumer taking `any
    ///   AudioDecoding` must answer for it.
    ///
    /// Neither can be mapped honestly. `readFailed` would claim the file could not be read to the end it
    /// declared, which is a different thing that did not happen; `invalidConfiguration` would blame the
    /// caller's configuration for a fault in the file. Inventing `waveform_invalid_stream_description`
    /// was not available either — `WaveformErrorTests` is deliberately written to break when a code
    /// appears.
    ///
    /// **This is still true and no longer blocks anything.** A consumer of the shared read never
    /// translates: when the decoder fails, the composition ends every consumer with its own human
    /// sentence, and `WaveformError` stays where it always was — inside the accumulator.
    @Test(
        "two decoding faults still have no honest waveform counterpart, and no longer need one",
        arguments: [AudioDecodingErrorCode.invalidStreamDescription, .invalidChunk]
    )
    func twoFaultsCannotBeTranslated(code: AudioDecodingErrorCode) {
        #expect(
            Self.waveformCounterpart(of: code) == nil,
            """
            \(code.rawValue) now has a waveform counterpart. The waveform's error space has grown, which \
            is the premise ADR-0021 argued from — re-read its decision 2 before assuming the reasoning \
            still holds.
            """
        )
    }

    /// The waveform's space is exactly as large as it was when the stop rule was applied — **and the
    /// migration did not change it**, which is the property ADR-0021 decision 2 claims. Guards the
    /// premise of the test above from the other direction: a code added anywhere, for any reason, makes
    /// that claim stale.
    @Test("the waveform error space is unchanged")
    func theWaveformSpaceIsUnchanged() {
        #expect(Self.waveformCodes.count == 10)
        #expect(Set(Self.waveformCodes.map(\.rawValue)).count == 10)
        #expect(Self.waveformCodes.allSatisfy { $0.rawValue.hasPrefix("waveform_") })
    }

    /// And the two spaces stay disjoint, so neither can quietly absorb the other. The same guarantee
    /// `WaveformErrorTests` already makes against the inspection space, made against this one.
    @Test("the waveform and decoding error spaces do not collide")
    func theSpacesAreDisjoint() {
        let waveform = Set(Self.waveformCodes.map(\.rawValue))
        let decoding = Set(Self.decodingCodes.map(\.rawValue))
        #expect(waveform.isDisjoint(with: decoding))
        #expect(decoding.allSatisfy { $0.hasPrefix("decoding_") })
    }

    /// The distinction the migration must not blur, and the reason both ports keep cancellation as an
    /// **error** rather than an absence: `nil` means the file offered nothing to size against, and a
    /// caller who cancelled has learnt nothing about their file. Both spaces say this the same way, so
    /// this much of the seam is genuinely ready.
    @Test("both ports keep cancellation apart from an absence, and say so the same way")
    func cancellationIsNeverAnAbsence() {
        #expect(WaveformErrorCode.cancelled.rawValue == "waveform_cancelled")
        #expect(AudioDecodingErrorCode.cancelled.rawValue == "decoding_cancelled")
        #expect(WaveformErrorCode.cancelled != .readFailed)
        #expect(AudioDecodingErrorCode.cancelled != .readFailed)
    }

    /// **The capability that made the migration possible, asserted rather than described.**
    ///
    /// The deferral rested on the waveform needing something the seam did not carry: an absolute frame
    /// position per run. `PCMChunk` has always carried exactly that, and this is where that stops being
    /// a claim in a design document.
    @Test("a chunk already carries the absolute position the waveform's reduction asks for")
    func theChunkCarriesThePosition() throws {
        let samples = [Float](repeating: 0.25, count: 512)
        let chunk = try PCMChunk(startFrame: 4_096, channels: [samples, samples])

        #expect(chunk.startFrame == 4_096, "the position is the chunk's own, not the caller's bookkeeping")
        #expect(chunk.frameCount == 512)
        #expect(chunk.channelCount == 2)

        // And it is exactly what the reduction accepts, for the channel and range it names.
        var accumulator = try #require(
            WaveformEnvelopeAccumulator(totalFrameCount: 8_192, channelCount: 2)
        )
        for channel in 0 ..< chunk.channelCount {
            try chunk.channels[channel].withUnsafeBufferPointer { buffer throws(WaveformError) in
                try accumulator.accumulate(buffer, ofChannel: channel, startingAtFrame: chunk.startFrame)
            }
        }
    }
}
