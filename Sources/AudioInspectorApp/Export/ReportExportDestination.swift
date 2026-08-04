import AppKit
import Foundation
import UniformTypeIdentifiers

/// The **only** place `NSSavePanel` is touched — AppKit is confined here, inside the composition
/// root. Presents a save panel for a single JSON destination and returns the user's chosen `URL`, or
/// `nil` on cancellation (**not** an error). No bookmark is created and nothing is persisted: the
/// returned URL is used once, immediately, by the caller.
///
/// The native callback API is wrapped in a checked continuation to expose an `async` surface (per the
/// group's decision, `begin` rather than `runModal()`).
@MainActor
enum ReportExportDestination {
    static func choose(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }
}
