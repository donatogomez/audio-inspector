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
determinable), codec/encoding (only when reliably determinable), and bitrate (declared, framework-estimated,
and/or calculated from file size and duration). **The extraction of these properties** MUST NOT process
samples: no technical property may be derived from decoded audio, and in particular none may be derived
from a spectral transform, a loudness measure, or a waveform.

This prohibition governs **how the technical properties are obtained**, not what the system as a whole
may do. Reading samples for a purpose other than deriving a technical property is outside its scope,
and any such reading MUST NOT alter which properties are reported, their values, their states, the
warnings, or the global inspection status.

A bitrate **calculated from the file's total size and its duration** SHALL be reported as a field
distinct from both the declared and the framework-estimated bitrate, and SHALL NEVER be reported as
`available`: it is always an approximation, because the file's total size includes container overhead
(headers, tags, embedded artwork) the calculation cannot separate from the audio payload. It SHALL be
computed only when both the file's size and a confirmed, positive duration are known, and SHALL be
absent (not fabricated, not zero) otherwise.

#### Scenario: Properties read from a well-formed file

- **WHEN** a well-formed audio file is inspected
- **THEN** the system reports the properties the format exposes (e.g. duration, sample rate, channel
  count) as measured facts, computed from metadata only

#### Scenario: Declared, estimated and calculated bitrate are three distinct facts

- **WHEN** bitrate information is available in any form
- **THEN** the system reports a declared bitrate, a framework-estimated bitrate, and a
  size/duration-calculated bitrate as **three separate** fields, never conflating any two of them

#### Scenario: A calculated bitrate is never presented as a declared or a reliable fact

- **WHEN** the system computes a bitrate from the file's size and duration
- **THEN** it is reported as an approximation, never as `available`, and the report does not claim it
  represents the audio payload's true encoded rate

#### Scenario: A calculated bitrate is absent when its inputs are absent

- **WHEN** the file's size cannot be read, or the duration is not a confirmed positive value
- **THEN** the calculated bitrate is reported as absent, never as zero and never as a fabricated number

#### Scenario: Sample processing elsewhere does not reach the properties

- **WHEN** the same file is inspected once with sample processing performed for another purpose and
  once without it
- **THEN** the technical properties, their states, the warnings and the global inspection status are
  identical in both cases

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

### Requirement: Present the report in human terms without interpreting quality

The system SHALL present the inspection report using vocabulary and formatting intended for a person, and
MUST NOT expose internal identifiers on its primary surface: enum case names, stable warning or error
codes, wire-format field keys, raw Uniform Type Identifiers, or codec tokens for which a comprehensible
name is known. Values that have a unit or a scale — byte counts, durations, sample rates, bitrates, dates
— SHALL be formatted for reading, while preserving the exact underlying value as secondary detail or in
the export, so no precision is lost. The system MUST NOT fabricate information while formatting: a label
may name only what the domain actually carries.

Presentation SHALL NOT interpret the quality of the audio. It may name a value and may state that a value
is absent, undefined for the format, unreliable or unreadable, but it MUST NOT characterise any value as
good, bad, better, worse, high or low, and MUST NOT imply that a larger number is preferable. Colour and
iconography SHALL communicate only the state of the inspection, never quality; in particular, a value
that is unreliable or not defined by the format SHALL NOT be presented as an error or a defect of the
file.

The presented report SHALL remain usable without sight of colour: no information may be conveyed by
colour alone, each property SHALL be reachable as a single coherent element by an assistive reader, and
the report SHALL remain legible at the system's accessibility text sizes.

This requirement governs presentation only. The properties read, their states, the warnings, the global
status, the safe origin descriptor and the exported JSON contract are unchanged by it.

#### Scenario: No internal identifier reaches the primary surface

- **WHEN** a report is presented for any file, whatever the outcome of the inspection
- **THEN** no enum case name, stable code, wire-format field key, raw Uniform Type Identifier, or
  known-nameable codec token appears as primary text

#### Scenario: Values are formatted for a reader

- **WHEN** a property carries a byte count, a duration, a sample rate, a bitrate or a date
- **THEN** it is presented in a readable form with its unit, and the exact underlying value remains
  available as secondary detail or in the export

#### Scenario: A technical token without a known name is shown unchanged

- **WHEN** a codec or container token has no comprehensible name available
- **THEN** the token is presented as it is, and no name is guessed for it

#### Scenario: Absence is presented without judgement

- **WHEN** a property is unavailable, not defined by the format, or unreliable
- **THEN** the report states which of those it is, in plain words, without presenting it as an error, a
  defect, or a statement about the quality of the file

#### Scenario: A failed reading is marked as a failure of the reading

- **WHEN** a property could not be read
- **THEN** the report says so and may mark it, always with words beside any colour or symbol, without
  implying a defect of the file

#### Scenario: Presentation never judges quality

- **WHEN** any value, state, warning or status is presented
- **THEN** no text, colour or symbol characterises it as good, bad, better, worse, high or low, and none
  implies that a larger value is preferable

#### Scenario: The report is reachable without colour or sight

- **WHEN** the report is read with an assistive reader, or by a user who cannot distinguish colour
- **THEN** every property is exposed as one coherent element with its name, value and state, and no
  information depends on colour alone

