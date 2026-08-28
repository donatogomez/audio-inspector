## ADDED Requirements

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
