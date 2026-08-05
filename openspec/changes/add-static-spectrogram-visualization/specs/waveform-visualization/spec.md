## MODIFIED Requirements

### Requirement: Produce a bounded amplitude envelope from the file's samples

The system SHALL derive, from the samples of the selected local audio file, an amplitude envelope
spanning the whole file. The samples SHALL be read in a **single pass over the file's audio**, in
bounded chunks, and the decoded track SHALL NEVER be held in memory in full: peak memory MUST be a
function of the chunk size and the envelope's resolution, never of the file's length or duration.

The samples MAY be obtained through a **decoding seam shared with other consumers of the same file's
audio**, rather than through a read owned by the envelope alone. Where it is, each consumer SHALL
remain its **own operation with its own cancellation**: cancelling one visualisation MUST NOT cancel
another, and no consumer may depend on another having been requested. Sharing the seam MUST NOT change
any guarantee below — the envelope's values, its resolution, its independence from chunk size, and its
outcomes remain exactly as specified.

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

#### Scenario: The envelope is unchanged by sharing a decoding seam

- **WHEN** the same file yields an envelope produced through a shared decoding seam and an envelope
  produced through a read owned by the envelope alone
- **THEN** the two envelopes are identical

#### Scenario: Cancelling another visualisation leaves the envelope alone

- **WHEN** another consumer of the same file's samples is cancelled while the envelope is still being
  produced
- **THEN** the envelope is produced and delivered as if the other consumer had never been requested
