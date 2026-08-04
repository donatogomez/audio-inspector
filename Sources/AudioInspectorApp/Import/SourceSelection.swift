import AppKit
import Foundation
import UniformTypeIdentifiers

/// The **only** place `NSOpenPanel` is touched — AppKit stays inside the composition root, mirroring
/// `ReportExportDestination`. Presents an open panel for a single audio file and returns the chosen
/// `URL`, or `nil` on cancellation (**not** an error). Nothing is persisted: no bookmark is created
/// and the URL is used once, immediately, by the caller (ADR-0010, ADR-0013).
///
/// `allowedContentTypes` is the `UTType.audio` supertype rather than a hand-written codec list: the
/// project has only validated PCM WAV/AIFF (spike 0031), so enumerating formats would assert support
/// the project has not proven. A file the reader cannot open surfaces honestly as an
/// `InspectionReport` with a `failed` status and a stable code, instead of being hidden from the user.
@MainActor
enum SourceSelection {
    static func choose() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }
}
