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

### Requirement: Present one continuous surface until a report exists

Before any report is presented, the system SHALL present a **single surface** that states what the
application does, offers **exactly one** primary way to choose a file, and states that a file may be
dragged onto the window instead. The idle, running and failed conditions SHALL be states of that one
surface: the statement of purpose, the primary action and the drag-and-drop alternative SHALL be present
in **every** one of them, and SHALL NOT be replaced by a different surface as the state changes.

The surface SHALL offer no second action equivalent to the primary one, and SHALL NOT present a history,
a list of previously inspected files, a library, sample content, or any action that does not perform
work the system can actually do.

The primary action SHALL be operable without a pointer, and dragging SHALL NOT be the only way to reach
any behaviour this surface offers.

#### Scenario: The application is launched

- **WHEN** the application is launched and no file has been inspected
- **THEN** the surface states what the application does, offers one way to choose a file, and states that
  a file may be dragged onto the window

#### Scenario: The surface is the same surface in every pre-report state

- **WHEN** the surface is idle, is running an inspection, or is reporting that an inspection could not be
  started
- **THEN** the statement of purpose, the primary action and the drag-and-drop alternative are present in
  all three

#### Scenario: The primary action is reachable without a pointer

- **WHEN** the surface is presented and no pointer is used
- **THEN** the action that chooses a file can be reached and invoked from the keyboard, and it carries a
  label that names what it does

### Requirement: State that the source file is only read

The pre-report surface SHALL state, in words and in every one of its states, that the chosen file is
read and is not modified, moved or copied. The statement SHALL be present whether or not a file has been
chosen, and SHALL NOT be conditional on any state, hover, disclosure or scroll position.

This states a guarantee the system already keeps; it SHALL NOT be reworded into a promise about results,
safety, privacy or what an inspection will find.

#### Scenario: The guarantee is stated before anything is chosen

- **WHEN** the surface is idle
- **THEN** it states that the file is only read, and never modified, moved or copied

#### Scenario: The guarantee survives every pre-report state

- **WHEN** an inspection is running, or an inspection could not be started
- **THEN** the same statement is still present

### Requirement: Show that an inspection is running without claiming progress

While an inspection is running, the surface SHALL indicate that work is under way using an
**indeterminate** indicator and a statement in words. It MUST NOT state or imply a quantity the system
does not have: no percentage, no fraction, no completed or remaining count, no step number, no elapsed or
estimated time, and no named phase.

It MUST NOT name the file being inspected, because the running state also covers the moment before a file
has been chosen.

The primary action SHALL remain present and SHALL be unavailable while an inspection is running, rather
than being removed. A drop performed while an inspection is running SHALL be refused with the existing
message and SHALL NOT start a second inspection.

The surface SHALL NOT offer to cancel an inspection unless the system can actually stop one.

#### Scenario: An inspection is running

- **WHEN** an inspection has been started and no result has arrived
- **THEN** the surface states in words that an inspection is under way, shows an indeterminate indicator,
  and states no percentage, count, step or time

#### Scenario: The running state names no file

- **WHEN** an inspection is running
- **THEN** the surface names no file, because a file may not have been chosen yet

#### Scenario: The primary action stays put while an inspection runs

- **WHEN** an inspection is running
- **THEN** the action that chooses a file is still present and is unavailable, rather than removed

#### Scenario: A drop while an inspection is running

- **WHEN** an item is dropped while an inspection is running
- **THEN** the surface states that the current inspection must finish, and no second inspection starts

### Requirement: Keep a way forward when an inspection cannot be started

When a selection cannot be turned into an inspection at all, the surface SHALL present the system's own
message for that failure, unaltered, and SHALL keep a way forward available: choosing another file
through the primary action, or dragging one onto the window.

The failure SHALL be conveyed **in words**, and colour alone SHALL NOT be what distinguishes it from
ordinary text. The failure SHALL NOT be presented as a report, SHALL NOT be attributed to the reader, and
SHALL NOT disclose a path, a URL or a framework error.

An action SHALL NOT be labelled as retrying, repeating or re-running the failed selection, because the
system retains nothing about it; an action that opens the file chooser SHALL be named for choosing a
file.

#### Scenario: An inspection could not be started

