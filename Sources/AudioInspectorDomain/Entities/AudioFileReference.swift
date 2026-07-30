import Foundation

/// A safe, **ephemeral** reference to a user-selected file within a single inspection flow.
///
/// It carries only descriptive metadata plus a safe `source`, and **never** a `URL`, `file://`
/// string, absolute path, security-scoped bookmark, security-scoped resource handle, `AVAsset`, or
/// any AppKit/sandbox type — the actual access handle stays in infrastructure (ADR-0010).
///
/// `id` is generated per inspection and implies **no** stable identity across sessions; it must not
/// be treated as a persistent key.
public struct AudioFileReference: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let fileExtension: String?
    /// File size in bytes, when known.
    public let sizeBytes: Int?
    /// File modification date — descriptive file metadata, not forensic evidence.
    public let modifiedAt: Date?
    public let source: AudioFileSource

    public init(
        id: UUID = UUID(),
        displayName: String,
        fileExtension: String?,
        sizeBytes: Int?,
        modifiedAt: Date?,
        source: AudioFileSource
    ) {
        self.id = id
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.source = source
    }
}
