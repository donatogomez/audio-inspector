import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

import AudioInspectorDomain

/// The native (AVFoundation/CoreMedia) implementation of the domain port `AudioFilePropertyReading`.
///
/// It opens the selected file, runs a deterministic track-selection flow (spike 0031), and maps each
/// technical field into its `Property` case. **Errors are classified by scope, not by which API threw**
/// (ADR-0011 §5, task 3.6): a whole-file failure (the asset/tracks cannot be opened or read) is a
/// thrown **global** `InspectionError`; a single-property read failure — while the rest of the report
/// can still be produced — becomes `Property.failed(PropertyFailure(.propertyReadError, …))`. Absence of
/// a datum is `unavailable`/`uncertain`, never `failed`.
///
/// Boundary (ADR-0011): this type lives in `AudioInspectorMedia` — the only target allowed to import
/// AVFoundation/CoreMedia — and returns **only** domain value types. No `AVAsset`, `CMFormatDescription`,
/// `AudioStreamBasicDescription`, `NSError`, `AVError`, or `OSStatus` ever crosses the port; Apple errors
/// are inspected only inside this adapter and converted to stable domain codes. It imports no
/// AudioToolbox (ADR-0012: not adopted for this slice).
public struct AVFoundationAudioFilePropertyReader: AudioFilePropertyReading {
    /// Resolves the file URL to open for a domain reference.
    ///
    /// The domain `AudioFileReference` intentionally carries **no** URL/path/bookmark (ADR-0010); the
    /// real security-scoped URL is supplied by the sandbox file-selection work (group 6), which wires a
    /// concrete resolver in the composition root. The default returns `nil`, so without a resolver an
    /// inspection fails as a global access error rather than silently succeeding. This is the seam only —
    /// no security-scoped access is implemented here.
    private let resolveURL: @Sendable (AudioFileReference) -> URL?

    /// Minimal initializer — no singletons, no shared/mutable state, no caches.
    public init(resolveURL: @escaping @Sendable (AudioFileReference) -> URL? = { _ in nil }) {
        self.resolveURL = resolveURL
    }

    public func readProperties(of file: AudioFileReference) async throws(InspectionError) -> TechnicalProperties {
        guard let url = resolveURL(file) else {
            // Group 6 supplies the security-scoped URL; until then, no accessible location → global error.
            throw InspectionError(
                code: .fileAccessDenied,
                message: "No accessible file URL was provided for the inspection."
            )
        }
        let loaded = try await loadAudio(from: url)
        return technicalProperties(from: loaded)
    }
}

// MARK: - Load result (value / absence / read-error, without leaking the Apple error)

private extension AVFoundationAudioFilePropertyReader {
    /// The outcome of one per-property load, preserving the distinction the domain needs. It carries a
    /// **flat value copy** on success and *no* Apple error on failure — the original `NSError`/`AVError`
    /// is caught and discarded at the point of failure, never stored or forwarded (ADR-0011 §5).
    enum LoadedProperty<Value> {
        /// A value was obtained.
        case value(Value)
        /// The source is simply absent (no track, no description, no datum) — not an error.
        case unavailable
        /// Reading this specific datum errored, while the rest of the inspection can continue.
        case failed
    }

    /// Runs an async throwing load and captures value-or-read-error, converting a thrown Apple error into
    /// a scope-local `.failed` without letting it escape.
    static func captured<Value>(_ operation: () async throws -> Value) async -> LoadedProperty<Value> {
        do {
            return .value(try await operation())
        } catch {
            return .failed
        }
    }
}

// MARK: - Flow (open → load tracks [global] → per-property loads → assemble)

private extension AVFoundationAudioFilePropertyReader {
    /// The per-load results the field mappers read from. Not `Sendable`-required: it never crosses an
    /// isolation boundary (the reader is nonisolated and the mappers are synchronous, called without an
    /// intervening `await`). It holds only flat value copies — no `AVAsset`/`AVAssetTrack`/pointer.
    struct LoadedAudio {
        /// The resolved file URL — raw material for `container` inference (its own read is done in the
        /// `container` mapper, which distinguishes an absent type from a resource-values read error).
        let url: URL
        /// The first format description of the selected audio track: `value` / `unavailable` (no track or
        /// no description) / `failed` (the `formatDescriptions` load errored). Feeds every ASBD field.
        let formatDescription: LoadedProperty<CMFormatDescription>
        /// The asset duration: `value` (a possibly-indefinite `CMTime`) / `failed` (the load errored).
        let duration: LoadedProperty<CMTime>
        /// The selected track's `estimatedDataRate` (bits/s): `value` / `unavailable` (no track) /
        /// `failed` (the load errored).
        let estimatedDataRate: LoadedProperty<Float>
    }

