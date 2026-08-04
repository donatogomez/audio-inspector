import AudioInspectorDomain

/// Derives the default export file name from the report's **safe** display name only — never a path.
/// A local, minimal rule (not a general naming service): drop the source extension, add
/// `-inspection.json`, and fall back to `inspection.json` when no valid base remains.
enum SuggestedExportName {
    static func forReport(_ report: InspectionReport) -> String {
        make(fromDisplayName: report.file.displayName)
    }

    static func make(fromDisplayName displayName: String) -> String {
        var base = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Neutralize characters that could be read as a path separator (defensive; a displayName is a
        // name, but names are untrusted input).
        base.removeAll { $0 == "/" || $0 == ":" }
        base = strippingExtension(from: base).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "inspection.json" }
        return "\(base)-inspection.json"
    }

    /// Removes the last `.extension`, keeping earlier dots (e.g. `my.song.final.flac` → `my.song.final`).
    /// A leading dot is preserved (a dotfile has no extension to strip).
    private static func strippingExtension(from name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}
