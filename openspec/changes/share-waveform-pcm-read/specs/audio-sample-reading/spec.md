## MODIFIED Requirements

### Requirement: One read of a file's samples serves every analysis that needs them

The system SHALL read a file's decoded samples **once** on behalf of **every** analysis that consumes
them, handing each chunk to every such analysis before the next chunk is read, rather than reading the
file once per analysis. No analysis SHALL keep a read of its own.

Each analysis SHALL keep its own accumulation, its own result and its own reported outcome. The read
SHALL NOT know what any analysis computes, and no analysis SHALL be able to observe another's state.

Adding a new sample-consuming analysis SHALL cost no additional read of the file.

An analysis whose accumulation consumes runs of samples rather than whole chunks — needing the channel
and the absolute frame position of each run — SHALL be served by the same read as the others, from the
same chunks. Sharing SHALL NOT require changing what any analysis computes, and the reduction rules of
each SHALL remain the analysis's own.

#### Scenario: Several analyses are produced from one read

- **WHEN** a file is inspected and more than one sample-consuming analysis is requested
- **THEN** the file's samples are read once, and every requested analysis is produced from that read

#### Scenario: Each analysis reports its own result

- **WHEN** several analyses are produced from one read
- **THEN** each is reported as its own result, and none is merged into or derived from another

#### Scenario: An inspection reads the file's samples exactly once

- **WHEN** a file is inspected and every sample-based analysis is requested
- **THEN** exactly one read of the file's samples is opened, counted at the boundary that opens it

#### Scenario: An analysis needing frame positions is served by the shared read

- **WHEN** an analysis reduces runs of samples identified by channel and absolute frame position
- **THEN** it is fed from the same chunks as the others, and its result is the one it would have
  produced from a read of its own — identical for a losslessly encoded file, and within a stated
  tolerance where the platform's decoder does not return identical samples for a different read
  granularity
