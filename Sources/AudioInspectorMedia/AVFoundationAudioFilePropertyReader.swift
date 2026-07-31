import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

import AudioInspectorDomain

/// The native (AVFoundation/CoreMedia) implementation of the domain port `AudioFilePropertyReading`.
///
/// **Task 3.2 — skeleton only.** This establishes the adapter's shape and the deterministic
/// track-selection flow validated by spike 0031 (`docs/spikes/0031-audio-property-api-validation.md`);
/// the per-field mapping is intentionally **not** implemented here — each mapper returns a conservative
/// placeholder and is completed by tasks 3.3 (`sampleRate`/`channelCount`), 3.4 (`container`/`duration`/
/// `codec`) and 3.5 (`bitDepth`/bitrates). Error translation is skeletal (a single conservative global
/// code); the scope-based taxonomy is task 3.6 (ADR-0011 §5).
///
/// Boundary (ADR-0011): this type lives in `AudioInspectorMedia` — the only target allowed to import
/// AVFoundation/CoreMedia — and returns **only** domain value types; no `AVAsset`, `CMFormatDescription`,
/// `NSError`, or `OSStatus` ever crosses the port. It imports no AudioToolbox (ADR-0012: not adopted for
/// this slice).
public struct AVFoundationAudioFilePropertyReader: AudioFilePropertyReading {
    /// Resolves the file URL to open for a domain reference.
    ///
    /// The domain `AudioFileReference` intentionally carries **no** URL/path/bookmark (ADR-0010); the
    /// real security-scoped URL is supplied by the sandbox file-selection work (group 6), which wires a
    /// concrete resolver in the composition root. The default returns `nil`, so without a resolver an
    /// inspection fails as a global access error rather than silently succeeding. This is the seam only —
    /// no security-scoped access is implemented here.
    private let resolveURL: @Sendable (AudioFileReference) -> URL?

    /// Minimal initializer — no singletons, no shared/mutable state, no caches (§8).
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

// MARK: - Flow (open → load tracks → select track[0] → first format description)

private extension AVFoundationAudioFilePropertyReader {
    /// The raw AVFoundation pieces the field mappers (3.3–3.5) will read from, gathered by the flow.
    /// Not `Sendable`-required: it never crosses an isolation boundary (the reader is nonisolated and the
    /// mappers are synchronous, called without an intervening `await`).
    struct LoadedAudio {
        /// The resolved file URL — raw material for `container` inference (UTI/extension) in task 3.4.
        let url: URL
        /// The first format description of the selected audio track (`track[0]`), or `nil` when the file
        /// exposes no audio track or the track carries no description. Its ASBD feeds 3.3 and 3.5.
        let formatDescription: CMFormatDescription?
        /// The asset duration, or `nil` when the duration load **errored** — a **per-property** concern,
        /// not a global failure (spike 0031, experiments E/H). A successful load yields a `CMTime`
        /// (possibly indefinite) that 3.4 maps by value, so `nil` here signals to 3.6 that the duration
        /// read failed (→ property-level `failed`), distinct from a present-but-indefinite duration.
        let duration: CMTime?
    }

    /// Opens the asset and runs the deterministic track-selection policy. A whole-file failure (the asset
    /// or its tracks cannot be opened/read) is a **global** `InspectionError` (ADR-0011); a duration-only
    /// failure is kept per-property (optional) and does not abort the inspection.
    func loadAudio(from url: URL) async throws(InspectionError) -> LoadedAudio {
        let asset = AVURLAsset(url: url)
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            // Deterministic track-selection policy (spike 0031/A): the first audio track, or none.
            // This is a provisional rule — not a claim of a "primary/preferred" track.
            let audioTrack = audioTracks.first
            var formatDescription: CMFormatDescription?
            if let audioTrack {
                formatDescription = try await audioTrack.load(.formatDescriptions).first
            }
            // Duration failure is per-property, not global (spike 0031/E,H): a *thrown* load error
            // collapses to `nil` here (→ 3.6 property-level `failed`), while a successful load keeps its
            // `CMTime` (possibly indefinite) for 3.4 to map by value.
            let duration = try? await asset.load(.duration)
            return LoadedAudio(url: url, formatDescription: formatDescription, duration: duration)
        } catch {
            throw Self.globalError(from: error)
        }
    }

