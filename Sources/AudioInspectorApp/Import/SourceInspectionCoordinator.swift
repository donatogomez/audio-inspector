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

    private let chooseSource: SourceProvider
    private let makeReader: ReaderFactory

    /// - Parameters:
    ///   - chooseSource: how a destination file is obtained (the native open panel in production).
    ///   - makeReader: builds the reader for the selected URL. The default supplies the real
    ///     AVFoundation reader, resolving the URL through its constructor seam — the domain reference
    ///     carries no location, so the URL travels outside the domain (ADR-0010). A fresh reader per
    ///     inspection means no shared mutable state and no registry.
    init(
        chooseSource: @escaping SourceProvider,
        makeReader: @escaping ReaderFactory = { url in
            AVFoundationAudioFilePropertyReader { _ in url }
        }
    ) {
        self.chooseSource = chooseSource
        self.makeReader = makeReader
    }

    func inspect() async -> SourceInspectionOutcome {
        guard let url = await chooseSource() else {
            return .cancelled // dismissing the panel is neutral, never an error
        }
        // Filenames and paths are untrusted input: anything that is not a file cannot be inspected.
        guard url.isFileURL else {
            return .preparationFailed
        }

        // Access is held only for this operation and released on every exit path. A `false` result is
        // not an error: a URL that is not security-scoped stays readable, so only a granted scope is
        // balanced with a matching stop (ADR-0010).
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let reference = AudioFileReferenceMapper.reference(for: url)
        let useCase = InspectAudioFileUseCase(reader: makeReader(url))
        // `execute` never throws: a global read failure comes back as a report with `.failed` status.
        return .inspected(await useCase.execute(file: reference))
    }
}
