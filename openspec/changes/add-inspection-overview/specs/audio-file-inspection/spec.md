## ADDED Requirements

### Requirement: Present one file's inspection as an overview section

The system SHALL present, as one section of the inspection workspace, an overview of the file being
inspected: the **file's own identity**, the **core technical facts**, the **key measurements**, a
**compact drawing of the amplitude envelope**, and **what became of the reading** — reachable by
selecting that section, and not by scrolling past unrelated content.

That section SHALL be the section a newly inspected file arrives at, and it SHALL be the only place those
five bodies of content are presented together while it is selected.

The core technical facts SHALL be the ones the report's own property presentation designates as
identifying a file, and each SHALL keep the value, the unit and the certainty state that presentation
gives it. The overview itself SHALL NOT select, reorder, omit or rename a property.

Each measurement SHALL contribute the **first** fact its own presentation produces, in that
presentation's own order and words, or the sentence it produces in place of facts when it has none. The
overview SHALL NOT reorder the measurements, promote one over another, or describe any of them as
principal, headline, notable or important.

#### Scenario: The section is selected

- **WHEN** the reader selects the overview section for a file being inspected on its own
- **THEN** the file's identity, the core technical facts, the key measurements, a compact amplitude
  drawing and the result of the reading are presented together

#### Scenario: A newly inspected file arrives at the overview

- **WHEN** a new primary file is inspected
- **THEN** the reader is at the overview section, and it presents that file's own overview

#### Scenario: The technical facts are the report's own selection

- **WHEN** the core technical facts are presented
- **THEN** they are exactly the properties the report's presentation designates as identifying a file,
  each appearing once with the value, unit and certainty that presentation gives it, and the overview
  names no property of its own

#### Scenario: One fact per measurement, in the measurement's own order

- **WHEN** a measurement that produced facts is presented on the overview
- **THEN** the fact shown is the first one that measurement's own presentation produces, with its own
  name, value and unit, and no measurement is ranked against another

### Requirement: Restate facts on the overview without deriving anything from them

The overview SHALL restate what the inspection already produced, and SHALL derive nothing from it.
Every value, unit, name, statement of absence, statement of failure, certainty state and outcome
sentence on it SHALL be exactly the one the inspection produced for that fact, and the overview SHALL
NOT compute, round, convert, re-derive, re-word or substitute any of them.

A fact with no value SHALL be stated as having none, in words, and MUST NOT be shown as zero, as a floor,
as a threshold or as any substituted figure. A fact whose reading **failed** SHALL remain distinguishable
from one the file does not carry and from one that is still being produced.

The overview MUST NOT present an absolute path, a URL, a parent directory, a security-scoped bookmark or
any other form of the file's location, and SHALL describe where the file came from in the terms the
report already uses.

#### Scenario: A fact the file does not carry

- **WHEN** a fact presented on the overview has no value
- **THEN** the overview states that in words, and shows no number, zero or floor value in its place

#### Scenario: A measurement still being produced

- **WHEN** a measurement has not settled
- **THEN** the overview says it is being prepared, and does not present it as absent or as failed

#### Scenario: The same fact says the same thing in both places

- **WHEN** a fact appears on the overview and also in the section that owns it
- **THEN** its name, its value, its unit and its certainty are identical, because both are the values the
  inspection produced

#### Scenario: No location is disclosed

- **WHEN** the file's origin is described on the overview
- **THEN** the description names the kind of selection and states that the location is omitted, and no
  path, URL or directory appears anywhere in the section

### Requirement: The overview summarises nothing and judges nothing

The overview MUST NOT present a score, a grade, a rating, a percentage, a similarity, a total, or any
other aggregate over the facts it shows — either directly, or by an absence that would mean one.

It MUST NOT state a count of the report's notes, and MUST NOT introduce any other cardinality over a list
of them.

It MUST NOT characterise the file or any of its values as good, bad, high, low, safe, unsafe, hot, quiet,
loud, excessive, clipping, distorted, better, worse, or as an indication of quality of any kind, and MUST
NOT introduce a threshold, a target, a delivery level, a platform or a reference to compare against.

