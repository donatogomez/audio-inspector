## ADDED Requirements

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
