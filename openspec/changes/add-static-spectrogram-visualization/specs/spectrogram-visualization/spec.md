## ADDED Requirements

### Requirement: Derive a bounded spectral model from the file's samples

The system SHALL derive, from the samples of the selected local audio file, a spectral model spanning
the whole file, computed as a short-time Fourier transform over **overlapping** windows so that no part
of the file's audio is skipped between windows.

Each read SHALL consume **exactly the number of frames the read reports as valid, and never the capacity
of the buffer it was read into**. The samples SHALL be read in bounded chunks and the decoded track
SHALL NEVER be held in memory in full: peak memory MUST be a function of the chunk size and the model's
fixed resolution, never of the file's length or duration.

The model SHALL be expressed as a fixed maximum of **1024 columns of time** by **512 bands of
frequency**, **independent of the width or height of any view**. Where the file yields more transform
frames than columns, or more frequency bins than bands, they SHALL be reduced by taking the
**maximum**, never an average, so that a brief or narrow concentration of energy is preserved rather
than diluted by its neighbours.

The mapping from a transform frame to its column SHALL be a function of the file alone, so the same
file yields an identical model regardless of the chunk size used to read it. Resizing the view SHALL
NOT cause the file to be decoded again, the transform to be recomputed, or the spectral evidence to
change.

The final incomplete window SHALL be **discarded rather than padded**: padding invents samples the file
does not contain and understates the level of the region it pads.

The read SHALL honour cancellation at chunk boundaries, stopping promptly and leaving no file open. The
system MUST NOT modify the file it reads.

#### Scenario: The model spans the whole file

- **WHEN** a file whose samples can be read is inspected
- **THEN** the system produces a spectral model covering the file from its first frame to its last,
  with at most 1024 columns and at most 512 bands

#### Scenario: The model does not depend on how the file was chunked

- **WHEN** the same file is read twice using different chunk sizes
- **THEN** both reads produce identical spectral values

#### Scenario: Memory does not grow with the file

- **WHEN** a long file and a short file of the same format are read
- **THEN** the memory used to produce each model is bounded by the chunk size and the fixed resolution,
  and does not scale with the file's duration

#### Scenario: Resizing does not recompute

- **WHEN** the view showing a spectrogram changes size
- **THEN** the existing model is redrawn at the new size, and the file is neither read nor transformed
  again

#### Scenario: A brief concentration of energy is not averaged away

- **WHEN** a file contains a short burst of high-frequency content surrounded by silence, and several
  transform frames fold into one column
- **THEN** the burst remains visible in the model at its own level, rather than being reduced towards
  the level of its silent neighbours

#### Scenario: A cancelled read stops promptly

- **WHEN** the operation is cancelled while the samples are being read
- **THEN** the read stops at the next chunk boundary, no model is presented as complete, and no file
  handle is left open

### Requirement: Represent spectral energy on an absolute scale, without normalising

Values SHALL be expressed in **dBFS on an absolute scale referenced to full scale**, with a fixed floor
so that everything quieter is represented as the floor rather than as an unbounded negative number.

The system MUST NOT normalise, per file or otherwise: a model MUST NOT be scaled relative to the file's
own loudest point, so a quiet file yields a quiet model and two files remain directly comparable. This
is what allows a user to compare copies of the same music.

Where a file has more than one channel, each channel SHALL be transformed **separately** and the
channels combined by taking the **maximum magnitude per frequency**, so that energy present in a single
channel survives and channels in opposing polarity cannot cancel. The system MUST NOT combine channels
by mixing, summing or averaging their **samples** before transforming, because that synthesises a
signal present in no channel and introduces spectral content the file does not contain. The result is a
**combined** spectrogram and MUST NOT be named or described as a mono mix or a downmix.

Samples that are not finite MUST be refused rather than transformed, so that a corrupted region is
reported as a fault instead of silently appearing as an absence of energy.

#### Scenario: Level is preserved across files

- **WHEN** two files carrying the same signal at clearly different levels are analysed
- **THEN** their models differ in magnitude in proportion to that difference, and neither is scaled to
  its own peak

#### Scenario: Energy in one channel alone survives

- **WHEN** a file carries a tone in one channel and silence in the other
- **THEN** the tone appears in the model at its own level, exactly as it would for a single-channel file
  carrying the same tone

#### Scenario: Channels in opposing polarity do not cancel

- **WHEN** a file whose two channels carry the same signal with opposite polarity is analysed
- **THEN** the model shows the energy present in the channels and is not empty

#### Scenario: No spectral content is invented

