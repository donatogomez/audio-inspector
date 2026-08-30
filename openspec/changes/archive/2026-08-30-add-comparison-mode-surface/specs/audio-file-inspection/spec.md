## ADDED Requirements

### Requirement: Present a comparison as a mode of the same workspace

The system SHALL present a comparison of two files through the **same** workspace sections it presents
one file through. It SHALL NOT add a section for the comparison, a second navigation, a separate page or
a document of its own.

While a comparison exists, each section SHALL present the comparison of the content that section is
already about, and SHALL NOT present it as a block appended after that content.

The sections available to a reader SHALL be exactly the same, in the same order, whether or not a
comparison exists. Which section is selected SHALL NOT change because a comparison starts, becomes
ready, fails, is closed or is superseded.

#### Scenario: The sections are the same in both modes

- **WHEN** a comparison exists
- **THEN** the workspace offers exactly the sections it offers without one, in the same order, and none
  of them is named for the comparison

#### Scenario: A section presents its own comparison in place

- **WHEN** a reader selects a section while a comparison is ready
- **THEN** that section presents both files' values for the content it is about, in that section's own
  arrangement

#### Scenario: Starting a comparison does not move the reader

- **WHEN** a comparison starts, becomes ready, fails, is closed or is superseded
- **THEN** the selected section is the one the reader had selected before

### Requirement: State no aggregate over a comparison, by a value or by an absence

No surface SHALL publish a count, a score, a grade, a percentage, a similarity, a confidence, a total or
any other aggregate over a comparison — and SHALL NOT publish one by the **absence** of something either.

An element whose appearance or disappearance would tell a reader that the two files are alike is such an
aggregate. The system SHALL NOT offer a list filtered to what differs, an empty state whose emptiness
means agreement, a badge, colour, icon or highlight that is present only when something differs, or a
phrase meaning that the files match, are identical, are equivalent or agree.

Where every comparable value agrees, the surface SHALL present exactly the elements it presents where
none of them agrees.

#### Scenario: Two files whose comparable values all agree

- **WHEN** every comparable measurement and property of two files agrees
- **THEN** no value, flag, phrase, badge, colour or icon states or implies that they match
- **AND** the surface presents the same elements it would present for two files that agree about nothing

#### Scenario: Nothing about the two files is comparable

- **WHEN** no measurement of two files can be compared
- **THEN** each measurement states its own reason in its own place
- **AND** no surface states a total, a proportion or a single phrase about how much was comparable

#### Scenario: No list is filtered to what differs

- **WHEN** the comparison is presented
- **THEN** every row the comparison covers is present whatever its outcome, and no view offers only the
  rows that differ

### Requirement: Present the two files' identities without comparing them

The overview of a comparison SHALL present the identifying facts of **each** file — its name, and
whichever of its extension, size and modified date the report carries — under a label naming its
position, and SHALL state in words that the sections carry both files.

That overview MUST NOT present a technical property, a measurement, an outcome, a note, a count of notes,
the result of either reading, or any comparison of any of them. It MUST NOT present a path, a URL, a
parent directory or a bookmark for either file.

#### Scenario: Both identities are presented

- **WHEN** a comparison is ready
- **THEN** the overview presents each file's name and whichever identifying facts its report carries,
  each under the label naming its position

#### Scenario: The overview compares nothing

- **WHEN** the overview of a comparison is presented for any pair of files
- **THEN** it states no outcome, no difference, no measurement, no note, no count and no result

### Requirement: Present each file's notes without counting or summarising them

Where a surface presents the notes of a file being compared, it SHALL present them in the words and the
state the report gives them, for that file alone.

It MUST NOT state how many notes a file carries, summarise them into a total, rank them by severity, or
replace a count with a badge, an icon, a pluralised phrase or any other token that varies with how many
there are. It MUST NOT set one file's notes against the other's.

#### Scenario: A file's notes are presented while comparing

- **WHEN** a file being compared carries notes
- **THEN** each note is presented with its own words and its own state, and no number, badge or icon
  states how many there are

#### Scenario: Notes are never set against each other

- **WHEN** both files carry notes
- **THEN** neither file's notes are described relative to the other's, and no surface states that one has
  more, fewer, worse or better ones

### Requirement: Present each reading's result without comparing the two

Where a surface presents the result of a reading while two files are being compared, it SHALL present
each file's own result, as a statement about that file's reading.

It MUST NOT compare the two results, combine them, or derive a result of the comparison. A reading is not
a property of the audio, and an outcome over two readings would be a verdict about the readings rather
than a fact about either file.

#### Scenario: Both results are presented

- **WHEN** two files are compared and both readings have ended
- **THEN** each file's result is presented as its own statement, and no outcome, difference or combined
  result appears beside them

### Requirement: Say honestly what a comparison is doing

While a second file is being inspected, the system SHALL say so where that file's values would appear,
and SHALL NOT present a placeholder, a zero, a dash standing for a number, or any invented value for it.

Where inspecting the second file failed, the system SHALL state that the second file could not be
inspected, in the words the flow produced, and SHALL NOT attribute the failure to a difference between
the files or to anything about their audio. The first file's own content SHALL remain presented and
unchanged.

#### Scenario: The second file is still being inspected

- **WHEN** a comparison is loading
- **THEN** the surface says the second file is being inspected, and shows no value of any kind for it

#### Scenario: The second file could not be inspected

- **WHEN** a comparison failed
- **THEN** the surface states that, in the flow's own words, and everything already presented about the
  first file is unchanged

### Requirement: Present the whole report without a transitional page

The system SHALL present every part of a report — the file's identity, its technical properties, its
measurements, its drawings, its notes and the result of the reading — through the workspace sections, in
both modes.

No surface SHALL present the report as one scrolling page, and no section SHALL fall back to one.

#### Scenario: No section shows a whole-report page

- **WHEN** any section is selected, with or without a comparison
- **THEN** it presents its own content, and no surface presents every part of the report at once
