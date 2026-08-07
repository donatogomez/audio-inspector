import AudioInspectorDomain
import Testing

// Why the waveform has **not** been migrated onto `AudioDecoding` (change
// `add-static-spectrogram-visualization`, group 9, stop rule 9.6).
//
// The migration is conditional by design: it happens only if it preserves `WaveformGenerating`'s
// contract, its error space and every existing waveform test without coupling the two consumers. It
// does not, and the reason is mechanical rather than a matter of taste — so it is written here as
// assertions instead of only as prose. If someone later closes the gap, **these tests fail**, and the
// deferral is revisited deliberately rather than forgotten.
//
// Nothing here tests production behaviour. It tests the shape of two error spaces, which is exactly
// what blocks the migration.

@Suite("Domain — the waveform cannot yet be expressed through the decoding seam")
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

    /// **The blocker.** Two decoding faults describe something the waveform's space cannot say.
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
    /// caller's configuration for a fault in the file. Task 9.1 requires the waveform's error space to be
    /// **unchanged**, so inventing `waveform_invalid_stream_description` is not available either — and
    /// `WaveformErrorTests` is deliberately written to break when a code appears.
    @Test(
        "two decoding faults have no honest waveform counterpart, which is what defers the migration",
        arguments: [AudioDecodingErrorCode.invalidStreamDescription, .invalidChunk]
    )
    func twoFaultsCannotBeTranslated(code: AudioDecodingErrorCode) {
        #expect(
            Self.waveformCounterpart(of: code) == nil,
            """
            \(code.rawValue) now has a waveform counterpart. The waveform's error space has changed, so \
            group 9's stop rule must be re-evaluated: re-read tasks 9.1–9.6 before assuming the \
            migration is still blocked.
            """
        )
    }

    /// The waveform's space is exactly as large as it was when the stop rule was applied. Guards the
    /// premise of the test above from the other direction: a code added anywhere, for any reason, makes
    /// the deferral's reasoning stale.
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
}
