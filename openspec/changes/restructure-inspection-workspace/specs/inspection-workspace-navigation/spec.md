## ADDED Requirements

### Requirement: Present one file's inspection as five sections, and the same five in both modes

The system SHALL present an inspection as **five sections** — an overview, the measurements, the
waveform, the spectrum and the details — of which **exactly one** is selected at a time.

The same five SHALL exist whether or not a comparison is settled. A comparison SHALL change what a
section **contains**, and SHALL NOT add, remove, reorder or rename a section. A section whose artefact is
absent or failed SHALL remain reachable and SHALL state that absence in words; an absent artefact MUST
NOT remove the section that would have shown it.

#### Scenario: An inspection is presented as five sections

- **WHEN** a report is presented for any file
- **THEN** the five sections are reachable and exactly one of them is selected

#### Scenario: A comparison changes content and not structure

- **WHEN** a comparison against a second file settles
- **THEN** the same five sections are reachable, in the same order and under the same names, and what
  they contain describes both files

#### Scenario: An absent artefact does not remove its section

- **WHEN** a file's envelope or spectral model is absent or failed
- **THEN** the section that would have shown it is still reachable, and states in words that it is not
  there

### Requirement: The selected section belongs to the surface, and to nothing below it

The selected section SHALL be **presentation state**. It SHALL NOT be part of the inspection's domain
values, of the flow that owns the inspection's lifecycle, of the comparison's state, or of anything
persisted.

No result SHALL be withheld, delayed or altered because of which section is selected, and the selection
SHALL NOT take part in deciding whether a result is current: an operation's own guards decide that, and
the selection belongs to no operation.

#### Scenario: The selection reaches nothing below the surface

- **WHEN** the application is built
- **THEN** no inspection value, no lifecycle state and no exported document names or carries the
  selected section

#### Scenario: An analysis settling does not move the reader

- **WHEN** any analysis settles, fails, or is reported absent while a section is selected
- **THEN** the selected section is unchanged

### Requirement: Only a new primary file moves the reader

The selected section SHALL return to the **overview** when a new primary file is inspected, and SHALL be
left **unchanged** by everything else — a comparison starting, a comparison becoming ready, a comparison
being dismissed or superseded, a second file failing to open, and an analysis of either file settling.

The selection SHALL NOT survive relaunching the application: a new launch SHALL begin at the overview,
and nothing about the previous session SHALL be restored.

#### Scenario: A new file starts at the overview

- **WHEN** a section other than the overview is selected and a new primary file is inspected
- **THEN** the overview is selected

#### Scenario: Starting a comparison leaves the reader where they are

- **WHEN** a comparison is requested while any section is selected
- **THEN** the same section stays selected while the comparison loads and after it settles

#### Scenario: Ending a comparison leaves the reader where they are

- **WHEN** a settled comparison is dismissed, superseded, or its file could not be opened
- **THEN** the same section stays selected, and its content returns to describing the primary file alone

#### Scenario: Nothing is restored on relaunch

- **WHEN** the application is launched
- **THEN** the overview is selected, and no section from a previous session is restored

### Requirement: State no aggregate over a comparison, by a value or by an absence

Where a surface introduces two files at once, it SHALL state **each file's own identity and facts** and
SHALL NOT state, imply or offer any aggregate over the comparison: no count of properties that agree,
differ or cannot be compared; no percentage, similarity, score or confidence; no verdict; no ordering by
importance; and no phrase meaning that the two files match.

It SHALL NOT present **a list of the properties that differ**, because such a list carries the same
aggregate whenever it is empty: an empty list of differences states that the two files agree, which is
the statement the system may not make.

Where the full comparison is reachable from such a surface, the way through SHALL be a means of
navigation and SHALL NOT describe what will be found there.

#### Scenario: Two files are introduced without being summarised

- **WHEN** a comparison is presented
- **THEN** each file's identity and its own facts are stated, and nothing counts, scores, ranks or
  summarises the relationship between them

#### Scenario: Two files whose comparable measurements all agree

- **WHEN** every comparable measurement of the two files agrees
- **THEN** no value, flag, phrase or empty region states or implies that the two files match

#### Scenario: The way through says nothing about what is behind it

- **WHEN** a surface offers access to the full comparison
- **THEN** that access names the destination and does not describe, count or characterise its contents