    /// Opens the asset and runs the deterministic track-selection policy.
    ///
    /// **Scope rule (ADR-0011):** only a *whole-file* failure — the asset or its audio tracks cannot be
    /// opened/read, so no useful property set can be produced — is a thrown **global** `InspectionError`.
    /// Every *subsequent* per-property load (format descriptions, estimated data rate, duration) is
    /// captured as `value`/`unavailable`/`failed` and does **not** abort the inspection.
    func loadAudio(from url: URL) async throws(InspectionError) -> LoadedAudio {
        let asset = AVURLAsset(url: url)

        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw Self.globalError(from: error) // whole-file failure → global, classified by scope
        }
        // Deterministic track-selection policy (spike 0031/A): the first audio track, or none.
        let audioTrack = audioTracks.first

        let formatDescription: LoadedProperty<CMFormatDescription>
        let estimatedDataRate: LoadedProperty<Float>
        if let audioTrack {
            // A thrown `formatDescriptions` load → `.failed` for the ASBD fields (per-property, not
            // global); an empty list → `.unavailable`. `.first` distinguishes the two.
            do {
                if let first = try await audioTrack.load(.formatDescriptions).first {
                    formatDescription = .value(first)
                } else {
                    formatDescription = .unavailable
                }
            } catch {
                formatDescription = .failed
            }
            estimatedDataRate = await Self.captured { try await audioTrack.load(.estimatedDataRate) }
        } else {
            // Zero audio tracks: stream fields are `unavailable` (not a global failure, spike 0031/A).
            formatDescription = .unavailable
            estimatedDataRate = .unavailable
        }

        let duration = await Self.captured { try await asset.load(.duration) }

        return LoadedAudio(
            url: url,
            formatDescription: formatDescription,
            duration: duration,
            estimatedDataRate: estimatedDataRate
        )
    }

    /// Assembles `TechnicalProperties` from the per-field mappers. The audio stream basic description is
    /// derived **once** here (preserving the value/absence/read-error distinction) and shared by every
    /// ASBD-dependent mapper (`sampleRate`/`channelCount`/`bitDepth`/`codec`), so the CoreMedia access is
    /// not duplicated.
    func technicalProperties(from loaded: LoadedAudio) -> TechnicalProperties {
        let stream = Self.streamProperty(from: loaded.formatDescription)
        return TechnicalProperties(
            container: container(from: loaded.url),
            duration: duration(from: loaded.duration),
            sampleRate: sampleRate(from: stream),
            channelCount: channelCount(from: stream),
            bitDepth: bitDepth(from: stream),
            codec: codec(from: stream),
            declaredBitrate: declaredBitrate(from: loaded),
            estimatedBitrate: estimatedBitrate(from: loaded.estimatedDataRate)
        )
    }
}

// MARK: - Audio stream basic description (shared by the structural mappers)

private extension AVFoundationAudioFilePropertyReader {
    /// Lifts the format-description load result into an ASBD load result. `failed`/`unavailable` pass
    /// through; a present description with no ASBD is `unavailable` (absence, not an error).
    static func streamProperty(from formatDescription: LoadedProperty<CMFormatDescription>) -> LoadedProperty<AudioStreamBasicDescription> {
        switch formatDescription {
        case .failed:
            return .failed
        case .unavailable:
            return .unavailable
        case let .value(description):
            if let asbd = streamBasicDescription(from: description) { return .value(asbd) }
            return .unavailable
        }
    }

    /// Copies the `AudioStreamBasicDescription` out of a format description, or `nil` when it carries no
    /// ASBD. The CoreMedia pointer is dereferenced and **copied immediately** into a value; no pointer is
    /// stored, retained, or escapes this function. No force-unwrap, no AudioToolbox.
    static func streamBasicDescription(from formatDescription: CMFormatDescription) -> AudioStreamBasicDescription? {
        guard let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return nil }
        return pointer.pointee
    }

    /// Serializes a FourCharCode (e.g. an `AudioFormatID`) into a stable, **non-localized** token
    /// (finalizing the serialization the spike deferred — spike 0031/C). The four bytes are read
    /// **big-endian** (MSB = first char). When every byte is printable ASCII (`0x20…0x7E`), **trailing
    /// spaces are trimmed** so common space-padded codes read naturally — e.g. `'aac '`
    /// (`kAudioFormatMPEG4AAC`) → `aac`, `'lpcm'` → `lpcm`. Any NUL/control/non-ASCII byte, an empty
    /// result, or a leading/internal space (never legitimate padding) falls back to a fixed-width
    /// uppercase hex form, keeping the token unambiguous. Deterministic; never a localized description;
    /// no force-unwrap.
    static func fourCharCodeToken(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) {
            var end = bytes.count
            while end > 0, bytes[end - 1] == 0x20 { end -= 1 } // trim trailing-space padding only
            let trimmed = bytes[0 ..< end]
            if !trimmed.isEmpty, !trimmed.contains(0x20) { // reject empty / leading / internal spaces
                return String(decoding: trimmed, as: UTF8.self)
            }
        }
        return String(format: "0x%08X", code)
    }

    /// A property-level read failure with the stable domain code. Messages are deterministic,
    /// non-localized, and contain no path/filename/system value (ADR-0008).
    static func readFailure(_ message: String) -> PropertyFailure {
        PropertyFailure(code: .propertyReadError, message: message)
    }
}

