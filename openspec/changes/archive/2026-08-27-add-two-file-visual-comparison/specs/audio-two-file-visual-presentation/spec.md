## ADDED Requirements

### Requirement: Pair two files' already-produced drawings, without reading or computing them again

When a comparison exists, the system SHALL present the amplitude envelope and the spectral model of
**both** files together, using the artefacts each file's own inspection **already produced**. It SHALL
NOT read either file's samples again, and SHALL NOT recompute either artefact for the pairing: adding
this presentation MUST cost **no additional read and no additional transform**.

A pairing SHALL exist only once **both** files have settled both artefacts. A drawing still being
produced is a state of the flow and never a result, so a file that has not finished yields **no
pairing** rather than a pairing with a missing side.

#### Scenario: Both files' drawings are presented together

- **WHEN** two files have been inspected as a comparison and both have settled their envelope and their
  spectral model
- **THEN** the system presents both files' envelopes together and both files' spectral models together,
  each attributed to the first or the second file

#### Scenario: The compared file's samples are read once

- **WHEN** a second file is inspected for a comparison whose drawings will be paired
- **THEN** exactly one read of that file's samples is opened, counted at the boundary that opens it, and
  the pairing adds none

#### Scenario: The paired drawings are the ones the inspection produced

- **WHEN** a pairing is presented
- **THEN** each side's envelope and spectral model are identical to the values that file's own inspection
  produced, and neither has been derived, re-reduced or re-scaled for the pairing

#### Scenario: A file still producing its drawings yields no pairing

- **WHEN** one file has settled both artefacts and the other has not finished producing them
- **THEN** no pairing is presented, and the file that has finished is not shown as having nothing

### Requirement: A pairing describes one pair of inspections, and can never be assembled from two

The system SHALL publish a pairing as a **single value covering both files**, so that a first file's
drawing and a second file's drawing presented together always belong to the **same** comparison
operation. It SHALL NOT assemble a pairing by reading one side from one place and the other from
another.

A **cancelled** inspection is not a settled answer: it belongs to an operation the user replaced, says
nothing about the file, and SHALL yield no pairing rather than an absence.

#### Scenario: A superseded second file never appears beside a newer one

- **WHEN** one second file's inspection is still running, the user chooses a different second file, and
  the first one finishes afterwards
- **THEN** no pairing containing the superseded file's drawings is ever presented, and the pairing that
  appears contains only the current second file's

#### Scenario: A cancelled second inspection produces no pairing

- **WHEN** a second file's inspection is cancelled before it settles
- **THEN** no pairing is presented, and no side is shown as absent, failed or empty on account of the
  cancellation

#### Scenario: The pairing and the comparison beside it describe the same two files

- **WHEN** a pairing is presented while a technical comparison and a measurement comparison are also on
  screen
- **THEN** all three describe the same two inspections, and no combination of a newer file's facts with
  an older file's drawing is presentable

### Requirement: While a pairing is presented, it stands in for the single-file drawings

While a pairing is presented, the system SHALL present it **instead of** the first file's own envelope
and spectral model sections, so that a file is **never drawn twice at once** and never appears
simultaneously under two different axes.

Whenever there is **no** pairing — none has been asked for, one is not yet settled, one was cancelled,
dismissed or superseded, or the second file could not be inspected — the system SHALL present the first
file's own drawings exactly as it would without this capability. Returning to them SHALL NOT read or
compute anything again.

Replacement SHALL apply to the two drawings and to nothing else: the report's property rows, the
technical comparison and the measurement comparison SHALL remain present and unchanged.

#### Scenario: The single-file drawings stand while no pairing exists

- **WHEN** a report is on screen with no comparison, or with a comparison whose pairing has not settled
- **THEN** the first file's envelope and spectral model are presented exactly as they are without this
  capability

#### Scenario: A settled pairing replaces the single-file drawings

- **WHEN** a pairing settles
- **THEN** the paired drawings are presented and the first file's own envelope and spectral model
  sections are no longer presented separately

#### Scenario: A file is never drawn twice at once

- **WHEN** a pairing is presented
- **THEN** the first file's envelope appears exactly once on the surface, and its spectral model exactly
  once

#### Scenario: Dismissing the comparison restores the single drawings

- **WHEN** a comparison carrying a pairing is dismissed, superseded, or ended by a new primary inspection
- **THEN** the first file's own drawings are presented again where applicable, and no file is read and no
  artefact is produced again in order to do so

#### Scenario: Nothing else on the report is replaced

- **WHEN** a pairing is presented
- **THEN** the property rows, the technical comparison and the measurement comparison are all still
  presented, unchanged

### Requirement: Draw both envelopes on one absolute amplitude scale

Both envelopes SHALL be drawn against the **same fixed amplitude scale**, the one a single envelope is
already drawn against. Neither SHALL be normalised — not to its own peak, not to the other file's, and
not to the pair's — so a quiet file MUST look quiet beside a loud one and two files remain comparable by
eye.

A sample beyond the nominal scale SHALL be limited **when drawn and only then**; the values behind the
drawing are unchanged.