    /// Assembles `TechnicalProperties` from the per-field mappers. The audio stream basic description is
    /// extracted **once** here and shared by the structural mappers (`sampleRate`/`channelCount`), so the
    /// CoreMedia access is not duplicated. The remaining fields are still conservative placeholders (see
    /// the referenced tasks).
    func technicalProperties(from loaded: LoadedAudio) -> TechnicalProperties {
        let streamDescription = Self.streamBasicDescription(from: loaded.formatDescription)
        return TechnicalProperties(
            container: container(from: loaded.url),
            duration: duration(from: loaded.duration),
            sampleRate: sampleRate(from: streamDescription),
            channelCount: channelCount(from: streamDescription),
            bitDepth: bitDepth(from: loaded),
            codec: codec(from: streamDescription),
            declaredBitrate: declaredBitrate(from: loaded),
            estimatedBitrate: estimatedBitrate(from: loaded)
        )
    }
}

// MARK: - Audio stream basic description (shared by the structural mappers)

private extension AVFoundationAudioFilePropertyReader {
    /// Copies the `AudioStreamBasicDescription` out of a format description, or `nil` when the description
    /// is absent or carries no ASBD (e.g. no audio track was selected).
    ///
    /// The CoreMedia call returns a pointer valid only while the `CMFormatDescription` lives; it is
    /// dereferenced and **copied immediately** into a value here. No pointer is stored, retained, or
    /// escapes this function — only a value copy is returned. No force-unwrap, no AudioToolbox.
    static func streamBasicDescription(from formatDescription: CMFormatDescription?) -> AudioStreamBasicDescription? {
        guard let formatDescription else { return nil }
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
}

// MARK: - Per-field mappers (placeholders — completed by 3.3–3.5; conservative per ADR-0012/§12)

private extension AVFoundationAudioFilePropertyReader {
    /// `container` from the file's content type (`URLResourceValues.contentType`, a `UTType`).
    ///
    /// Spike 0031/F found **no direct real-container signal** among the evaluated AVFoundation/CoreMedia
    /// APIs (only the codec), and the content type is a *type/extension inference* that was provably wrong
    /// for a renamed file. So a resolved type is `uncertain` — carrying the stable, **non-localized** UTI
    /// identifier as the tentative value with a reason — **never `available`** on this evidence. No type
    /// resolvable → `unavailable`. A `resourceValues` read error (via `try?`) is conservatively folded
    /// into the same `unavailable` here — **not** because "no type" and "read error" are equivalent, but
    /// because distinguishing them into a per-property `failed` is task 3.6. No deep byte inspection; no
    /// deduction from MIME/codec/name; any resolved type (incl. a generic UTI) is carried as-is under
    /// `uncertain`, since the state already disclaims reliability (ADR-0012).
    func container(from url: URL) -> Property<String> {
        guard let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else {
            return .unavailable(reason: nil)
        }
        return .uncertain(
            value: contentType.identifier,
            reason: "Inferred from the file's type identifier; not verified against the container bytes."
        )
    }