- **WHEN** a selection cannot be turned into an inspection
- **THEN** the surface presents the system's message for it, marks it as a failure by more than colour,
  and still offers a way to choose another file

#### Scenario: Recovering after a failure

- **WHEN** a failure is shown and the reader chooses another file that inspects successfully
- **THEN** the report is presented and no trace of the failure remains

#### Scenario: Dragging after a failure

- **WHEN** a failure is shown and one valid local audio file is dropped onto the window
- **THEN** a new inspection starts, exactly as it would from the idle state

#### Scenario: No action claims to retry the failed selection

- **WHEN** a failure is shown
- **THEN** no action on the surface is named as retrying, repeating or re-running the selection that
  failed

### Requirement: The pre-report surface is not part of the report's navigation

The surface presented before a report SHALL NOT be a section of the report workspace, SHALL NOT appear in
the workspace's section navigation, and SHALL NOT be selectable as one. The workspace's section
navigation SHALL NOT be presented while no report exists.

When an inspection produces a report, the pre-report surface SHALL be replaced by the report workspace,
and the section the workspace then presents SHALL be decided by the workspace's own rule and by nothing
this surface does.

#### Scenario: No section navigation before a report

- **WHEN** no report is presented
- **THEN** the workspace's section navigation is not presented, and the pre-report surface is not one of
  its sections

#### Scenario: A report replaces the surface

- **WHEN** an inspection produces a report
- **THEN** the pre-report surface is no longer presented, the report workspace is, and the selected
  section is the one the workspace's own rule chooses

#### Scenario: The section list is unchanged by this surface

- **WHEN** the application is built
- **THEN** the workspace's sections are exactly the five it already defines, and no case exists for an
  empty, idle, working or failed state

### Requirement: Present the report's secondary content as one section

The system SHALL present the report's **technical properties**, the **file's own identity**, the
**notes**, and the **result of the reading** together, as one section of the inspection workspace,
reachable by selecting that section and not by scrolling past unrelated content.

That section SHALL be the only place those four bodies of content are presented while it is selected:
they SHALL NOT also appear elsewhere on screen at the same time.

The technical properties SHALL keep the grouping the report already gives them — what the file **is**,
and how it is **encoded** — and that grouping SHALL be legible as a distinction rather than presented as
two unrelated lists.

#### Scenario: The section is selected

- **WHEN** the reader selects the report's details section
- **THEN** the technical properties, the file's identity, the notes and the result of the reading are
  presented together

#### Scenario: The content has one place at a time

- **WHEN** the details section is selected
- **THEN** the technical properties, the file's identity, the notes and the result are not also
  presented anywhere else on screen

#### Scenario: The property grouping is the report's own

- **WHEN** the technical properties are presented
- **THEN** they appear in the groups the report already assigns them to, each property in exactly one
  group, and no property is dropped or moved between groups by the presentation

### Requirement: Lose no fact in re-presenting the report

Re-presenting the report's secondary content SHALL NOT change what it says. Every property name, every
value with its unit, every statement that a value is absent, undefined for the format, unreliable or
unreadable, every note, and the result sentence SHALL be exactly what the report produces.

A property with no value SHALL be shown as having none, and MUST NOT be shown as zero, empty, or as any
substitute figure. A property whose reading **failed** SHALL remain distinguishable from one the file
simply does not carry.

The certainty or availability of a property SHALL be presented **in words**, and colour or a symbol alone
SHALL NOT be what conveys it.

#### Scenario: A property the file does not carry

- **WHEN** a property is absent from the file
- **THEN** the section states that it is absent, and shows no number in its place

#### Scenario: A property that could not be read

- **WHEN** reading a property failed
- **THEN** the section says so, in words, and that statement is distinguishable from a property the
  format does not define

#### Scenario: Every property the report carries is presented

- **WHEN** the section is presented for any report
- **THEN** every property the report produces appears exactly once, with the value, the unit and the
  certainty the report gives it

### Requirement: Present the file's identity without disclosing its location

The section SHALL present the file's identifying facts — its name, its extension, its size, and when it
was last modified — where the report carries them, and SHALL describe where the file came from in the
terms the report already uses.

It MUST NOT present an absolute path, a URL, a parent directory, a security-scoped bookmark, or any other
form of the file's location.

#### Scenario: The file's identity is presented

