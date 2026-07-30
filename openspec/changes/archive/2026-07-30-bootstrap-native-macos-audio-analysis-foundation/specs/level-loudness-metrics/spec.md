## ADDED Requirements

### Requirement: Compute level and loudness metrics with a documented, versioned methodology

The system SHALL compute, from the decoded audio stream, at minimum: sample peak (dBFS), true peak
(dBFS), RMS (dBFS), integrated loudness (LUFS), DC offset, and basic clipping detection. Each
metric SHALL follow a documented methodology, and every result SHALL record the analysis engine
version used.

#### Scenario: Metrics computed for a normal file

- **WHEN** a supported file is analyzed
- **THEN** the system reports sample peak, true peak, RMS, integrated LUFS, and DC offset with
  units, tagged with the engine version that produced them

#### Scenario: Deterministic results

- **WHEN** the same file is analyzed twice with the same engine version
- **THEN** the reported metric values are identical within the documented numeric tolerance

### Requirement: True peak via oversampling

The system SHALL estimate true (inter-sample) peak by oversampling the signal (at least 4×) before
peak detection, following ITU-R BS.1770 / EBU R128 practice, and SHALL record the oversampling
factor.

#### Scenario: Inter-sample clipping flagged

- **WHEN** a file's true peak exceeds 0 dBFS while its sample peak does not
- **THEN** the system flags possible inter-sample clipping and reports the true-peak value and the
  oversampling factor used

### Requirement: Basic clipping and DC offset detection

The system SHALL detect runs of consecutive full-scale samples as basic clipping and SHALL compute
per-channel DC offset.

#### Scenario: Clipped file

- **WHEN** a file containing sustained full-scale sample runs is analyzed
- **THEN** the system reports the presence of clipping and an indication of its extent, phrased as
  measured evidence

#### Scenario: File with DC offset

- **WHEN** a file whose samples have a non-zero mean is analyzed
- **THEN** the system reports the per-channel DC offset value

### Requirement: Cross-check loudness against a reference in tests

The loudness/true-peak implementation SHALL be validated in tests against a reference
implementation (FFmpeg `ebur128`) within explicit numeric tolerances.

#### Scenario: Reference comparison in the test suite

- **WHEN** the test suite runs on a synthetic fixture
- **THEN** the native LUFS and true-peak values agree with the FFmpeg `ebur128` reference within the
  documented tolerance
