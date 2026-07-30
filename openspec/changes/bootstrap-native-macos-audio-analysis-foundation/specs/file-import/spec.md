## ADDED Requirements

### Requirement: Import a single audio file via drag-and-drop and file picker

The system SHALL allow the user to import a single audio file either by dragging it onto the app
window or by choosing it through the macOS file picker. Import SHALL use a security-scoped bookmark
and SHALL access the file read-only. The system MUST NOT modify the original file in any way.

#### Scenario: Import a supported file by drag-and-drop

- **WHEN** the user drops a single supported audio file (`.mp3`, `.wav`, `.aiff`, `.flac`,
  `.m4a`/ALAC, `.m4a`/AAC) onto the window
- **THEN** the system creates a security-scoped bookmark, opens the file read-only, and presents it
  as the current subject for analysis without altering the file's bytes or modification date

#### Scenario: Import via the file picker

- **WHEN** the user invokes the file picker and selects one supported audio file
- **THEN** the system imports it identically to the drag-and-drop path, using a security-scoped
  bookmark

#### Scenario: Reject an unsupported or non-audio file

- **WHEN** the user drops or picks a file whose type is not a supported audio format
- **THEN** the system declines to import it and shows a clear, non-technical message stating the
  format is unsupported, without crashing or partially importing

### Requirement: Treat file paths and names as untrusted input

The system SHALL treat file paths, names, and embedded metadata as untrusted data. It MUST NOT
interpolate paths into shell command strings; any subprocess invocation MUST pass arguments as a
separated argument vector.

#### Scenario: File with adversarial name is handled safely

- **WHEN** a file whose name contains shell metacharacters, spaces, or quotes is imported and later
  probed via an external process
- **THEN** the system passes the path as a discrete process argument (never via a shell string),
  and analysis proceeds without command injection or path misinterpretation

### Requirement: Gracefully handle a file that becomes unavailable

The system SHALL handle the case where an imported file is missing, moved, or unreadable at
analysis time without crashing.

#### Scenario: Bookmarked file is missing at analysis time

- **WHEN** analysis begins but the bookmarked file can no longer be resolved or opened
- **THEN** the system reports a clear, recoverable error for that file and remains responsive