- **WHEN** the section is presented
- **THEN** the file's name and whichever of its extension, size and modified date the report carries are
  shown

#### Scenario: No location is disclosed

- **WHEN** the file's origin is described
- **THEN** the description names the kind of selection and states that the location is omitted, and no
  path, URL or directory appears anywhere in the section

### Requirement: Keep notes and the result apart from the facts

Notes SHALL be presented with the words and the state the report gives them, and SHALL be absent from the
section entirely when the report carries none. A note MUST NOT be counted, scored, ranked by severity, or
summarised into a total.

The result of the reading SHALL be presented as a statement **about the reading** and SHALL be
distinguishable from the properties it is not one of. It MUST NOT be turned into a verdict about the
file: no score, no grade, no quality claim, and no statement about the file's origin, master, remaster,
transcode or upsampling.

#### Scenario: A report with no notes

- **WHEN** the report carries no notes
- **THEN** the section presents no notes area at all, and states no count of them

#### Scenario: Notes are presented as they are

- **WHEN** the report carries notes
- **THEN** each is presented with its own words and its own state, and nothing counts, scores or ranks
  them

#### Scenario: The result is about the reading

- **WHEN** the result of the reading is presented
- **THEN** it states what became of the reading, is distinguishable from the properties, and characterises
  neither the file nor its quality

### Requirement: Filling a section changes no navigation

Giving a section its content SHALL NOT change how sections are selected, how many there are, or what
moves the reader between them. The sections SHALL remain exactly those the workspace already defines, and
the selection SHALL continue to be moved only by what already moves it.

#### Scenario: The workspace's sections are unchanged

- **WHEN** the application is built
- **THEN** the workspace defines exactly the sections it defined before, and no section is added for the
  content of another

#### Scenario: Selecting the section moves nothing else

- **WHEN** the reader selects the details section and then selects another
- **THEN** no inspection is started, no result is recomputed, and nothing about the report changes

### Requirement: Present the measurements derived from the samples as one section

The system SHALL present the four measurements it derives from a file's decoded samples — the
**sample-level signal metrics**, the **true peak**, the **integrated loudness** and the **programme
bandwidth** — together, as one section of the inspection workspace, reachable by selecting that section
and not by scrolling past unrelated content.

That section SHALL be the only place those four measurements are presented while it is selected: they
SHALL NOT also appear elsewhere on screen at the same time.

The four SHALL be presented in the order the report already presents them, and SHALL be grouped by the
kind of quantity they measure — those describing the signal's **level** apart from the one describing
its **frequency** content — so that the distinction is legible rather than implied by position alone. A
group name SHALL name a physical quantity and SHALL NOT rank, score or characterise what it holds.

#### Scenario: The section is selected

- **WHEN** the reader selects the measurements section
- **THEN** the signal level metrics, the true peak, the integrated loudness and the programme bandwidth
  are presented together

#### Scenario: The measurements have one place at a time

- **WHEN** the measurements section is selected
- **THEN** those four measurements are not also presented anywhere else on screen

#### Scenario: The order and the grouping

- **WHEN** the measurements are presented
- **THEN** they appear in the order the report already gives them, each in exactly one group, and no
  measurement is dropped, duplicated or moved between groups by the presentation

### Requirement: Lose no measured fact in re-presenting the measurements

Re-presenting the measurements SHALL NOT change what they say. Every measurement name, every value with
the unit and the precision the measurement is qualified to, every per-channel breakdown, every statement
that a value is absent or not computable, and every sentence describing a failure to measure SHALL be
exactly what the report produces.

A measurement with no value SHALL be shown as having none, in words, and MUST NOT be shown as zero, as a
floor, as a threshold, or as any substituted figure. A measurement whose reading **failed** SHALL remain
distinguishable from one that could not be computed and from one the file offers nothing to measure. A
measurement still being produced SHALL say so, and SHALL NOT be presented as absent.

A count that is genuinely defined SHALL remain a number even where sibling values are not computable.

The unit SHALL travel with the value it belongs to, and a value SHALL NOT be presented under another
measurement's unit.

#### Scenario: A measurement that could not be computed

- **WHEN** a measurement has no value for a file
- **THEN** the section states that in words, and shows no number, zero or floor value in its place

#### Scenario: A failed measurement is distinguishable from an absent one

