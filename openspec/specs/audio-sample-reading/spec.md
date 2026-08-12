# audio-sample-reading Specification

## Purpose
TBD - created by archiving change add-shared-pcm-read. Update Purpose after archive.
## Requirements
### Requirement: One read of a file's samples serves every analysis that needs them

The system SHALL read a file's decoded samples **once** on behalf of the analyses that consume whole
chunks of them, handing each chunk to every such analysis before the next chunk is read, rather than
reading the file once per analysis.

Each analysis SHALL keep its own accumulation, its own result and its own reported outcome. The read
SHALL NOT know what any analysis computes, and no analysis SHALL be able to observe another's state.

Adding a new sample-consuming analysis SHALL cost no additional read of the file.

#### Scenario: Several analyses are produced from one read

- **WHEN** a file is inspected and more than one sample-consuming analysis is requested
- **THEN** the file's samples are read once, and every requested analysis is produced from that read

#### Scenario: Each analysis reports its own result

- **WHEN** several analyses are produced from one read
- **THEN** each is reported as its own result, and none is merged into or derived from another

### Requirement: One analysis failing does not disturb the others

The system SHALL confine a single analysis's failure to that analysis. When one cannot continue — its
accumulation cannot be built for the stream it is given, or it detects audio that does not match that
stream — the system SHALL stop that analysis, **continue reading for the others**, and report a failure
for it alone. Every other analysis SHALL settle exactly as it would have had the failing one never been
requested.

An analysis that fails SHALL NOT emit an inspection warning, SHALL NOT change the global inspection
status, and SHALL NOT alter any other analysis's result.

#### Scenario: A failing analysis leaves the others intact

- **WHEN** one analysis fails partway through a shared read
- **THEN** it is reported as failed, the read continues, and every other analysis produces exactly the
  result it would have produced on its own

#### Scenario: No analysis depends on another being requested

- **WHEN** a subset of the sample-consuming analyses is requested
- **THEN** each produces the same result it would produce when all of them are requested

### Requirement: A failure to read samples ends every analysis that depends on it

When the **read itself** fails, no further samples exist for anyone, so the system SHALL end every
analysis that had not already finished and SHALL report a failure **for each of them separately**. A
reader unable to obtain one analysis's result SHALL NOT have to consult another's to learn what
happened.

A failure to read samples SHALL be distinguishable from an analysis's own failure.

#### Scenario: The read fails partway through

- **WHEN** the samples cannot be read past a certain point
- **THEN** every analysis that had not finished is reported as failed, each on its own terms

#### Scenario: A file that holds no audio is not a failure

- **WHEN** a file opens correctly and contains no audio frames
- **THEN** each analysis reports its own complete, empty answer rather than a failure

### Requirement: Cancelling an inspection cancels the read and every analysis

When an inspection is cancelled, the system SHALL stop reading and SHALL report every unfinished
analysis as cancelled. **No partial or provisional result SHALL escape**: a cancelled analysis reports
cancellation, never a value computed from the samples read so far.

Cancellation SHALL be distinguishable from both a failure and an absence.

The read SHALL continue while **any** analysis still needs samples, and SHALL stop once every analysis
has finished, so that one analysis finishing early cannot deprive another of the samples it needs.

#### Scenario: A cancelled inspection yields no partial results

- **WHEN** an inspection is cancelled partway through the read
- **THEN** every unfinished analysis reports cancellation and none reports a value derived from the
  samples read before it stopped

#### Scenario: One analysis finishing early does not stop the read

- **WHEN** one analysis needs no further samples while another still does
- **THEN** the read continues until every analysis has what it needs

### Requirement: The read is bounded, deterministic and does not delay the report

The system SHALL NOT retain the file's decoded samples: memory used by the read and by the analyses
consuming it SHALL be a function of the chunk size and of each analysis's own fixed state, **never of
the file's duration**.

Every analysis's result SHALL be identical regardless of how the samples were divided into chunks.

Reading samples SHALL NOT delay the inspection report, which is produced from metadata alone and
reported before any sample is read.

#### Scenario: A long file uses no more memory than a short one

- **WHEN** files of very different durations are inspected
- **THEN** the memory used by the read and its analyses does not grow with duration, and no complete
  copy of the file's samples is held

#### Scenario: Chunk size does not change any result

- **WHEN** the same file is read in different chunk sizes
- **THEN** every analysis produces an identical result

#### Scenario: The report is not held up by the analyses

- **WHEN** a file is inspected
- **THEN** the report is available before the samples are read, and remains unaffected by what any
  analysis subsequently does