// MARK: - Per-field mappers

private extension AVFoundationAudioFilePropertyReader {
    /// `container` from the file's content type (`URLResourceValues.contentType`, a `UTType`).
    ///
    /// Spike 0031/F found **no direct real-container signal** among the evaluated AVFoundation/CoreMedia
    /// APIs (only the codec), and the content type is a *type/extension inference* that was provably wrong
    /// for a renamed file. So a resolved type is `uncertain` — carrying the stable, **non-localized** UTI
    /// identifier as the tentative value — **never `available`**. An absent type is `unavailable`; a
    /// `resourceValues` **read error** is `failed` (now distinguished from absence, task 3.6). No deep
    /// byte inspection; no deduction from MIME/codec/name; no path/URL in messages (ADR-0012).
    func container(from url: URL) -> Property<String> {
        let contentType: UTType?
        do {
            contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        } catch {
            return .failed(Self.readFailure("Could not read the file's content type."))
        }
        guard let contentType else { return .unavailable(reason: nil) }
        return .uncertain(
            value: contentType.identifier,
            reason: "Inferred from the file's type identifier; not verified against the container bytes."
        )
    }

    /// `duration` (seconds) from the already-loaded `CMTime` (no re-load, no second asset access).
    /// A read error → `failed`; otherwise, conservative per spike 0031/E: positive finite numeric →
    /// `available`; exactly zero → `uncertain` keeping the observed `0`; negative → `unavailable`;
    /// invalid/indefinite/non-numeric/non-finite → `unavailable`.
    func duration(from loaded: LoadedProperty<CMTime>) -> Property<Double> {
        switch loaded {
        case .failed:
            return .failed(Self.readFailure("Could not read the duration."))
        case .unavailable:
            return .unavailable(reason: nil)
        case let .value(time):
            guard time.isValid, time.isNumeric else { return .unavailable(reason: nil) }
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return .unavailable(reason: nil) }
            if seconds > 0 { return .available(seconds) }
            if seconds == 0 {
                return .uncertain(
                    value: 0,
                    reason: "Duration was reported as zero and could not be confirmed; the file may be empty or truncated."
                )
            }
            return .unavailable(reason: nil) // negative duration is invalid
        }
    }

    /// `sampleRate` (Hz) from the ASBD `mSampleRate`. Read error → `failed`; no track/description/ASBD →
    /// `unavailable`; `available` only for a finite, strictly-positive value that is **exactly** an
    /// integer (the domain models Hz as `Int`, so no silent rounding).
    func sampleRate(from stream: LoadedProperty<AudioStreamBasicDescription>) -> Property<Int> {
        switch stream {
        case .failed:
            return .failed(Self.readFailure("Could not read the audio format description."))
        case .unavailable:
            return .unavailable(reason: nil)
        case let .value(asbd):
            let hertz = asbd.mSampleRate
            guard hertz.isFinite, hertz > 0, let value = Int(exactly: hertz) else {
                return .unavailable(reason: nil)
            }
            return .available(value)
        }
    }

    /// `channelCount` from the ASBD `mChannelsPerFrame`. Read error → `failed`; no ASBD → `unavailable`;
    /// `available` only for a strictly-positive count safely representable as the domain's `Int`. Never
    /// inferred from channel layouts, labels, or names.
    func channelCount(from stream: LoadedProperty<AudioStreamBasicDescription>) -> Property<Int> {
        switch stream {
        case .failed:
            return .failed(Self.readFailure("Could not read the audio format description."))
        case .unavailable:
            return .unavailable(reason: nil)
        case let .value(asbd):
            let channels = asbd.mChannelsPerFrame
            guard channels > 0, let value = Int(exactly: channels) else {
                return .unavailable(reason: nil)
            }
            return .available(value)
        }
    }

    /// `bitDepth` (bits) from the ASBD `mBitsPerChannel` — **never** formula-inferred (spike 0031/D). Read
    /// error → `failed`. Only **Linear PCM** has a spike-validated, semantically-applicable sample depth →
    /// `available` when `mBitsPerChannel > 0` (PCM with a `0` field → `unavailable`). Any **non-PCM**
    /// format → `unavailable`: robustly telling a lossy codec (bit depth N/A → `unsupported`) from a
    /// lossless-compressed one needs codec classification the spike did not validate and ADR-0012 forbids
    /// via a codec table, so `unsupported` is intentionally not emitted here (the split is deferred).
    func bitDepth(from stream: LoadedProperty<AudioStreamBasicDescription>) -> Property<Int> {
        switch stream {
        case .failed:
            return .failed(Self.readFailure("Could not read the audio format description."))
        case .unavailable:
            return .unavailable(reason: nil)
        case let .value(asbd):
            guard asbd.mFormatID == kAudioFormatLinearPCM else { return .unavailable(reason: nil) }
            let bits = asbd.mBitsPerChannel
            guard bits > 0, let value = Int(exactly: bits) else { return .unavailable(reason: nil) }
            return .available(value)
        }
    }

    /// `codec` as a stable, non-localized token from the ASBD `mFormatID` (the decoded audio format —
    /// direct recognition, spike 0031/C). Read error → `failed`; no ASBD or a zero format id →
    /// `unavailable`; a valid id → `available` (token via `fourCharCodeToken`).
    func codec(from stream: LoadedProperty<AudioStreamBasicDescription>) -> Property<String> {
        switch stream {
        case .failed:
            return .failed(Self.readFailure("Could not read the audio format description."))
        case .unavailable:
            return .unavailable(reason: nil)
        case let .value(asbd):
            guard asbd.mFormatID != 0 else { return .unavailable(reason: nil) }
            return .available(Self.fourCharCodeToken(asbd.mFormatID))
        }
    }

    /// `declaredBitrate` — a nominal rate **directly declared** by container/codec metadata, with **no
    /// self-computation**. Spike 0031/G found no such direct source among the evaluated AVFoundation APIs,
    /// and the adapter does not attempt to read one, so it is always `unavailable` — an *absence of
    /// capability*, **not** a read error, so never `failed`. No value is fabricated; no AudioToolbox.
    func declaredBitrate(from _: LoadedAudio) -> Property<Int> {
        .unavailable(reason: nil)
    }

    /// `estimatedBitrate` — **always `uncertain`** by contract (criterion 3.5; matrix; design), except a
    /// genuine read **error**, which the matrix reserves for `failed`. So: a read error → `failed`; a
    /// usable value (finite, `>0`, exactly an `Int`, no rounding) → `uncertain(value)`; absence or an
    /// unusable value (no track, `0`, negative, non-finite, fractional) → `uncertain(nil)`. It never
    /// carries a declared bitrate and never self-computes from size/duration.
    func estimatedBitrate(from loaded: LoadedProperty<Float>) -> Property<Int> {
        switch loaded {
        case .failed:
            return .failed(Self.readFailure("Could not read the estimated data rate."))
        case .unavailable:
            return .uncertain(value: nil, reason: Self.noEstimateReason)
        case let .value(rate):
            guard rate.isFinite, rate > 0, let value = Int(exactly: rate) else {
                return .uncertain(value: nil, reason: Self.noEstimateReason)
            }
            return .uncertain(
                value: value,
                reason: "Framework estimated data rate; an estimate — not a declared bitrate — that may not exactly represent the stream."
            )
        }
    }

    static var noEstimateReason: String { "No reliable bitrate estimate is available from the file." }
}

