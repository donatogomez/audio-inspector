## ADDED Requirements

### Requirement: Measure the highest frequency carrying persistent signal energy

The system SHALL measure, from the file's decoded samples, the highest frequency region that carries
signal energy above a stated threshold in at least a stated fraction of analysis windows, and SHALL
report it as a measured fact with no interpretation of its cause.

The measurement SHALL be derived from the samples at the analysis transform's own resolution. It SHALL
NOT be derived from any representation reduced for display, because such a representation reduces over
time by maximum — which cannot distinguish an isolated transient from persistent content — and its
resolution is a presentation parameter rather than a property of the file.

The measurement SHALL depend only on the file's content and the recorded methodology. It SHALL NOT
depend on the chunk size the samples were read in.

#### Scenario: A file whose content stops at a known frequency

- **WHEN** a file carries persistent tones up to a known highest frequency and nothing above it
- **THEN** the reported frequency is that highest frequency, within the stated resolution

#### Scenario: An isolated transient does not widen the reported band

- **WHEN** a file is otherwise silent except for a single broadband impulse
- **THEN** the impulse's energy does not raise the reported frequency, because it is present in too few
  analysis windows to meet the persistence criterion

#### Scenario: Persistent low-level content is reported

- **WHEN** a file carries a band of energy that is quiet but present throughout
- **AND** that band is above the stated threshold
- **THEN** it is included in the reported frequency, and is not discarded for being quiet

#### Scenario: The result does not depend on how the file was read

- **WHEN** the same file is analysed in different chunk sizes
- **THEN** the reported frequency is identical

### Requirement: State the measurement's methodology and its resolution

The system SHALL record, with every measurement, the identity of the algorithm that produced it, the
threshold and persistence criterion it applied, and the frequency resolution the answer is quantised
to.

The system SHALL NOT report the frequency at a precision finer than that resolution, in any surface or
document, because a value stated more precisely than it was measured asserts a certainty that does not
exist.

#### Scenario: The resolution travels with the value

- **WHEN** a measurement is produced at any supported sample rate
- **THEN** it carries the frequency resolution of the transform that produced it

#### Scenario: The same signal at a different sample rate

- **WHEN** the same described signal is analysed at two different sample rates
- **THEN** the two reported frequencies agree within their stated resolutions

### Requirement: Report a bandwidth only where one can be measured honestly

The system SHALL report no frequency when the file offers nothing to measure: when it carries no audio,
when it is shorter than a single analysis window, or when no frequency meets the threshold and
persistence criterion.

An absence SHALL be reported as an absence. The system SHALL NOT substitute zero, Nyquist, the declared
sample rate, or any floor value for a measurement that was not made.

#### Scenario: A file shorter than one analysis window

- **WHEN** a file contains fewer samples than one transform window
- **THEN** no bandwidth is reported, and no value is substituted

#### Scenario: Digital silence

- **WHEN** a file contains only digital silence
- **THEN** no bandwidth is reported, and neither zero nor Nyquist is presented as a result

#### Scenario: An absent bandwidth leaves everything else untouched

- **WHEN** no bandwidth can be measured for a file
- **THEN** every other analysis of that file reports its own result unchanged

### Requirement: Draw no conclusion about origin, quality or provenance

The system SHALL present the measurement as a fact about the signal and SHALL NOT assert, imply or
suggest that a file has been upsampled, transcoded, compressed with a lossy codec, or derived from any
particular source.

The system SHALL NOT characterise the value as good, bad, sufficient, insufficient, suspicious or
unnecessary, SHALL NOT compare it against the declared sample rate as a verdict, and SHALL NOT emit a
finding.

#### Scenario: A high-rate file whose content stops well below its Nyquist

- **WHEN** a file declares 96 kHz and carries no persistent energy above roughly 22 kHz
- **THEN** the measurement is reported as the frequency it is
- **AND** nothing states or implies that the file was upsampled, transcoded or is of lower quality

#### Scenario: A band limit characteristic of a lossy encoder

- **WHEN** a file carries a band limit of the kind a lossy encoder introduces
- **THEN** the measurement reports the frequency
- **AND** no codec, encoder or bitrate is named
