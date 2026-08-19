import AudioInspectorDomain
import AudioInspectorMedia
import FeatureImport
import Foundation

/// Orchestrates one selection-and-inspection: ask for a file → hold security-scoped access → build the
/// safe reference → run the use case with the real reader → return the outcome. It owns no state and
/// keeps `URL`, AppKit, and the sandbox entirely inside `AudioInspectorApp`.
///
/// The file is opened **read-only**: nothing here (or in the reader) writes to, renames, moves, or
/// deletes it — the read-write entitlement exists only so the *export* destination can be written
/// (ADR-0013). No bookmark is created and no URL is persisted.
///
/// Two injected seams keep it unit-testable without opening a real panel: `chooseSource` (substituted
/// by a known URL) and `makeReader` (substituted by a fake port implementation).
@MainActor
struct SourceInspectionCoordinator {
    /// Returns the chosen file URL, or `nil` when the user cancels.
    typealias SourceProvider = @MainActor () async -> URL?
    /// Builds the port implementation that reads the file at `url`.
    typealias ReaderFactory = @Sendable (URL) -> any AudioFilePropertyReading
    /// Builds the port implementation that decodes PCM for the file at `url`.
    typealias DecoderFactory = @Sendable (URL) -> any AudioDecoding

    private let chooseSource: SourceProvider
    private let makeReader: ReaderFactory
    private let makeDecoder: DecoderFactory

    /// - Parameters:
    ///   - chooseSource: how a destination file is obtained (the native open panel in production).
    ///   - makeReader: builds the reader for the selected URL. The default supplies the real
    ///     AVFoundation reader, resolving the URL through its constructor seam — the domain reference
    ///     carries no location, so the URL travels outside the domain (ADR-0010). A fresh reader per
    ///     inspection means no shared mutable state and no registry.
    /// - Parameters:
    ///   - chooseSource: how the file is obtained. The panel supplies it for the
    ///     `Choose audio file…` path; the drop path already knows the URL and calls `inspect(_:)`
    ///     directly, so it leaves this at its default, which chooses nothing.
    init(
        chooseSource: @escaping SourceProvider = { nil },
        makeReader: @escaping ReaderFactory = { url in
            AVFoundationAudioFilePropertyReader { _ in url }
        },
        makeDecoder: @escaping DecoderFactory = { url in
            AVFoundationAudioDecoder(resolveURL: { _ in url })
        }
    ) {
        self.chooseSource = chooseSource
        self.makeReader = makeReader
        self.makeDecoder = makeDecoder
    }

    /// The panel path: ask for a file, then inspect it.
    func inspect(onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        guard let url = await chooseSource() else {
            return .cancelled // dismissing the panel is neutral, never an error
        }
        return await inspect(url, onUpdate: onUpdate)
    }