- **WHEN** measuring did not succeed
- **THEN** the section says so, and that statement is distinguishable from a measurement that was simply
  not computable for this file

#### Scenario: A measurement still being produced

- **WHEN** a measurement has not settled
- **THEN** the section says it is being prepared, and does not present it as absent or as failed

#### Scenario: A defined count beside values that are not computable

- **WHEN** a file offers no audio frames, so its per-sample values are not computable
- **THEN** the count of samples at or beyond full scale is still presented as its own defined number

#### Scenario: Units are preserved exactly

- **WHEN** the values are presented
- **THEN** each carries the unit its own measurement is quoted in, and no value appears under the unit of
  another measurement

### Requirement: Keep each measurement's method reachable without letting it crowd the facts

The system SHALL present, for every measurement that records one, the sentence describing how the
measurement was produced. That sentence MAY be presented behind a disclosure that a reader opens, and
SHALL then remain within the measurement it belongs to, reachable in a single action and reachable by an
assistive reader.

A value, its unit, its per-channel breakdown, a statement of absence, a statement of failure, and the
resolution a value is quantised to SHALL NOT be placed behind a disclosure.

The frequency resolution of the programme bandwidth SHALL remain presented as a quantity of its own,
beside the value, and SHALL NOT be rendered as an uncertainty, an error bar or a tolerance on that
value.

#### Scenario: The method is reachable

- **WHEN** a measurement that records a method is presented
- **THEN** the sentence describing that method is present in the section and reachable by the reader,
  whether or not it is shown expanded

#### Scenario: Facts are never behind the disclosure

- **WHEN** a measurement is presented with its method collapsed
- **THEN** its value, its unit, its per-channel detail and any statement of absence or failure are all
  still visible

#### Scenario: The bandwidth's resolution stays a quantity

- **WHEN** the programme bandwidth is presented with a reading
- **THEN** the resolution the reading sits on is presented as its own named quantity, and no operator
  joins it to the value as a tolerance

### Requirement: The measurements section states measured facts and no judgement

The section MUST NOT characterise any measurement as good, bad, safe, unsafe, high, low, hot, quiet,
loud, excessive, clipping, distorted, or as an indication of quality of any kind. It MUST NOT introduce a
threshold, a target, a delivery level, a platform, or a comparison against any of them.

Colour, weight, badge or icon SHALL NOT vary with the magnitude of a value. Only a failure of the
**reading** may be given emphasis, and it SHALL carry words that say so.

The section MUST NOT state or imply anything about the file's origin, master, remaster, transcode,
upsampling, codec or bitrate, and MUST NOT compare a bandwidth reading against the file's declared
sample rate.

The section MUST NOT publish a score, a grade, a count of differences, a similarity, a percentage, or any
other aggregate over the measurements — either directly, or by an absence that would mean one.

#### Scenario: A value beyond full scale is stated, not judged

- **WHEN** a measurement's value exceeds full scale
- **THEN** it is presented with its unit exactly as any other value is, with no colour, weight, badge or
  word that a value below full scale would not receive

#### Scenario: No target and no threshold

- **WHEN** the integrated loudness is presented
- **THEN** no delivery target, platform, recommendation or reference level appears beside it

#### Scenario: No aggregate over the four

- **WHEN** all four measurements are presented, in any combination of states
- **THEN** the section offers no total, score, count, percentage or single phrase summarising them

### Requirement: Filling the measurements section changes nothing beneath it

Giving the measurements section its content SHALL NOT start an inspection, read samples, decode audio,
run an analysis, or recompute a measurement. It SHALL present the measurements the inspection already
produced.

It SHALL NOT change the exported document, its schema, the technical properties, the warnings, the global
status, or the drawings — and it SHALL NOT change how sections are selected, how many there are, or what
moves the reader between them.

The comparison of two files SHALL be unchanged by this section: its semantics, its wording and its place
are exactly what they were, and the section SHALL introduce no comparison surface, no comparison value
and no difference of its own.

#### Scenario: Selecting the section computes nothing

- **WHEN** the reader selects the measurements section and then selects another
- **THEN** no decoder is created, no samples are read, no analysis is run, and no measurement changes

#### Scenario: The export is untouched

- **WHEN** a report is exported after the measurements section has been presented
- **THEN** the exported document and its schema version are exactly what they would have been

