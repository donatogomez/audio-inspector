## ADDED Requirements

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
