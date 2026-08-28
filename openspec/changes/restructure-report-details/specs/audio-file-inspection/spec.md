## ADDED Requirements

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
