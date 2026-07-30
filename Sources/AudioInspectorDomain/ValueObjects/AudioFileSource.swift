/// Whether and how a file's location is disclosed in results/exports. Closed by design; for this
/// slice the location is always **omitted** — the app never discloses paths/URLs/bookmarks
/// (ADR-0010).
public enum LocationDisclosure: Sendable, Equatable {
    case omitted
}

/// A safe, closed representation of where an inspected file came from.
///
/// It deliberately models the origin as a small closed enum rather than a free-form dictionary, and
/// **never** carries an absolute path, `file://` URL, security-scoped bookmark, sandbox identifier,
/// or parent directory name (ADR-0010). For this slice, the only case is a user-selected local file.
public enum AudioFileSource: Sendable, Equatable {
    case userSelectedLocalFile(displayName: String, locationDisclosure: LocationDisclosure)
}