// MARK: - Global error classification (by scope/effect — ADR-0011 §5; no Apple error crosses the port)

private extension AVFoundationAudioFilePropertyReader {
    /// Converts a whole-file failure into a **global** `InspectionError`, classified by scope using
    /// bridged Swift error types (inspected **only here**, never forwarded). Permission denial →
    /// `fileAccessDenied`; an unrecognizable/corrupt/unreadable file → `fileUnreadable`; anything else →
    /// the stable `fileOpenFailed` fallback. No `NSError`/`AVError`/`OSStatus`/`localizedDescription`/URL
    /// leaves this function — only a stable code and a deterministic message.
    static func globalError(from error: some Error) -> InspectionError {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileReadNoPermission:
                return InspectionError(code: .fileAccessDenied, message: "Access to the file was denied.")
            case .fileReadCorruptFile:
                // Opened, but the media is corrupt → "opened but not read".
                return InspectionError(code: .fileUnreadable, message: "The file could not be read for inspection.")
            default:
                // A missing file (`fileReadNoSuchFile`) could not be *opened*, and an unknown read error
                // is not reliably "unreadable media" — both take the stable `fileOpenFailed` fallback
                // rather than over-claiming `fileUnreadable`.
                break
            }
        }
        if let av = error as? AVError {
            switch av.code {
            case .fileFormatNotRecognized, .failedToParse, .undecodableMediaData:
                return InspectionError(code: .fileUnreadable, message: "The file's media could not be recognized or read.")
            default:
                break
            }
        }
        return InspectionError(code: .fileOpenFailed, message: "The file could not be opened for inspection.")
    }
}
