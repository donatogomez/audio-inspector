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

    /// Assembles `TechnicalProperties` from the per-field mappers. Field mapping is deferred: every
    /// mapper currently returns a conservative placeholder (see the referenced tasks).
    func technicalProperties(from loaded: LoadedAudio) -> TechnicalProperties {
        TechnicalProperties(
            container: container(from: loaded),
            duration: duration(from: loaded),
            sampleRate: sampleRate(from: loaded),
            channelCount: channelCount(from: loaded),
            bitDepth: bitDepth(from: loaded),
            codec: codec(from: loaded),
            declaredBitrate: declaredBitrate(from: loaded),
            estimatedBitrate: estimatedBitrate(from: loaded)
        )
    }
}

// MARK: - Per-field mappers (placeholders — completed by 3.3–3.5; conservative per ADR-0012/§12)

private extension AVFoundationAudioFilePropertyReader {
    func container(from _: LoadedAudio) -> Property<String> {
        // TODO(3.4): infer from UTI/extension → `uncertain` (never `available`; spike 0031/F).
        .unavailable(reason: nil)
    }

    func duration(from _: LoadedAudio) -> Property<Double> {
        // TODO(3.4): positive finite numeric → `available`; `0.0` → `uncertain`/`unavailable` (spike 0031/E).
        .unavailable(reason: nil)
    }

    func sampleRate(from _: LoadedAudio) -> Property<Int> {
        // TODO(3.3): from the selected track's ASBD `mSampleRate`.
        .unavailable(reason: nil)
    }

    func channelCount(from _: LoadedAudio) -> Property<Int> {
        // TODO(3.3): from the selected track's ASBD `mChannelsPerFrame`.
        .unavailable(reason: nil)
    }

    func bitDepth(from _: LoadedAudio) -> Property<Int> {
        // TODO(3.5): PCM `mBitsPerChannel` → `available`; lossy → `unsupported`; never formula-inferred.
        .unavailable(reason: nil)
    }

    func codec(from _: LoadedAudio) -> Property<String> {
        // TODO(3.4): stable non-localized FourCC token from the ASBD `mFormatID`.
        .unavailable(reason: nil)
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
