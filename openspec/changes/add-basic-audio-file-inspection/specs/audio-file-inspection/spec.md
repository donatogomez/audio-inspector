## ADDED Requirements

### Requirement: Select a single local audio file

The system SHALL let the user choose one local audio file through the native macOS file-open panel,
under App Sandbox, gaining user-granted access to that file for the duration of the inspection. The
system MUST NOT modify the file and MUST NOT require any entitlement beyond App Sandbox plus the
user-selected read-only file access implied by the open panel.

#### Scenario: User picks a file

- **WHEN** the user selects a supported local audio file in the open panel
- **THEN** the system obtains read access to that file for the inspection and begins reading its
  basic properties, without modifying the file

#### Scenario: User cancels selection

- **WHEN** the user dismisses the open panel without choosing a file
- **THEN** no inspection starts and the app remains in its prior state

### Requirement: Read basic technical properties without DSP

The system SHALL read only metadata-level technical properties that do not require sample
processing: container/type, duration, sample rate, channel count, bit depth (only when reliably
determinable), codec/encoding (only when reliably determinable), and bitrate (declared and/or
estimated). It MUST NOT perform any DSP (no decoding-for-analysis, FFT, loudness, waveform, etc.).

#### Scenario: Properties read from a well-formed file

- **WHEN** a well-formed audio file is inspected
- **THEN** the system reports the properties the format exposes (e.g. duration, sample rate, channel
  count) as measured facts, computed from metadata only

#### Scenario: Declared vs estimated bitrate are distinct

- **WHEN** bitrate information is available
- **THEN** the system reports a declared bitrate and an estimated bitrate as **separate** fields,
  never conflating the two

### Requirement: Represent each property's availability and certainty explicitly

Every technical property in the result SHALL carry an explicit state from the exhaustive set
`available` (value required), `unavailable`, `unsupported`, `uncertain` (reason required), `failed`
(stable `code` + message). Invalid combinations (e.g. a value with `unsupported`) SHALL be
unrepresentable. The system MUST NOT invent a value when a property is not available, and MUST NOT
present an inference as a fact.

#### Scenario: A property the format does not expose

- **WHEN** a format does not expose bit depth (e.g. a lossy codec)
- **THEN** that property is reported with state `unsupported` (or `unavailable`) and no fabricated
  numeric value

#### Scenario: A property that cannot be trusted

- **WHEN** a property can be read but is not reliable
- **THEN** it is reported with state `uncertain`, optionally with the tentative value and a note

#### Scenario: A property whose extraction errors

- **WHEN** reading a specific property throws or fails
- **THEN** that property is reported with state `failed` while the rest of the inspection continues

### Requirement: Produce a structured inspection report with warnings and a global status

The system SHALL produce a structured report containing: the inspected file's descriptive metadata
(name, extension, size in bytes, modification date labelled as file metadata, and a safe `source`
descriptor), the technical properties with their states (**including `container` as a technical
property**, not as file metadata), a list of warnings — each with a stable `code` — for
unavailable/unsupported/uncertain/failed fields, and a global inspection status of `completed`,
`partial`, or `failed` (a global failure carries a stable `error.code`).

#### Scenario: Partial inspection

- **WHEN** some properties are available and others are unavailable/unsupported
- **THEN** the report lists the available properties, emits warnings for the missing ones, and sets
  the global status to `partial`

#### Scenario: Global failure

- **WHEN** the file cannot be opened or read at all
- **THEN** the report sets the global status to `failed` with a message, contains no fabricated
  properties, and the app remains responsive

### Requirement: Represent the file origin safely (no location disclosure)

The report and any export SHALL represent the file origin with a safe `source` descriptor —
`kind = userSelectedLocalFile`, a `displayName`, and `locationDisclosure = omitted` — and MUST NOT
include, by default, the absolute path, a `file://` URL, a security-scoped bookmark, sandbox-internal
identifiers, or the parent directory name. There is no `path` field.

#### Scenario: Source representation in the export

- **WHEN** a report is exported for a selected file
- **THEN** the export contains a `source` object with `kind = userSelectedLocalFile`, the display
  name, and `locationDisclosure = omitted`, and contains no absolute path, `file://` URL, bookmark,
  or parent directory name

### Requirement: Export the report as schemaVersion 1 JSON

The system SHALL export the report as JSON following the canonical `schemaVersion` 1 contract in
`docs/json-schema-v1.md`. The envelope fields `schemaVersion`, `generatedAt`, and `generator` are
produced by the exporter (not the domain report). Each technical property SHALL be a flat object
`{ state, value, unit?, reason?, error? }` that distinguishes `unavailable`, `unsupported`,
`uncertain` (with a required `reason`), and `failed` (with a stable `error.code` and `message`).
Warnings SHALL carry a stable `code`; a global failure SHALL set `inspectionStatus.state = failed`
with a stable `error.code`. Schema changes SHALL be additive where possible; an incompatible change
SHALL increment `schemaVersion`.

#### Scenario: Export produces versioned JSON

- **WHEN** the user exports a completed or partial inspection
- **THEN** the system writes a JSON document with `schemaVersion` = 1, the envelope fields, and each
  technical property carrying its explicit `state` (and `reason`/`error` as applicable), with no
  absolute path or location disclosed by default

#### Scenario: Stable machine-processable codes

- **WHEN** a property is `failed` or a warning is emitted
- **THEN** the output includes a stable `code` (message text is descriptive only and not part of the
  code's identity), so results can be processed automatically