    /// `duration` (seconds) from the already-loaded `CMTime` (no re-load, no second asset access).
    ///
    /// Conservative per spike 0031/E (a truncated file returned a valid+numeric `0.0`):
    /// - a **positive**, finite, numeric time → `available`;
    /// - **exactly zero** → `uncertain`, **keeping the observed `0` as the tentative value** (read but not
    ///   trustworthy — may be a genuinely empty file or a truncated read; the two are indistinguishable);
    /// - a **negative** time → `unavailable` (nonsensical/invalid — not a plausible tentative value);
    /// - `nil` (the load errored) or an invalid/indefinite/non-numeric/non-finite time → `unavailable`.
    /// Refining an errored load into a property-level `failed` is task 3.6.
    func duration(from time: CMTime?) -> Property<Double> {
        guard let time, time.isValid, time.isNumeric else { return .unavailable(reason: nil) }
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

    /// `sampleRate` (Hz) from the ASBD `mSampleRate`. Conservative: `available` only for a finite,
    /// strictly-positive value that is **exactly** an integer (the domain models Hz as `Int`, so no
    /// silent rounding). No ASBD, or a non-representable value → `unavailable` (task 3.6 owns the wider
    /// `uncertain`/`failed`/discrepancy policy; not reachable from a single already-loaded description).
    func sampleRate(from streamDescription: AudioStreamBasicDescription?) -> Property<Int> {
        guard let streamDescription else { return .unavailable(reason: nil) }
        let hertz = streamDescription.mSampleRate
        guard hertz.isFinite, hertz > 0, let value = Int(exactly: hertz) else {
            return .unavailable(reason: nil)
        }
        return .available(value)
    }

    /// `channelCount` from the ASBD `mChannelsPerFrame`. Conservative: `available` only for a
    /// strictly-positive count safely representable as the domain's `Int`. Never inferred from channel
    /// layouts, labels, or names. No ASBD, or a zero count → `unavailable`.
    func channelCount(from streamDescription: AudioStreamBasicDescription?) -> Property<Int> {
        guard let streamDescription else { return .unavailable(reason: nil) }
        let channels = streamDescription.mChannelsPerFrame
        guard channels > 0, let value = Int(exactly: channels) else {
            return .unavailable(reason: nil)
        }
        return .available(value)
    }

    func bitDepth(from _: LoadedAudio) -> Property<Int> {
        // TODO(3.5): PCM `mBitsPerChannel` → `available`; lossy → `unsupported`; never formula-inferred.
        .unavailable(reason: nil)
    }

    /// `codec` as a stable, non-localized token from the ASBD `mFormatID` (the decoded audio format —
    /// direct recognition, high confidence per spike 0031/C). Serialization follows the spike's policy
    /// (`fourCharCodeToken`). No ASBD, or a zero format id → `unavailable`. Container-vs-track discrepancy
    /// reconciliation is out of scope here (a later concern); a valid id maps directly to `available`.
    func codec(from streamDescription: AudioStreamBasicDescription?) -> Property<String> {
        guard let streamDescription, streamDescription.mFormatID != 0 else { return .unavailable(reason: nil) }
        return .available(Self.fourCharCodeToken(streamDescription.mFormatID))
    }

    func declaredBitrate(from _: LoadedAudio) -> Property<Int> {
        // TODO(3.5): only a directly declared nominal rate; otherwise `unavailable` (no self-computation).
        .unavailable(reason: nil)
    }

    func estimatedBitrate(from _: LoadedAudio) -> Property<Int> {
        // TODO(3.5): always `uncertain` with a `reason`; no bitrate computation in 3.2 (§15).
        .unavailable(reason: nil)
    }
}

// MARK: - Error conversion (skeleton — scope-based taxonomy is task 3.6, ADR-0011 §5)

private extension AVFoundationAudioFilePropertyReader {
    /// Converts a whole-file AVFoundation failure into a **global** domain error. The precise code
    /// selection (open vs unreadable vs access-denied, by scope/effect) is refined in 3.6; crucially, no
    /// `NSError`/`OSStatus`/`AVError` value crosses the port — only the stable domain code (ADR-0011 §5).
    static func globalError(from _: some Error) -> InspectionError {
        InspectionError(code: .fileOpenFailed, message: "The file could not be opened for inspection.")
    }
}
