/// Reads a file's decoded PCM once, in bounded chunks, handing each to the caller as it is read.
///
/// A domain **port**: the implementation lives in infrastructure (`AudioInspectorMedia`), opens the
/// file with the platform's own APIs and translates everything into the domain's value types, so no
/// media framework ever leaks inward (ADR-0011). The reference carries no location — the real access
/// handle stays in infrastructure (ADR-0010) — so the adapter receives the file's URL through its own
/// constructor seam, never through this port.
///
/// ## Why a synchronous callback rather than a stream
///
/// The whole read happens inside **one** `async` call, and `receive` is synchronous, non-escaping and
/// never suspends. That is not a stylistic preference; it is what keeps two guarantees true:
///
/// - **The security-scoped window.** `SourceInspectionCoordinator` acquires access and releases it in a
///   `defer` when it returns (ADR-0010). An `AsyncSequence` would let a consumer iterate *after* that
///   window had closed — a fault that would appear only under the sandbox, and only sometimes. Here it
///   cannot happen: the decode finishes before the call returns.
/// - **Bounded memory.** Nothing accumulates. The decoded track is never held in full, and peak memory
///   is a function of the chunk size, never of the file's duration.
///
/// ## Two consumers, two operations
///
/// More than one analysis reads the same audio — the amplitude envelope and the spectrogram — and each
/// runs as its **own** operation with its **own** cancellation. Nothing here couples them: cancelling
/// one must not cancel the other, and no consumer may depend on another having been requested. A single
/// shared pass producing several results was considered and rejected in ADR-0016; if measurement ever
/// justifies one, it can be built *on top of* this port rather than by changing it.
///
/// ## Three outcomes, and they must stay apart
///
/// - a **description with a frame count of zero** — the file opened and holds no audio. A complete
///   answer, not a missing one;
/// - **`nil`** — the file exposed no usable total frame count, so there was nothing to size an analysis
///   against. An absence caused by the file, not an error;
/// - a thrown **`AudioDecodingError`** — decoding went wrong, *or* the caller cancelled
///   (`AudioDecodingErrorCode.cancelled`). Cancellation is deliberately **not** `nil`: it is something
///   the caller did, and reporting it as an absence would tell them their file lacks something it does
///   not.
/// ## The description arrives *with* the first chunk, not only at the end
///
/// `decode` still returns the description, because a file with no audio delivers no chunk and must
/// still be described. But every chunk is handed over **together with** it, and that is not
/// convenience: a consumer that sizes anything — a grid, a reduction, a buffer — needs the stream's
/// shape *before* it sees the first sample, and returning it only at the end would leave that consumer
/// buffering the whole file or reading it twice. Passing it alongside each chunk also makes the mistake
/// unrepresentable: there is no way to receive audio without knowing what stream it came from.
public protocol AudioDecoding: Sendable {
    /// Decodes `file` once, calling `receive` with each chunk before the next is read.
    ///
    /// - Parameters:
    ///   - file: the safe reference. It carries no location; the adapter resolves that itself.
    ///   - chunkFrames: how many frames to read at a time. A hint, not a contract: an implementation may
    ///     deliver fewer at the end of the file, and **the result of any correct consumer must not
    ///     depend on this value**.
    ///   - receive: called on the decoding task, synchronously, once per chunk in file order, with the
    ///     stream the chunk came from. The description is the same value on every call and the same one
    ///     `decode` returns. Returning `.stop` ends the read normally rather than as a failure.
    /// - Returns: what the stream turned out to be, or `nil` when its total frame count is unusable.
    /// - Throws: `AudioDecodingError`, including on cancellation.
    func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription?
}