#### Scenario: The workspace's sections are unchanged

- **WHEN** the application is built
- **THEN** the workspace defines exactly the sections it defined before, and no section is added for the
  content of another

### Requirement: Present the file's amplitude drawing as one section with room for it

The system SHALL present the amplitude envelope drawn from the file's samples as one section of the
inspection workspace, reachable by selecting that section and not by scrolling past unrelated content.

That section SHALL be the only place the drawing appears while it is selected: it SHALL NOT also be
presented anywhere else on screen at the same time.

The drawing SHALL be given the vertical space the section can offer rather than a fixed strip: it SHALL
grow as the window grows, and SHALL retain a height at which it remains readable at the window's
smallest supported size. Where two files are paired, both lanes SHALL be given room on the same terms.

#### Scenario: The section is selected

- **WHEN** the reader selects the waveform section
- **THEN** the amplitude drawing for the file is presented, together with the words that describe it

#### Scenario: The drawing has one place at a time

- **WHEN** the waveform section is selected
- **THEN** the amplitude drawing is not also presented anywhere else on screen

#### Scenario: The drawing grows with the window

- **WHEN** the window is made taller
- **THEN** the drawing occupies more of the section's height, and the words describing it keep their own
  space rather than being displaced

### Requirement: Room for the drawing grants it no new powers

Giving the drawing more space SHALL NOT make it interactive. The section MUST NOT offer playback, a
playhead, zoom, panning, scrubbing, a cursor, selection, looping, transport controls, a hovered sample
readout, an interactive timestamp, alignment of one drawing to another, an overlay of two drawings, a
difference drawing, a correlation, a similarity, normalisation or gain matching, and pointer or scroll
activity over a drawing SHALL leave it and the data behind it unchanged.

The section SHALL NOT recompute the envelope, read the file's samples again, decode the file again, or
retain the decoded audio. It SHALL present what the inspection already produced.

It SHALL NOT change the exported document, its schema, the technical properties, the warnings, the
global status, or the measurements — and it SHALL NOT change how sections are selected, how many there
are, or what moves the reader between them.

#### Scenario: The larger drawing is still still

- **WHEN** the reader clicks, drags, scrolls or hovers over the drawing in the section
- **THEN** nothing is played, selected, zoomed, scrubbed, aligned or moved, and the drawing and its data
  are unchanged

#### Scenario: Selecting the section computes nothing

- **WHEN** the reader selects the waveform section and then selects another
- **THEN** no decoder is created, no samples are read, no envelope is produced again, and no analysis
  runs

#### Scenario: The export is untouched

- **WHEN** a report is exported after the waveform section has been presented
- **THEN** the exported document and its schema version are exactly what they would have been

#### Scenario: The workspace's sections are unchanged

- **WHEN** the application is built
- **THEN** the workspace defines exactly the sections it defined before, and no section is added for the
  content of another

### Requirement: State the drawing's absence in the section, never as empty space

The section SHALL state, in words and in the place the drawing would occupy, which of three situations
holds where no drawing exists for a file: it is still being produced, the samples offered nothing to
build one from, or producing it did not succeed.

The three SHALL remain distinguishable from one another, and none of them SHALL be presented as an empty
drawing, a flat line, a baseline or a zero.

#### Scenario: The drawing is still being produced

- **WHEN** the envelope has not settled
- **THEN** the section says it is being prepared, and does not present it as absent or as failed

#### Scenario: No drawing could be built

- **WHEN** the file offered nothing to build an envelope from
- **THEN** the section states that in words, and presents no drawing, no flat line and no empty area in
  its place

#### Scenario: Producing the drawing did not succeed

- **WHEN** producing the envelope failed
- **THEN** the section says so, and that statement is distinguishable from a file that simply has no
  envelope

### Requirement: Present the file's spectral drawing as one section with room for it

The system SHALL present the spectral model drawn from the file's samples as one section of the
inspection workspace, reachable by selecting that section and not by scrolling past unrelated content.

That section SHALL be the only place the spectral drawing appears while it is selected: it SHALL NOT
also be presented anywhere else on screen at the same time.

