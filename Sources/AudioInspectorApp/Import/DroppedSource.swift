import FeatureImport
import Foundation
import UniformTypeIdentifiers

/// What the composition root decided about a dropped payload. `URL` never leaves this layer: the
/// feature only ever receives the `DropRejection`, or an opaque action already bound to the accepted
/// file (ADR-0010, ADR-0014).
enum DroppedSourceDecision: Equatable {
    case accepted(URL)
    case rejected(DropRejection)
}

/// The synchronous half of a drop: turn `[URL]` into one inspectable local file, or into a reason why
/// not. Pure and free of SwiftUI, so every branch is unit-testable without building a view.
///
/// It restores by code the guarantees `NSOpenPanel` gets by configuration — one item
/// (`allowsMultipleSelection = false`), a file rather than a folder (`canChooseDirectories = false`),
/// and an audio type (`allowedContentTypes = [.audio]`) — because a drop guarantees none of them.
enum DroppedSource {
    /// Checks are ordered by what the user most needs to be told. Being busy comes first: while an
    /// inspection runs nothing will be processed anyway, so "wait" is the honest message even if the
    /// payload is also malformed.
    ///
    /// **The audio check asks the system, never a list we wrote.** An item whose resolved content type
    /// does not conform to `UTType.audio` is refused; only when no type can be resolved at all does the
    /// item go through, leaving the decision to the reader. In practice the system types nearly
    /// everything — a file with no extension resolves to generic data and is therefore refused — which
    /// deliberately matches the panel, whose `allowedContentTypes = [.audio]` would not offer such a
    /// file either. The consequence is accepted knowingly: an extension-less audio file is refused by
    /// both entry points alike.
    ///
    /// This is a *routing* check, not a support claim. It filters by conformance rather than by a
    /// hand-written list of formats, and the reader with its honest `failed` states remains the source
    /// of truth about what can actually be inspected.
    static func evaluate(_ urls: [URL], isInspecting: Bool) -> DroppedSourceDecision {
        if isInspecting {
            return .rejected(.inspectionInProgress)
        }
        guard urls.count <= 1 else {
            return .rejected(.multipleItems) // never silently take the first
        }
        guard let url = urls.first, url.isFileURL else {
            return .rejected(.unsupportedItem) // nothing usable, or not a local file
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        if values?.isDirectory == true {
            return .rejected(.unsupportedItem)
        }
        if let contentType = values?.contentType, !contentType.conforms(to: .audio) {
            return .rejected(.unsupportedItem)
        }
        // No normalisation: a sandboxed observation found Finder delivers conventional path URLs whose
        // `filePathURL` is identical, so there is nothing to normalise (ADR-0014).
        return .accepted(url)
    }
}
