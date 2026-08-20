# audio-two-file-comparison

## ADDED Requirements

### Requirement: Compare the measurements two files were already measured by

The system SHALL compare two inspected files by the measurements derived from their samples — signal
level metrics, true peak, integrated loudness and programme bandwidth — in addition to the technical
properties it already compares.

The second file's measurements SHALL be the ones its inspection already produced. The system SHALL NOT
start a second read, re-run any accumulator, or retain PCM in order to compare.

Each comparison SHALL be derived from two settled values. Loading, absence, failure and cancellation
SHALL be resolved to "nothing to compare" before the comparison is formed, so that no lifecycle state of
a run is presented as a fact about a file.

#### Scenario: The second file's measurements reach the comparison
- **WHEN** a file is compared against the file already on screen
- **THEN** the comparison carries that file's signal level metrics, true peak, integrated loudness and programme bandwidth
- **AND** exactly one decoder is created and exactly one sample read is performed for that file
- **AND** no accumulator is run a second time

#### Scenario: A measurement that does not exist is not compared
- **WHEN** either file has no value for a measurement
- **THEN** that measurement reports that nothing was compared, and which side was missing
- **AND** no value is substituted, defaulted or inferred for the missing side

### Requirement: Compare only measurements whose methods mean the same thing

The system SHALL decide comparability from the measurement's own recorded method identity, never from a
displayed string, and SHALL report a pair produced by incompatible methods as not comparable rather than
comparing the numbers.

True peak SHALL be comparable only when both the oversampling factor and the filter identity are equal.
Integrated loudness SHALL be comparable when the algorithm identity is equal and the pair of weighting
identities is one this project has demonstrated to produce the same number; any other weighting pair
SHALL be not comparable. Programme bandwidth SHALL be comparable only when the method identity is equal.
Signal level metrics carry no method and SHALL be comparable whenever both sides have a value.

#### Scenario: Two files at different sample rates compare their loudness
- **GIVEN** two files whose loudness was measured with the same algorithm and the two demonstrated weightings
- **WHEN** they are compared
- **THEN** their integrated loudness is compared
- **AND** no weighting name appears in the result

#### Scenario: A true peak measured at a different oversampling factor is not compared
- **GIVEN** two files whose true peak was measured at different oversampling factors
- **WHEN** they are compared
- **THEN** the true peak reports that nothing was compared
- **AND** the reason names the difference in method rather than a difference in the audio

### Requirement: Compare programme bandwidth on its own resolution grid

The system SHALL compare two programme bandwidth readings by whether the analysis cells they name
overlap, and SHALL NOT compare them by numeric equality of frequency.

A reading of frequency `f` at resolution `r` names the cell `[f − r/2, f + r/2]`. Two readings SHALL be
reported as indistinguishable at their own resolutions when `|f₁ − f₂| < (r₁ + r₂) / 2`, and as separated
otherwise.

The system SHALL NOT present this rule as an uncertainty interval, an error bar or a confidence bound,
and SHALL NOT publish a frequency difference between two readings.

#### Scenario: Two readings inside one another's cells
- **GIVEN** two readings 50 Hz apart, each on a 94 Hz grid
- **WHEN** they are compared
- **THEN** they are reported as indistinguishable at those resolutions
- **AND** no frequency difference is published

#### Scenario: Two readings a bin apart
- **GIVEN** two readings separated by exactly one bin width on the same grid
- **WHEN** they are compared
- **THEN** they are reported as separated

#### Scenario: Two files at different sample rates
- **GIVEN** two files whose analyses ran on different resolution grids
- **WHEN** their programme bandwidth is compared
- **THEN** the rule uses each reading's own resolution
- **AND** neither grid is converted, rounded or preferred

### Requirement: State measured facts, and no conclusion about the audio

A measurement comparison SHALL state whether two measured facts are the same, different, or not
comparable, and SHALL NOT state, imply, rank, order or score which file is better, more authentic, of
higher quality, less compressed, more dynamic, or worth keeping.

The system SHALL NOT state or imply that two files hold the same master or recording, that one is a
remaster, transcode, upsample or lossy source, or that one derives from the other. It SHALL NOT emit a
finding, a score, a similarity, a confidence, a count of differences or any other aggregate over the
comparison.

A difference between two values SHALL be published only where the difference is itself a standard
quantity in the unit the domain stores: integrated loudness, in LU. The system SHALL NOT publish a
difference or ratio for true peak or for signal level metrics, whose stored values are linear
amplitudes.

#### Scenario: A large loudness difference is reported without a judgement
- **GIVEN** two files whose integrated loudness differs by several LU
- **WHEN** they are compared
- **THEN** both values and their difference in LU are stated
- **AND** nothing describes either file as louder-than-it-should-be, compressed, hot, better or worse
- **AND** no colour, badge or icon varies with the sign of the difference

#### Scenario: No aggregate is offered
- **WHEN** every comparable measurement agrees
- **THEN** the system offers no single value, flag or phrase meaning "the two files match"

### Requirement: Compare channels by index, and never by an inferred layout

Where a measurement is per channel, the system SHALL compare channels by index and SHALL NOT name,
assume or infer a channel layout.

When the two files carry different channel counts, the system SHALL still compare the overall figures
and SHALL report the per-channel comparison as not comparable, rather than comparing the channels the two
files happen to share.

#### Scenario: A stereo file compared against a multichannel one
- **GIVEN** two files with different channel counts
- **WHEN** their per-channel measurements are compared
- **THEN** the overall figures are compared
- **AND** the per-channel comparison reports that the channel counts differ
- **AND** no channel is described as left, right, centre or any other position