The drawing SHALL be given the vertical space the section can offer rather than a fixed strip: it SHALL
grow as the window grows, and SHALL retain at the window's smallest supported size a height no smaller
than the one it already had. Its growth SHALL be bounded by the resolution of the model itself, so that
the drawing is never enlarged past the detail it carries. Where two files are paired, both lanes SHALL
be given room on the same terms.

#### Scenario: The section is selected

- **WHEN** the reader selects the spectrum section
- **THEN** the spectral drawing for the file is presented, together with its axes, its legend and the
  words that describe it

#### Scenario: The drawing has one place at a time

- **WHEN** the spectrum section is selected
- **THEN** the spectral drawing is not also presented anywhere else on screen

#### Scenario: The drawing grows with the window, up to its own resolution

- **WHEN** the window is made taller
- **THEN** the drawing occupies more of the section's height, up to a bound derived from the number of
  frequency bands the model carries, and the words and legend describing it keep their own space

### Requirement: Room for the spectral drawing grants it no new powers

Giving the spectral drawing more space SHALL NOT make it interactive. The section MUST NOT offer
playback, zoom, panning, scrubbing, a cursor, selection, a hovered frequency or time readout, an
overlay of two drawings, a difference or subtraction of two models, alignment of one drawing to
another, a channel selector, or export of the drawing as an image; and pointer or scroll activity over
a drawing SHALL leave it and the data behind it unchanged.

The section SHALL NOT transform the samples again, read the file's samples again, decode the file
again, rebuild the model, or retain the decoded audio. Redrawing at a different size SHALL NOT
recompute anything.

The section MUST NOT change the exported document, its schema, the technical properties, the warnings,
the global status, the measurements or the amplitude drawing — and it SHALL NOT change how sections are
selected, how many there are, or what moves the reader between them.

#### Scenario: The larger drawing is still still

- **WHEN** the reader clicks, drags, scrolls or hovers over the spectral drawing in the section
- **THEN** nothing is played, selected, zoomed, scrubbed, aligned or read out, and the drawing and its
  data are unchanged

#### Scenario: Resizing recomputes nothing

- **WHEN** the window is resized while the spectrum section is selected
- **THEN** the existing model is redrawn at the new size, and the file is neither read nor transformed
  again

#### Scenario: Selecting the section computes nothing

- **WHEN** the reader selects the spectrum section and then selects another
- **THEN** no decoder is created, no samples are read, no transform runs, and no analysis runs

#### Scenario: The workspace's sections are unchanged

- **WHEN** the application is built
- **THEN** the workspace defines exactly the sections it defined before, and no section is added for the
  content of another

### Requirement: Keep the spectral drawing's scale absolute and explained wherever it is shown

The colours the section draws with SHALL be the same fixed scale, with the same floor, whichever file is
presented and however many are presented. The section MUST NOT normalise, auto-range, auto-contrast,
brighten, darken or re-colour a drawing relative to the file's own content, relative to another file, or
relative to the window it is drawn in.

Wherever a spectral drawing is presented, a legend stating the decibel range those colours represent
SHALL be presented with it. Where two files are presented together, **one** legend SHALL describe both,
and it SHALL state the same range it states for a single file.

#### Scenario: Two files of clearly different energy

- **WHEN** two spectral drawings are presented together
- **THEN** both use the same colour scale and the same floor, and neither is brightened or darkened
  towards the other

#### Scenario: One legend describes a pair

- **WHEN** two spectral drawings are presented together
- **THEN** a single legend states the decibel range, and it is the same range a single drawing is
  presented with

### Requirement: State the spectral drawing's absence in the section, never as empty space

The section SHALL state, in words and in the place the drawing would occupy, which of three situations
holds where no drawing exists for a file: it is still being produced, the samples offered nothing to
build one from, or producing it did not succeed.

The three SHALL remain distinguishable from one another, and none of them SHALL be presented as an empty
grid, as a region of the colour scale's floor, or as any drawn value.

#### Scenario: The drawing is still being produced

- **WHEN** the model has not settled
- **THEN** the section says it is being prepared, and does not present it as absent or as failed

#### Scenario: No model could be built

- **WHEN** the file offered nothing to build a model from
- **THEN** the section states that in words, and presents no grid and no region of the floor colour in
  its place

#### Scenario: Producing the model did not succeed

- **WHEN** producing the model failed
- **THEN** the section says so, and that statement is distinguishable from a file that simply has no
  model

