import AudioInspectorDomain
import Foundation

/// Derives the default export file name from the report's **safe** display name only — never a path.
/// A local, minimal rule (not a general naming service): path-like separators become `-` (rather than
/// vanishing, which would fuse `01/02` into an ambiguous `0102`), runs of `-` collapse, the source
/// extension is dropped, and stray separators/dots at the edges are trimmed so the result is never a
/// hidden or degenerate name. No truncation, no Unicode normalization, no transliteration.
enum SuggestedExportName {
    static func forReport(_ report: InspectionReport) -> String {
        make(fromDisplayName: report.file.displayName)
    }

    static func make(fromDisplayName displayName: String) -> String {
        var base = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Separators become `-` so distinct segments stay distinguishable, then runs collapse.
        base = String(base.map { $0 == "/" || $0 == ":" ? "-" : $0 })
        base = collapsingHyphens(base)
        base = strippingExtension(from: base).trimmingCharacters(in: edgeNoise)
        // Empty, or nothing left but dots/separators/spaces → the deterministic fallback.
        guard !base.isEmpty else { return "inspection.json" }
        return "\(base)-inspection.json"
    }

    /// Characters that carry no meaning at either edge of a base name — trimming them prevents a
    /// leading dot (a hidden file) or a dangling separator.
    private static let edgeNoise = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-."))

    /// Collapses consecutive `-` into a single `-`.
    private static func collapsingHyphens(_ name: String) -> String {
        var result = ""
        for character in name where !(character == "-" && result.last == "-") {
            result.append(character)
        }
        return result
    }

    /// Removes the last `.extension`, keeping earlier dots (e.g. `my.song.final.flac` →
    /// `my.song.final`). A leading dot marks a dotfile with no extension, so nothing is stripped
    /// there; the edge trim then removes the dot itself.
    private static func strippingExtension(from name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}