- **WHEN** a file's two channels carry different signals
- **THEN** the model contains energy at the frequencies present in the channels, and no significant
  energy at frequencies present in neither

#### Scenario: A non-finite sample is refused

- **WHEN** the samples read from a file include a value that is not a number
- **THEN** the system reports a failure to produce the model, rather than a model in which the affected
  region reads as silence

### Requirement: An absent spectrogram never damages a correct report

The spectral model SHALL be produced and carried **beside** the inspection report, never inside it.
Failure or absence of the spectrogram is a first-class outcome, distinct from an inspection failure:
when the properties were read but the samples were not, the report SHALL be presented exactly as it
would be without this capability, and the spectrogram's absence SHALL be stated.

A spectrogram that could not be produced MUST NOT emit an inspection warning, MUST NOT change the
global inspection status, and MUST NOT appear in the exported JSON in any form. The `schemaVersion` 1
contract is unchanged by this capability. Nothing about the spectrogram may disclose the file's
location.

The spectrogram SHALL be produced as its own operation, cancellable independently of any other
sample-reading work, so that cancelling one visualisation does not cancel another.

#### Scenario: The samples cannot be read but the properties can

- **WHEN** a file's technical properties are read successfully and its samples are not
- **THEN** the report is presented with the same properties, warnings and status it would have
  otherwise, and the spectrogram is reported as unavailable

#### Scenario: The export is unaffected

- **WHEN** a report is exported, with or without a spectrogram
- **THEN** the exported JSON is identical in structure and content to what the same inspection would
  export without this capability, and contains no spectral data

#### Scenario: One visualisation is cancelled and the other is not

- **WHEN** one sample-reading visualisation is cancelled while another is in flight
- **THEN** the other continues and produces its result

### Requirement: Present the spectrogram as a still drawing that interprets nothing

The spectrogram SHALL be presented as a **static drawing** beside the report, with time on the
horizontal axis and frequency on the vertical axis, and with intensity conveyed by colour. There SHALL
be no interaction: no playback, no zoom, no scrubbing, no selection and no cursor. Pointer or scroll
activity over the drawing SHALL NOT alter it or the data behind it.

The frequency axis SHALL be **linear** and SHALL span from zero to **the file's own Nyquist frequency**,
whatever the sample rate, without cropping. A file that declares a high sample rate but carries no
content in its upper range is showing evidence, and the axis MUST NOT hide it.

Colour SHALL be used only to convey intensity, on a scale whose **luminance increases monotonically**,
and MUST NOT carry a judgement: no colour may mean good, bad, safe or damaged. A **numeric legend
stating the decibel range** SHALL accompany the drawing, because a gradient without a scale states
nothing. Colour SHALL NOT be the sole carrier of any meaning, and states such as loading, absence and
failure SHALL be stated in words.

Presentation MUST NOT interpret the drawing. It MUST NOT describe the file or any part of it as lossy,
transcoded, fake, authentic, good or bad, MUST NOT name a probable encoder or bitrate, and MUST NOT
present the model as a measurement of level. It MAY state what is observable — that energy is present or
absent above a frequency, that an edge is abrupt, that bands or gaps appear — and MUST NOT state what
that observation implies about the file's origin.

The spectrogram SHALL remain usable without seeing it: it SHALL be exposed to an assistive reader as a
single element labelled with what it is rather than with what it looks like, and when no spectrogram
exists its absence SHALL be stated in words rather than shown as an empty area.

#### Scenario: The drawing does not respond to interaction

- **WHEN** the user clicks, drags or scrolls over the spectrogram
- **THEN** nothing is played, selected, zoomed or moved, and the drawing and its data are unchanged

#### Scenario: The full Nyquist range is shown

- **WHEN** a file declaring a high sample rate carries no content in its upper frequency range
- **THEN** the drawing still spans the file's full Nyquist range, and the empty region is visible

#### Scenario: The drawing carries no verdict

- **WHEN** a spectrogram is presented for a file whose content stops abruptly below its Nyquist
- **THEN** no text, colour or symbol states or implies that the file is lossy, transcoded, fake or of
  poor quality

#### Scenario: The scale is readable

- **WHEN** a spectrogram is presented
- **THEN** a legend states the decibel range the colours represent, and the frequency axis is labelled

#### Scenario: The spectrogram is reachable without seeing it

- **WHEN** the report is read with an assistive reader
- **THEN** the spectrogram is announced as a single element describing what it is, with no
  characterisation of the audio, and an absent spectrogram is announced as unavailable
