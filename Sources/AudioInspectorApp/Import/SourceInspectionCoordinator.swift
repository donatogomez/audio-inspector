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
    /// Receives the spectrogram once its generation has settled.
    ///
    /// Optional on purpose, and the switch that decides whether the work happens at all: until group 6
    /// carries the spectrogram beside the report, nothing consumes it, and generating a model only to
    /// drop it would be minutes of transform for nothing. A caller that wants one asks for one.
    typealias SpectrogramHandler = @MainActor (SpectrogramOutcome) -> Void

    private let chooseSource: SourceProvider
    private let makeReader: ReaderFactory
    private let makeWaveformGenerator: WaveformGeneratorFactory
    private let makeDecoder: DecoderFactory
    private let onSpectrogram: SpectrogramHandler?

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
        },
        onSpectrogram: SpectrogramHandler? = nil
    ) {
        self.chooseSource = chooseSource
        self.makeReader = makeReader
        self.makeWaveformGenerator = makeWaveformGenerator
        self.makeDecoder = makeDecoder
        self.onSpectrogram = onSpectrogram
    }

    /// The panel path: ask for a file, then inspect it.
    func inspect(onReport: InspectionReportHandler) async -> SourceInspectionOutcome {
        guard let url = await chooseSource() else {
            return .cancelled // dismissing the panel is neutral, never an error
        }
        return await inspect(url, onReport: onReport)
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
    /// works for the sake of something optional. `onReport` fires the moment it exists.
    ///
    /// The scope is acquired once and released once, covering the mapper, the property reader, the use
    /// case **and** the waveform: the `defer` below runs only after the sample read has finished, so
    /// the generator never needs a scope of its own (ADR-0010).
    func inspect(_ url: URL, onReport: InspectionReportHandler) async -> SourceInspectionOutcome {
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
        onReport(report)

        // Nothing could be read at all, so there is nothing to read samples from either. **Neither**
        // sample read starts: the report stands, and both visualisations are simply absent.
        if case .failed = report.status {
            onSpectrogram?(.unavailable)
            return .inspected(report, waveform: .unavailable)
        }

        let waveformOutcome = await waveform(for: reference, at: url)
        // The spectrogram is its **own** operation, run inside this same window: a separate decode, a
        // fresh accumulator, and no state shared with the waveform. Sequential here is not the same as
        // coupled — neither can cancel or fail the other, which is what ADR-0016 decision 15 requires.
        // Group 9 may or may not move the waveform onto the shared seam; until then two reads is a
        // declared cost, not an oversight.
        if let onSpectrogram {
            onSpectrogram(await spectrogram(for: reference, at: url))
        }
        return .inspected(report, waveform: waveformOutcome)
    }

    /// Produces the spectrogram inside the window the caller already holds.
    ///
    /// The `defer` that releases the scope runs when `inspect` returns, and this is awaited before
    /// that — so the decoder can open the file for as long as the read takes, and nothing survives the
    /// window (ADR-0010). A fresh decoder and a fresh accumulator per operation: nothing is retained
    /// between two inspections.
    private func spectrogram(for reference: AudioFileReference, at url: URL) async -> SpectrogramOutcome {
        await SpectrogramGeneration(decoder: makeDecoder(url)).run(for: reference)
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
