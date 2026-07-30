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

Every technical property in the result SHALL carry an explicit state from the set `available`,
`unavailable`, `unsupported`, `uncertain`, `failed`. The system MUST NOT invent a value when a
property is not available, and MUST NOT present an inference as a fact.

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

The system SHALL produce a structured report containing: the inspected file's identity (name,
extension, size in bytes, container/type, a sandbox-safe path representation, and modification date
labelled as file metadata), the technical properties with their states, a list of warnings for
unavailable/unsupported/uncertain/failed fields, and a global inspection status of `completed`,
`partial`, or `failed`.

#### Scenario: Partial inspection

- **WHEN** some properties are available and others are unavailable/unsupported
- **THEN** the report lists the available properties, emits warnings for the missing ones, and sets
  the global status to `partial`

#### Scenario: Global failure

- **WHEN** the file cannot be opened or read at all
- **THEN** the report sets the global status to `failed` with a message, contains no fabricated
  properties, and the app remains responsive

### Requirement: Represent the file with a sandbox-safe path

The report and any export SHALL represent the file by name/extension and a **sandbox-safe path
representation**, and MUST NOT include the user's absolute private path by default.

#### Scenario: Path representation in the result

- **WHEN** a report is produced for a selected file
- **THEN** the file is shown by its display name and a safe path representation, not the absolute
  `/Users/...` path

### Requirement: Export the report as schemaVersion 1 JSON

The system SHALL export the report as JSON following the `schemaVersion` 1 contract in
`docs/json-schema-v1.md`, including at least `schemaVersion`, `generatedAt`, `generator`,
`inspectedFile`, `technicalProperties`, `warnings`, and `inspectionStatus`. Property states in the
export SHALL distinguish absent, unsupported, uncertain, and extraction-error cases. Schema changes
SHALL be additive where possible; an incompatible change SHALL increment `schemaVersion`.

#### Scenario: Export produces versioned JSON

- **WHEN** the user exports a completed or partial inspection
- **THEN** the system writes a JSON document with `schemaVersion` = 1 and the required top-level
  fields, where each technical property carries its explicit state and no absolute private path is
  included by default
