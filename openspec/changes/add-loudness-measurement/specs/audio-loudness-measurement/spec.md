## ADDED Requirements

### Requirement: Measure the programme's integrated loudness

The system SHALL measure a file's **integrated loudness** from its decoded audio samples, following the
ITU-R BS.1770 / EBU R128 definition: frequency-weighted, accumulated over fixed-length blocks, and gated
so that the measurement describes the programme rather than its silences.

The measurement SHALL be **signal-derived** and therefore never a field of the metadata-only technical
properties. It SHALL be produced from the same single read of the file's samples that serves every other
sample-based analysis, and SHALL cost no additional read.

The value SHALL be reported in **LUFS**, as a single figure for the file. There is no per-channel
integrated loudness: the channels are combined before the quantity exists.

Every constant the measurement depends on — the weighting, the gate values, the block length — SHALL be
named and tied to the analysis engine version, and SHALL travel with the result, so that a reported
figure can be reproduced and so that changing any of them is a visible change of methodology rather
than a silent change of number.

The system SHALL NOT characterise a loudness measurement as loud, quiet, correct, excessive, ready for
any platform, or in need of any adjustment. It reports what was measured.

#### Scenario: A stereo programme reports one integrated loudness figure

- **WHEN** a stereo file is inspected
- **THEN** a single integrated loudness value in LUFS is reported for the file, accompanied by the
  methodology that produced it

#### Scenario: The measurement is frequency-weighted, not a plain average

- **WHEN** two files carry the same sample-domain level at different frequencies
- **THEN** their reported loudness differs according to the standard's weighting, and neither is
  reported as equal to the file's RMS level

#### Scenario: Quiet passages do not drag the programme's measurement down

- **WHEN** a file contains a loud passage and a substantially quieter one
- **THEN** the gating excludes what the standard excludes, and the reported value describes the
  programme rather than the mean of everything present

#### Scenario: The result does not depend on the sample rate

- **WHEN** the same signal is measured at different sample rates
- **THEN** the reported loudness is the same, because the weighting is adapted to the rate rather than
  assumed

#### Scenario: The result does not depend on how the file was read

- **WHEN** the same file's samples are decoded in different chunk sizes
- **THEN** the reported loudness is identical, with the filter's state and the block boundaries carried
  across chunks rather than restarted

### Requirement: Report loudness only where it can be measured honestly

The system SHALL report an integrated loudness figure only for channel configurations whose weighting it
can determine. Where the channel configuration cannot be established, or where the standard's weighting
depends on knowing which channel is which and the file does not say, the system SHALL report **no
value** rather than one computed from an assumed layout.

A file offering too little audio to complete a single measurement block SHALL be reported as **not
computable**, distinctly from a file that was measured. A measurement that could not be produced SHALL
NEVER be reported as a floor value, a substituted number, or zero.

A loudness measurement that is absent or could not be produced SHALL NOT emit an inspection warning,
SHALL NOT degrade the inspection status, and SHALL NOT alter the report, the other analyses, or the
exported document beyond its own field.

#### Scenario: A layout whose weighting is unknown yields no figure

- **WHEN** a file's channel configuration is one whose weighting the system cannot determine
- **THEN** no loudness value is reported, and the absence is presented as an absence rather than as a
  failure or as a number

#### Scenario: A file too short to fill one block is not computable

- **WHEN** a file contains less audio than one measurement block
- **THEN** the loudness is reported as not computable, distinctly from a measured value

#### Scenario: An absent measurement leaves everything else untouched

- **WHEN** the loudness measurement is absent or fails
- **THEN** the report, its warnings, its status, the other sample-based analyses and every existing
  exported field are exactly what they would have been
