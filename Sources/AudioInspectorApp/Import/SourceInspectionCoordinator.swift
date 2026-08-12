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
    /// Builds the port implementation that produces the waveform for the file at `url`.
    typealias WaveformGeneratorFactory = @Sendable (URL) -> any WaveformGenerating
    /// Builds the port implementation that decodes PCM for the file at `url`.
    typealias DecoderFactory = @Sendable (URL) -> any AudioDecoding

    private let chooseSource: SourceProvider
    private let makeReader: ReaderFactory
    private let makeWaveformGenerator: WaveformGeneratorFactory
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
        makeWaveformGenerator: @escaping WaveformGeneratorFactory = { url in
            AVFoundationWaveformGenerator(resolveURL: { _ in url })
        },
        makeDecoder: @escaping DecoderFactory = { url in
            AVFoundationAudioDecoder(resolveURL: { _ in url })
        }
    ) {
        self.chooseSource = chooseSource
        self.makeReader = makeReader
        self.makeWaveformGenerator = makeWaveformGenerator
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
    /// then are the samples read for the waveform — **inside the same security-scoped window**.
    ///
    /// The order is deliberate. The report is complete on its own and metadata is far quicker to read
    /// than samples, so holding it back until the waveform is done would delay everything that already
    /// works for the sake of something optional. `onUpdate(.report(_:))` fires the moment it exists,
    /// and each visualisation follows as it settles.
    ///
    /// The scope is acquired once and released once, covering the mapper, the property reader, the use
    /// case **and both visualisations**: the `defer` below runs only after the last sample read has
    /// finished, so neither the generator nor the decoder needs a scope of its own (ADR-0010).
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

        // Nothing could be read at all, so there is nothing to read samples from either. **None** of
        // the three sample reads starts: the report stands, and all three are simply absent.
        if case .failed = report.status {
            onUpdate(.waveform(.unavailable))
            onUpdate(.spectrogram(.unavailable))
            onUpdate(.signalLevelMetrics(.unavailable))
            return .inspected(
                report, waveform: .unavailable, spectrogram: .unavailable, signalLevelMetrics: .unavailable
            )
        }

        // The waveform keeps its own read: it uses a different port, and its accumulator needs frame
        // position and throws where the shared consumers neither need nor do. Migrating it is a change
        // of its own (ADR-0016 left it deliberately undone), so this is a declared cost rather than an
        // oversight — and it is why an inspection reads the file twice rather than once.
        let waveformOutcome = await waveform(for: reference, at: url)
        onUpdate(.waveform(waveformOutcome))

        // **One read, several analyses.** The spectrogram and the signal level metrics used to decode
        // the file once each; they now share a single pass, because a redundant read of a compressed
        // file costs about a quarter of an inspection (ADR-0020,
        // `docs/spikes/2026-08-12-shared-pcm-analysis-architecture.md`).
        //
        // Nothing about what they *are* changed. Each still has its own accumulator, its own failure
        // and its own outcome, each is still emitted as its own update, and one failing leaves the
        // other exactly as it would have been — which is the independence ADR-0016 protects, now held
        // by construction rather than by separate decoders.
        let shared = await sharedAnalyses(for: reference, at: url)
        onUpdate(.spectrogram(shared.spectrogram))
        onUpdate(.signalLevelMetrics(shared.signalLevelMetrics))

        return .inspected(
            report,
            waveform: waveformOutcome,
            spectrogram: shared.spectrogram,
            signalLevelMetrics: shared.signalLevelMetrics
        )
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

    /// Produces the waveform and translates its outcome, keeping the three meanings apart.
    private func waveform(for reference: AudioFileReference, at url: URL) async -> WaveformOutcome {
        do {
            guard let envelope = try await makeWaveformGenerator(url).makeWaveform(for: reference) else {
                // The file opened but offered nothing to size an envelope against — an absence, not a
                // failure, and never reported as one.
                return .unavailable
            }
            return .available(envelope)
        } catch {
            // Cancellation is the user replacing this operation, so it says nothing about the file and
            // must not be dressed up as a limitation of it.
            if error.code == .cancelled { return .cancelled }
            // Human, neutral, and carrying no path, no framework text and no stable code — those stay
            // where they are meaningful (ADR-0011).
            return .failed(message: "The waveform for this file could not be produced.")
        }
    }
}
