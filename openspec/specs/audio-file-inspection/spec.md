# audio-file-inspection Specification

## Purpose
TBD - created by archiving change add-basic-audio-file-inspection. Update Purpose after archive.
## Requirements
### Requirement: Select a single local audio file

The system SHALL let the user choose one local audio file through an **explicit user selection** —
either the native macOS file-open panel **or by dragging the file onto the app window** — under App
Sandbox, gaining user-granted access to that file for the duration of the inspection. **Exactly one
local file SHALL be accepted per operation**, and **both mechanisms SHALL converge on the same
inspection path and produce the same report for the same file**. The system MUST NOT modify the file.
It MUST NOT require any entitlement beyond App Sandbox plus the user-selected file access those
mechanisms imply — `com.apple.security.files.user-selected.read-write`, which one executable setting
applies to both the inspected file and the export destination (ADR-0013) — and MUST NOT use any
folder-wide or system-wide entitlement. Access SHALL be held only for the operation that needs it, and
the system MUST NOT persist any URL or create any security-scoped bookmark. The source file is treated
as read-only by the system's own APIs; the only file the system writes is the export destination the
user picks. A selection that cannot be turned into a single inspectable local file SHALL be rejected
without starting an inspection, without discarding any result already presented, and without disclosing
any path or URL.

#### Scenario: User picks a file in the open panel

- **WHEN** the user selects a supported local audio file in the open panel
- **THEN** the system obtains read access to that file for the inspection and begins reading its
  basic properties, without modifying the file

#### Scenario: User cancels selection

- **WHEN** the user dismisses the open panel without choosing a file
- **THEN** no inspection starts and the app remains in its prior state

#### Scenario: User drops a single audio file from the initial state

- **WHEN** no report is displayed and the user drops one local audio file onto the app window
- **THEN** the system obtains read access to that file, inspects it, and presents the resulting report,
  without modifying the file and without persisting its location

#### Scenario: User drops a single audio file while a report is displayed

- **WHEN** a report is displayed and the user drops one valid local audio file onto the app window
- **THEN** a new inspection starts and, on completion, the new report is presented

#### Scenario: User drops more than one item

- **WHEN** the user drops two or more items at once
- **THEN** the system rejects the whole drop, selects none of the items, starts no inspection, and
  states that a single audio file is expected

#### Scenario: User drops something that is not a single local file

- **WHEN** the dropped item is not a local file, or is a folder rather than a file
- **THEN** the system rejects it, starts no inspection, and shows a neutral, recoverable message that
  discloses no path or URL

#### Scenario: A rejected drop preserves the previous result

- **WHEN** a drop is rejected while a report is displayed
- **THEN** that report remains displayed, the rejection is not reported as an inspection failure, and
  the next accepted selection clears the rejection message

#### Scenario: User drops while an inspection is running

- **WHEN** an inspection is already in flight and another item is dropped
- **THEN** the drop does not start a second inspection, the running inspection is unaffected, and at
  most one inspection exists at any time

#### Scenario: Both mechanisms use the same inspection path

- **WHEN** the same file is inspected once through the open panel and once by dropping it
- **THEN** both produce the same report content and the same exported JSON, apart from the envelope
  fields the exporter generates per export

#### Scenario: Targeting feedback states what is expected

- **WHEN** a drag operation is over the app window and the dragged items are not yet delivered
- **THEN** the window indicates that it is the target of the operation and states that one audio file is
  expected, without asserting that the dragged content is valid

#### Scenario: Feature modules never receive a file location

- **WHEN** the source of the feature modules is inspected
- **THEN** no feature module uses the `URL` type or imports AppKit, and the selection mechanism reaches
  them only as an opaque action and safe visual state

#### Scenario: No new entitlement or bookmark is introduced

- **WHEN** a file is selected by either mechanism and inspected
- **THEN** the app declares only App Sandbox and `com.apple.security.files.user-selected.read-write`,
  creates no security-scoped bookmark, and retains no URL after the inspection completes

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

#### Scenario: A descriptive-metadata attribute is missing

- **WHEN** the inspected file's `sizeBytes` and/or `modifiedAt` is not available
- **THEN** the report emits the corresponding stable warning code(s) (`metadata_size_unavailable` /
  `metadata_modified_at_unavailable`); absent a global failure the global status is `partial`, and on a
  global failure the status remains `failed`

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