#### Scenario: Two files at clearly different levels

- **WHEN** two files carrying the same signal at clearly different levels are paired
- **THEN** their drawings differ in magnitude in proportion to that difference, and neither is scaled to
  its own peak

#### Scenario: Neither side is re-ranged for the pair

- **WHEN** a pairing is drawn
- **THEN** both sides are drawn against the same amplitude range as a single envelope is, and no range,
  gain or contrast is computed from either file

### Requirement: Draw both files on one shared time axis spanning the longer of them

Both envelopes, and both spectral models, SHALL be drawn on **one shared time axis** whose extent is the
**greater** of the two files' own extents, each taken from the stream that file's samples were read
from.

Each file's drawing SHALL occupy exactly its own extent as a fraction of the shared extent, and SHALL
**end there**. The remainder of that file's lane SHALL carry **no drawn value at all**, and SHALL be
described **in words** as being **outside that file's audio** — never as silence, never as a measured
zero, and never as an empty region the reader has to interpret.

The system SHALL NOT stretch, compress or crop either file's drawing to make the two occupy the same
extent, SHALL NOT align them, and SHALL NOT state or imply that a position in one drawing corresponds to
the same position in the other.

#### Scenario: Two files of the same duration

- **WHEN** two files of the same duration are paired
- **THEN** both drawings span the whole shared time axis and neither has a remainder

#### Scenario: The second file is shorter

- **WHEN** the second file is shorter than the first
- **THEN** the first file's drawing spans the whole axis, the second file's ends at its own duration as a
  fraction of the shared one, and the remainder of its lane carries no drawn value

#### Scenario: The first file is shorter

- **WHEN** the first file is shorter than the second
- **THEN** the same rule applies with the sides exchanged, and the shared extent is the second file's

#### Scenario: The remainder is not silence

- **WHEN** a file's lane has a remainder beyond its own audio
- **THEN** the surface states in words that the file has no audio there, and the remainder is not drawn
  as a silent value, a baseline, a zero or a floor

#### Scenario: Neither drawing is stretched to fit

- **WHEN** two files of different durations are paired
- **THEN** each drawing keeps the same proportions it would have alone, occupying less of the axis rather
  than being widened or narrowed to match the other

#### Scenario: Both kinds of drawing share the one axis

- **WHEN** a pairing presents both envelopes and both spectral models
- **THEN** all four are drawn against the same shared time extent, taken from the same source for each
  file

### Requirement: Draw both spectral models on one absolute energy scale

Both spectral models SHALL be drawn with the **same colour ramp, the same floor and the same legend** as
each other and as a single model is drawn with. Neither SHALL be normalised, auto-ranged, auto-contrasted
or re-coloured relative to the other or to itself.

#### Scenario: One ramp, one floor, one legend

- **WHEN** a pairing presents two spectral models
- **THEN** both are drawn with the same ramp and the same floor, and one legend describes both

#### Scenario: A quiet file beside a loud one

- **WHEN** two files whose energy differs clearly are paired
- **THEN** that difference is visible in the drawings, and neither is brightened or darkened to resemble
  the other

### Requirement: Draw both spectral models on one shared frequency axis reaching the higher Nyquist

Both spectral models SHALL be drawn on **one shared frequency axis** running from 0 Hz to the **greater**
of the two files' Nyquist frequencies. Each model SHALL occupy exactly its own Nyquist as a fraction of
the shared one, from 0 Hz upward.

The region above a file's own Nyquist SHALL carry **no drawn value**, SHALL be described **in words** as
outside what that file can represent, and SHALL be **visually distinguishable from the ramp's floor**:
*this file cannot represent this range* and *this file was measured here and is very quiet* are different
facts and MUST NOT look the same.

The shared axis SHALL NOT be cropped to the lower Nyquist, and neither model SHALL be stretched to fill
the axis.

#### Scenario: Two files at the same sample rate

- **WHEN** two files with the same sample rate are paired
- **THEN** both models span the whole shared frequency axis and neither has a region above its own
  Nyquist

#### Scenario: A lower-rate file beside a higher-rate one

- **WHEN** a 44.1 kHz file and a 96 kHz file are paired, in either order
- **THEN** the shared axis reaches the 96 kHz file's Nyquist, the 44.1 kHz file's model occupies its own
  Nyquist as a fraction of that, and the 96 kHz file's model spans the whole axis

#### Scenario: The region above a file's Nyquist is not the floor

- **WHEN** a file's model has a region above its own Nyquist on the shared axis
- **THEN** that region is drawn distinguishably from the ramp's floor colour, is stated in words as
  outside what the file can represent, and carries no cell

#### Scenario: The axis is not cropped to the lower rate

- **WHEN** two files of different sample rates are paired
- **THEN** the higher file's range is presented in full, and the axis is labelled to the shared Nyquist
  rather than to the lower one

### Requirement: State an absent or failed drawing in words, never as an empty picture