    /// The shared body, and the **only** owner of the `isFileURL` guard, the security scope, the
    /// mapper, the reader construction and the use case. Both entry points run exactly this: the panel
    /// after resolving its selection, the drop with the URL the composition root already accepted.
    /// There is no second pipeline.
    /// One selection, start to finish: the properties are read and handed back immediately, and only
    /// then are the samples read — **once**, inside the same security-scoped window.
    ///
    /// The order is deliberate. The report is complete on its own and metadata is far quicker to read
    /// than samples, so holding it back until an analysis is done would delay everything that already
    /// works for the sake of something optional. `onUpdate(.report(_:))` fires the moment it exists,
    /// and the five sample-based analyses follow.
    ///
    /// The scope is acquired once and released once, covering the mapper, the property reader, the use
    /// case **and the single sample read**: the `defer` below runs only after that read has finished, so
    /// the decoder needs no scope of its own (ADR-0010).
    func inspect(_ url: URL, onUpdate: InspectionUpdateHandler) async -> SourceInspectionOutcome {
        // Filenames and paths are untrusted input: anything that is not a file cannot be inspected.
        guard url.isFileURL else {
            return .preparationFailed
        }

        // Access is held only for this operation and released on every exit path. A `false` result is
        // not an error: a URL that is not security-scoped stays readable, so only a granted scope is
        // balanced with a matching stop (ADR-0010). A sandboxed observation confirmed this is exactly
        // what a dropped URL does — `start` returns `false` and the file reads fine (ADR-0014).
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let reference = AudioFileReferenceMapper.reference(for: url)
        let useCase = InspectAudioFileUseCase(reader: makeReader(url))
        // `execute` never throws: a global read failure comes back as a report with `.failed` status.
        let report = await useCase.execute(file: reference)
        onUpdate(.report(report))

        // Nothing could be read at all, so there is nothing to read samples from either. The read does
        // not start: the report stands, and all five analyses are simply absent.
        if case .failed = report.status {
            onUpdate(.waveform(.unavailable))
            onUpdate(.spectrogram(.unavailable))
            onUpdate(.signalLevelMetrics(.unavailable))
            onUpdate(.truePeak(.unavailable))
            onUpdate(.loudness(.unavailable))
            return .inspected(
                report, analyses: InspectionAnalyses(waveform: .unavailable,
                spectrogram: .unavailable,
                signalLevelMetrics: .unavailable,
                truePeak: .unavailable,
                loudness: .unavailable))
        }

        // **One read, every analysis.** The waveform, the spectrogram, the signal level metrics and the
        // true peak each used to mean a decode of their own; all four now share a single pass, because a
        // redundant read of a compressed file costs about a quarter of an inspection (ADR-0020, and
        // ADR-0021 for the waveform's own move).
        //
        // **The waveform was the last one holding a read of its own**, and losing it is what takes an
        // inspection from two reads to one. Nothing about what any analysis *is* changed: each still has
        // its own accumulator, its own failure and its own outcome, each is still emitted as its own
        // update in the order it always was, and one failing leaves the others exactly as they would
        // have been — the independence ADR-0016 protects, held by construction rather than by separate
        // decoders.
        //
        // **What did change is when the waveform arrives**, and it is worth stating rather than
        // discovering. It used to settle after its own read, before the shared pass had started; now it
        // settles with its three siblings when the one read finishes. The report is still emitted before
        // any sample is read — that is the ordering the spec protects — and no analysis waits on
        // another's *result*. They now share a producer, so they share its duration.
        let shared = await sharedAnalyses(for: reference, at: url)
        onUpdate(.waveform(shared.waveform))
        onUpdate(.spectrogram(shared.spectrogram))
        onUpdate(.signalLevelMetrics(shared.signalLevelMetrics))
        onUpdate(.truePeak(shared.truePeak))
        onUpdate(.loudness(shared.loudness))

        return .inspected(
            report, analyses: InspectionAnalyses(waveform: shared.waveform,
            spectrogram: shared.spectrogram,
            signalLevelMetrics: shared.signalLevelMetrics,
            truePeak: shared.truePeak,
            loudness: shared.loudness))
    }

    /// Produces every sample-based analysis from **one** read, inside the window the caller already
    /// holds.
    ///
    /// The `defer` that releases the scope runs when `inspect` returns, and this is awaited before
    /// that — so the decoder can open the file for as long as the read takes, and nothing survives the
    /// window (ADR-0010). One decoder and fresh accumulators per inspection: nothing is retained
    /// between two of them.
    ///
    /// `makeDecoder(url)` is called **once** here, where it used to be called once per analysis. That
    /// is the whole change, and it is why the returned outcomes are read apart immediately: nothing
    /// downstream is given a way to ask a question about the analyses together.
    private func sharedAnalyses(for reference: AudioFileReference, at url: URL) async -> SharedPCMAnalysisOutcome {
        await SharedPCMAnalysisGeneration(decoder: makeDecoder(url)).run(for: reference)
    }

}
