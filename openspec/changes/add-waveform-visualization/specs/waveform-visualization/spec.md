## ADDED Requirements

### Requirement: Produce a bounded amplitude envelope from the file's samples

The system SHALL derive, from the samples of the selected local audio file, an amplitude envelope
spanning the whole file. The samples SHALL be read in a **single pass over the file's audio**, in
bounded chunks, and the decoded track SHALL NEVER be held in memory in full: peak memory MUST be a
function of the chunk size and the envelope's resolution, never of the file's length or duration.

Each read SHALL consume **exactly the number of frames the read reports as valid, and never the
capacity of the buffer it was read into**. The region beyond the reported frame count is not part of
the audio and MUST NOT contribute to the envelope, even though it may contain plausible sample values.

The envelope SHALL be expressed as a fixed number of **buckets** that is **independent of the width of
any view**, capped at 2048 and never exceeding the number of frames in the file, so a file shorter than
the cap produces no empty bucket. The mapping from a frame to its bucket SHALL be a function of the file
alone, so the same file yields an identical envelope regardless of the chunk size used to read it.
Resizing the view SHALL NOT cause the file to be decoded again. The read SHALL honour cancellation at
chunk boundaries, stopping promptly and leaving no file open. The system MUST NOT modify the file it
reads.

Where the file does not expose a usable total frame count, the system SHALL produce **no envelope** and
report its absence, rather than guessing a length or accumulating an unbounded buffer.

#### Scenario: The envelope spans the whole file

- **WHEN** a file whose samples can be read is inspected
- **THEN** the system produces an envelope covering the file from its first frame to its last, with a
  bucket count that does not exceed 2048 and does not exceed the file's frame count

#### Scenario: Only the frames reported as valid contribute

- **WHEN** a read reports fewer valid frames than the capacity of the buffer it filled
- **THEN** the envelope is computed from the reported frames alone, and is identical to what the same
  file yields when no surplus capacity exists

#### Scenario: The envelope does not depend on how the file was chunked

- **WHEN** the same file is read twice using different chunk sizes
- **THEN** both reads produce identical bucket values

#### Scenario: Memory does not grow with the file

- **WHEN** a long file and a short file of the same format are read
- **THEN** the memory used to produce each envelope is bounded by the chunk size and the bucket count,
  and does not scale with the file's duration

#### Scenario: Resizing does not decode again

- **WHEN** the view showing a waveform changes width
- **THEN** the existing envelope is redrawn at the new width and the file is not read again

#### Scenario: A cancelled read stops promptly

- **WHEN** the operation is cancelled while the samples are being read
- **THEN** the read stops at the next chunk boundary, no envelope is presented as complete, and no file
  handle is left open

#### Scenario: The total frame count is not usable

- **WHEN** a file opens but does not expose a usable total frame count
- **THEN** the system produces no envelope, states that it is unavailable, and does not fabricate a
  length or accumulate the decoded track in memory

### Requirement: Represent amplitude faithfully, without downmixing or normalising

Each bucket SHALL carry the **minimum** and the **maximum** sample value observed within its slice of
the file, taken across **all channels**. The system MUST NOT average, sum, or otherwise mix channels
into a single signal before measuring, because two channels in opposing phase would cancel and the
envelope would show a flat line for a file that is not flat. The result is a combined envelope and MUST
NOT be named or described as a mono mix or a downmix.

Values SHALL remain on the sample scale `[-1, 1]` and the system MUST NOT normalise, per file or
otherwise: an envelope MUST NOT be scaled relative to the file's own peak, so a quiet file yields a
small envelope and a file close to full scale yields a large one, and two files remain comparable.
Sample values beyond the nominal range SHALL be preserved as read rather than clamped; limiting them is
a concern of drawing, not of the data.

#### Scenario: Channels in opposing phase do not cancel

- **WHEN** a file whose two channels carry the same signal with opposite polarity is read
- **THEN** the envelope reflects the amplitude present in the channels and is not flat

#### Scenario: Level is preserved across files

- **WHEN** two files carrying the same signal at clearly different levels are read
- **THEN** their envelopes differ in magnitude in proportion to that difference, and neither is scaled
  to its own peak

#### Scenario: A sample beyond the nominal range is preserved

- **WHEN** a file contains sample values outside `[-1, 1]`
- **THEN** the bucket carrying them retains the values as read, and they are not clamped in the data

### Requirement: An absent waveform never damages a correct report

The waveform SHALL be produced and carried **beside** the inspection report, never inside it. Failure or
absence of the waveform is a first-class outcome, distinct from an inspection failure: when the
properties were read but the samples were not, the report SHALL be presented exactly as it would be
without this capability, and the waveform's absence SHALL be stated.

A waveform that could not be produced MUST NOT emit an inspection warning, MUST NOT change the global
inspection status, and MUST NOT appear in the exported JSON in any form. The `schemaVersion` 1 contract
is unchanged by this capability. Nothing about the waveform may disclose the file's location.

#### Scenario: The samples cannot be read but the properties can

- **WHEN** a file's technical properties are read successfully and its samples are not
- **THEN** the report is presented with the same properties, warnings and status it would have
  otherwise, and the waveform is reported as unavailable

#### Scenario: The inspection fails globally

- **WHEN** the file cannot be opened or read at all
- **THEN** the failed report is presented as it is today, no waveform is attempted or shown, and no
  second error is reported for it

#### Scenario: The export is unaffected

- **WHEN** a report is exported, with or without a waveform
- **THEN** the exported JSON is identical in structure and content to what the same inspection would
  export without this capability, and contains no waveform data

### Requirement: Present the waveform as a still drawing that interprets nothing

The waveform SHALL be presented as a **static drawing** of amplitude over time beside the report, with
no interaction: no playback, no zoom, no scrubbing, no selection and no cursor. Pointer or scroll
activity over the drawing SHALL NOT alter it or the data behind it.

Presentation MUST NOT interpret the drawing. It MUST NOT characterise the shape or any part of it as
loud, quiet, clipped, compressed, dynamic, healthy, damaged, good or bad, and MUST NOT present the
envelope as a measurement or as evidence about bit depth, encoding, integrity or provenance. It is a
drawing of amplitude, derived from the decoded signal, and is described as nothing more.

The waveform SHALL remain usable without seeing it: every piece of information the drawing conveys SHALL
have a textual alternative, the waveform SHALL be exposed to an assistive reader as a single element
labelled with what it is and not with what it looks like, and when no waveform exists its absence SHALL
be stated in words rather than shown as an empty area. Colour SHALL NOT be the sole carrier of any
meaning, and the surrounding text SHALL remain legible at the system's accessibility text sizes.

#### Scenario: The drawing does not respond to interaction

- **WHEN** the user clicks, drags or scrolls over the waveform
- **THEN** nothing is played, selected, zoomed or moved, and the drawing and its data are unchanged

#### Scenario: The drawing carries no judgement

- **WHEN** a waveform is presented for any file
- **THEN** no text, colour or symbol beside it characterises the signal's quality, level or condition,
  and none presents it as a measured value

#### Scenario: The waveform is reachable without seeing it

- **WHEN** the report is read with an assistive reader
- **THEN** the waveform is announced as an amplitude envelope of the file, with no characterisation of
  the audio, and an absent waveform is announced as unavailable

#### Scenario: Nothing depends on colour alone

- **WHEN** the waveform is viewed by a user who cannot distinguish colour
- **THEN** every meaning it or its surroundings convey remains available from text or shape