For each file and each artefact, the system SHALL keep **absence** and **failure** distinct, and SHALL
state either **in words**. It MUST NOT stand in for a missing drawing with an empty envelope, an empty
grid, a zero-filled or floor-coloured region, or a blank area the reader has to interpret.

A model with no columns — a file shorter than one analysis window — is a **complete answer** and MUST
NOT be presented as an absence or as a failure.

One side being absent or failed SHALL NOT withhold the other side's drawing, and SHALL NOT remove the
shared axis the present side is drawn against.

#### Scenario: One side has no envelope

- **WHEN** one file offered nothing to build an envelope from and the other produced one
- **THEN** the present file's envelope is drawn on the shared axis, and the other side states in words
  that the file has no envelope

#### Scenario: One side's drawing failed

- **WHEN** producing one file's artefact failed and the other's succeeded
- **THEN** the failure is stated in a neutral sentence that names no path and no framework, distinct from
  the sentence used for an absence

#### Scenario: Absence and failure do not read the same

- **WHEN** one pairing has an absent side and another has a failed side
- **THEN** the two are stated differently, and neither is presented as the other

#### Scenario: A file too short for a spectral model

- **WHEN** a file yields a model with no columns
- **THEN** that is stated as its own fact, distinct from an absence and from a failure, and no grid is
  drawn for it

### Requirement: Say nothing about the two files that two drawings cannot support

The system SHALL NOT state, imply, rank, order or score any relationship between the two files on the
strength of their drawings. It SHALL publish **no outcome** about the pair of pictures.

No text, colour, symbol, badge, ordering or emphasis on this surface may say or imply: *same*,
*different*, *identical*, *similar*, *matching*, *matching regions*, *indistinguishable*, *separated*;
that one file is *louder*, *quieter*, or carries *more* or *less* high-frequency content; that the files
share or do not share a *source*, a *master*, a *remaster*, or that one is a *transcode* or an
*upsample*; or that either is *better*, *worse*, of higher *quality*, or the one to keep.

The permitted words are the two files' attribution — **first** and **second**, by position, never
*original*, *copy*, *source* or *derived* — the names of the artefacts, the factual labels of the shared
axes, and the factual statements of absence and of out-of-range required above.

Channels SHALL NOT be paired, reconciled or compared here: both artefacts already combine a file's
channels, and a differing channel count is not an error and produces no statement on this surface.

#### Scenario: No outcome word appears

- **WHEN** a pairing is presented for any two files, including two identical ones
- **THEN** nothing on the surface states whether the two drawings, or the two files, are the same or
  different

#### Scenario: Nothing ranks the two files

- **WHEN** a pairing is presented
- **THEN** no badge, arrow, ordering, highlight, colour or emphasis reads as a preference for either
  file, and neither is presented first because it is better

#### Scenario: Differing channel counts produce no statement

- **WHEN** two files with different channel counts are paired
- **THEN** both drawings are presented as they are, and nothing on this surface compares, reconciles or
  remarks on the channel counts

### Requirement: Present the paired drawings as still drawings that interpret nothing

The paired drawings SHALL be **static**, with no interaction: no playback, no zoom, no scrubbing, no
selection, no cursor and no synchronised navigation between the two. Pointer or scroll activity over
either drawing SHALL NOT alter it, the other, or the data behind them.

Every meaning the paired presentation conveys SHALL have a textual alternative: each drawing SHALL be
exposed to an assistive reader as a **single element**, labelled with what it is and with which file it
belongs to, never with what it looks like; the shared axes' extents SHALL be available as text; and the
out-of-range regions and the absences SHALL be stated in words rather than shown as empty area. Colour
SHALL NOT be the sole carrier of any meaning.

#### Scenario: The paired drawings do not respond to interaction

- **WHEN** the user clicks, drags or scrolls over either drawing
- **THEN** nothing is played, selected, zoomed, scrubbed or moved in either drawing, and the data behind
  them is unchanged

#### Scenario: The pairing is reachable without seeing it

- **WHEN** the surface is read with an assistive reader
- **THEN** each drawing is announced as one element naming the artefact and the file it belongs to, with
  no characterisation of the audio, and each absent drawing is announced as unavailable

#### Scenario: Nothing depends on colour alone

- **WHEN** the pairing is viewed by a user who cannot distinguish colour
- **THEN** every meaning it conveys — including which region is outside a file's audio and which is
  outside what it can represent — remains available from text or shape

### Requirement: Keep the pairing out of the report and out of the export

The paired presentation SHALL travel **beside** the inspection reports and never inside them. It SHALL
NOT appear in the exported document in any form, SHALL NOT emit an inspection warning, and SHALL NOT
change either file's global inspection status. The `schemaVersion` 1 contract is unchanged by this
capability.

#### Scenario: The export is unaffected

- **WHEN** a report is exported while a pairing is on screen
- **THEN** the exported document is identical in structure and content to what the same inspection
  exports with no comparison at all, and contains no drawing data

#### Scenario: A missing drawing never damages a report

- **WHEN** either file's artefact is absent or failed
- **THEN** both reports are presented with the same properties, warnings and status they would have
  otherwise, and no warning is emitted for the drawing