It MUST NOT state or imply anything about the file's origin, master, remaster, transcode, upsampling or
bitrate, and MUST NOT describe in plain language what the file *is* beyond the facts the report carries.

Colour, weight, badge or icon SHALL NOT vary with the magnitude of any value. Only a failure of the
**reading** may be given emphasis, and it SHALL carry words that say so.

#### Scenario: No aggregate over the overview's facts

- **WHEN** the overview is presented for any report, in any combination of measurement states
- **THEN** it offers no score, grade, rating, percentage, total or single phrase summarising the file

#### Scenario: The notes are not counted

- **WHEN** the report carries notes
- **THEN** the overview states no number of them, and the notes remain read where the report presents
  them

#### Scenario: A value beyond full scale is stated, not judged

- **WHEN** a value presented on the overview exceeds full scale
- **THEN** it is presented with its unit exactly as any other value is, with no colour, weight, badge or
  word that a value below full scale would not receive

#### Scenario: Nothing is inferred about the file's history

- **WHEN** the overview is presented for any file
- **THEN** no statement about origin, master, remaster, transcode, upsampling or bitrate appears, and no
  plain-language characterisation of the file is offered

### Requirement: The overview's drawing is informative, and is not a control

The compact amplitude drawing SHALL be produced from the envelope the inspection already generated for
that file. Presenting it SHALL NOT read the file, decode audio, run an accumulator, re-bucket, resample
or generate a second envelope, and SHALL NOT derive an alternative reduced source of its own.

Its amplitude scale SHALL be the absolute one the envelope is already drawn on. It MUST NOT be
normalised, auto-ranged or scaled to its own content.

It SHALL offer no interaction: no playback, playhead, zoom, pan, scrubbing, cursor, selection, hover
readout, transport or hit target of any kind.

Where the envelope is absent, still being produced, or failed, the overview SHALL state that in the words
the inspection already produces for it, and SHALL NOT draw silence in its place.

#### Scenario: The drawing reuses the envelope

- **WHEN** the overview presents the compact drawing
- **THEN** it is drawn from the envelope already produced for that inspection, and no decoder is created
  and no sample is read

#### Scenario: The drawing is still

- **WHEN** the compact drawing is presented
- **THEN** it responds to no click, drag, hover or key, and offers no playback, zoom, cursor or selection

#### Scenario: An absent envelope is words, not silence

- **WHEN** the file offers no envelope, or producing one failed
- **THEN** the overview states which of those happened, in the words the inspection produces, and draws
  no flat line in place of a drawing

### Requirement: Giving the overview content changes nothing beneath it

Giving the overview section its content SHALL NOT start an inspection, read samples, decode audio, run an
analysis, or recompute a property or a measurement. It SHALL present what the inspection already
produced.

It SHALL NOT change the exported document, its schema, the technical properties, the notes, the result of
the reading, or the drawings — and it SHALL NOT change how sections are selected, how many there are, or
what moves the reader between them. No content on the overview SHALL move the reader to another section.

**The comparison of two files SHALL remain presented.** Where a second file is being compared — while the
comparison is being prepared, once it is ready, and where it failed — the comparison SHALL still be
reachable, with its existing semantics, wording and placement unchanged. This change SHALL introduce no
comparison surface, no comparison value and no difference of its own.

#### Scenario: Selecting the overview computes nothing

- **WHEN** the reader selects the overview section and then selects another
- **THEN** no decoder is created, no samples are read, no analysis is run, and no property or measurement
  changes

#### Scenario: The comparison survives

- **WHEN** a second file is being compared, in any state the comparison can be in
- **THEN** the comparison is still presented, with the same semantics, the same wording and the same
  placement it had

#### Scenario: The overview navigates nobody

- **WHEN** the reader interacts with any content on the overview
- **THEN** the selected section does not change, and the section control remains the only way between
  sections

#### Scenario: The export is untouched

- **WHEN** a report is exported after the overview has been presented
- **THEN** the exported document and its schema version are exactly what they would have been
