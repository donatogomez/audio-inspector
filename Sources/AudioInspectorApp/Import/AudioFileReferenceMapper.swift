import AudioInspectorDomain
import Foundation

/// Builds the domain's safe file reference from a selected `URL` — the single place that translates a
/// location into the location-free `AudioFileReference` (ADR-0010). The absolute path never reaches
/// the domain type: only the display name, the extension, and two descriptive attributes do.
///
/// Descriptive metadata is **best-effort**: if the resource values cannot be read, `sizeBytes` and
/// `modifiedAt` are `nil` rather than fabricated, and the inspection continues. The use case already
/// turns those `nil`s into the stable `metadata_size_unavailable` / `metadata_modified_at_unavailable`
/// warnings (task 2.4), so nothing extra is derived here.
enum AudioFileReferenceMapper {
    static func reference(for url: URL) -> AudioFileReference {
        let displayName = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return AudioFileReference(
            displayName: displayName,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased(),
            sizeBytes: values?.fileSize,
            modifiedAt: values?.contentModificationDate,
            source: .userSelectedLocalFile(displayName: displayName, locationDisclosure: .omitted)
        )
    }
}
