/// Produces a file's amplitude envelope from its decoded samples.
///
/// A domain **port**: the implementation lives in infrastructure (`AudioInspectorMedia`), reads the
/// samples with the platform's own APIs, and translates everything into the domain's value types, so
/// no media framework ever leaks inward (ADR-0011). The domain says *what* it needs; never *how*.
///
/// The reference carries no location — the real access handle stays in infrastructure (ADR-0010) — so
/// the adapter receives the file's URL through its own constructor seam, never through this port.
///
/// **The result is optional, and that is not the same as a failure.** `nil` means the file gave no
/// envelope for a reason that is not an error: it opened, but exposed no usable total frame count, so
/// there was nothing to size an envelope against. A thrown `WaveformError` means producing one went
/// wrong. Both are distinct again from an envelope with no buckets, which is the honest description of
/// a file that has no frames at all.
///
/// Whatever the outcome, it says nothing about the file's technical properties: a waveform that could
/// not be produced never becomes an inspection warning, never changes the inspection status, and never
/// reaches the `schemaVersion` 1 export (ADR-0009).
public protocol WaveformGenerating: Sendable {
    func makeWaveform(for file: AudioFileReference) async throws(WaveformError) -> WaveformEnvelope?
}
