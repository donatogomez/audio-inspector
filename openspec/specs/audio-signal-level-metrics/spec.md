# audio-signal-level-metrics Specification

## Purpose
TBD - created by archiving change add-computed-technical-properties. Update Purpose after archive.
## Requirements
### Requirement: Measure objective sample-level signal metrics

The system SHALL compute, from the file's decoded audio samples, the following per-channel metrics, each
a direct mathematical fact requiring no judgement about audio quality: the peak absolute sample value,
the mean sample value (DC offset), the root-mean-square level, and a count of samples at or beyond a
fixed, published clipping threshold. Each metric SHALL also be reported per file where a single-number
summary across channels is meaningful.

These metrics are **signal-derived** and are therefore never fields of the basic, metadata-only technical
properties (`audio-file-inspection`'s own "no DSP" rule): they live in their own capability, computed by
reading the file's decoded PCM once, independently of the waveform and the spectrogram, with its own
cancellation.

The clipping threshold SHALL be a named constant tied to the analysis engine version; changing it SHALL
be treated as changing the engine version, per this project's existing versioning rule for measured
constants.

No metric here SHALL be characterised as good, bad, excessive, or indicative of any quality judgement.
The system reports what was measured; it does not evaluate it.

#### Scenario: A well-formed file's level metrics are reported per channel

- **WHEN** a file with two channels is inspected
- **THEN** peak, DC offset, RMS and the clipped-sample count are each reported for both channels
  individually

#### Scenario: A file with no clipped samples reports a zero count, not an absence

- **WHEN** a file's samples never reach the clipping threshold
- **THEN** the clipped-sample count is reported as zero, distinct from a metric that could not be
  computed at all

#### Scenario: Silence is reported honestly

- **WHEN** a channel's samples are all zero
- **THEN** its peak and RMS are reported as zero and its DC offset is reported as zero, with no
  characterisation of the audio as empty, broken, or of any particular quality

#### Scenario: The metrics do not depend on how the file was read

- **WHEN** the same file's samples are decoded in different chunk sizes
- **THEN** every metric is identical regardless of chunk size, matching the order-independence already
  proven for the waveform envelope

#### Scenario: Level metrics never alter the report, the export, or the other visualisations

- **WHEN** level metrics are computed alongside the report, the waveform and the spectrogram
- **THEN** none of the technical properties, the warnings, the global status, the waveform, or the
  spectrogram change as a result, and the `schemaVersion` 1 export's existing fields remain
  byte-identical

### Requirement: Estimate the true (inter-sample) peak from a reconstructed waveform

The system SHALL estimate, for each channel and for the file overall, the **true peak**: the maximum
absolute value of the band-limited waveform the channel's samples represent, including the values the
waveform takes **between** stored samples. It SHALL be estimated by oversampling the signal before peak
detection, by a factor of at least four relative to the practice ITU-R BS.1770 / EBU R128 defines, and
SHALL NEVER be derived from the stored samples alone.

The overall value SHALL be the maximum of the per-channel values, since a maximum of maxima is exact.

The estimate SHALL NEVER be reported below that channel's own sample peak: a value the file literally
contains is part of the waveform being reconstructed.

Values SHALL be carried in the same linear amplitude scale as every other measured amplitude, never in
decibels, and SHALL NEVER be clamped — a file whose waveform exceeds full scale reports a value above
full scale.

A channel that carried no audio frames SHALL report the true peak as **not computable**, distinct from a
channel that was measured and is silent, whose true peak is a genuine, computed zero.

#### Scenario: An inter-sample peak above the highest stored sample

- **WHEN** a file whose every stored sample is at or below full scale is measured, and its reconstructed
  waveform rises above full scale between two samples
- **THEN** the true peak is reported above full scale, while the sample peak continues to be reported at
  or below it, as two separate values

#### Scenario: The estimate never falls below the stored samples

- **WHEN** any file is measured
- **THEN** each channel's true peak is greater than or equal to that channel's own sample peak

#### Scenario: Silence is measured, not treated as absent

- **WHEN** a channel's samples are all zero
- **THEN** its true peak is reported as a measured zero, not as "not computable"

#### Scenario: A channel with no frames reports no value

- **WHEN** a channel carried no audio frames at all
- **THEN** its true peak is reported as not computable, never as zero and never as a fabricated number

### Requirement: Record the methodology that produced a true peak

The system SHALL record, with every true peak it reports, the **oversampling factor** and the
**interpolation filter** used to produce it, so a reader can tell which methodology produced the number.

The oversampling factor and the filter SHALL be named constants tied to the analysis engine version and
SHALL NEVER be user-configurable: a measurement a user could retune would make the same file produce
different results across runs.

Given the same input and the same engine version, the reported true peak SHALL be identical.

#### Scenario: The method travels with the value

- **WHEN** a true peak is reported, in the interface or in an export
- **THEN** the oversampling factor and the interpolation filter that produced it are reported with it

#### Scenario: The same file measures the same way twice

- **WHEN** the same file is measured twice with the same engine version
- **THEN** the reported true peak values are identical

#### Scenario: No configuration surface

- **WHEN** the application is used in any supported way
- **THEN** no oversampling factor, filter or threshold of this measurement can be changed by the user

### Requirement: A true peak is reported as a measurement, never as a verdict

The system SHALL report the true peak as a measured value with its unit and its method, and SHALL NOT
characterise it as clipping, distortion, damage, unsafe, excessive, or as an indication of quality of
any kind. A true peak above full scale SHALL NOT be described as clipping, and SHALL NOT be given
colour, weight or emphasis that a value below full scale does not receive.

Reporting a true peak — including one above full scale, and including a failure to measure it — SHALL
NOT emit an inspection warning, SHALL NOT change the global inspection status, and SHALL NOT alter any
technical property, the waveform, the spectrogram, or the sample-level signal metrics.

#### Scenario: A true peak above full scale is stated, not judged

- **WHEN** a file's true peak exceeds full scale
- **THEN** the value is reported with its unit and method, with no characterisation of the file, its
  master, or its quality

#### Scenario: The measurement does not disturb the inspection

- **WHEN** the true peak is measured, fails to be measured, or is cancelled
- **THEN** the technical properties, the warnings, the global status, the waveform, the spectrogram and
  the sample-level metrics are unchanged, and an export produced without a true peak is byte-identical
  to one produced before this measurement existed

### Requirement: True peak and the clipped-sample count are independent facts

The system SHALL report the true peak and the clipped-sample count as **separate** measurements, and
SHALL NOT derive either from the other. A clipped-sample count of zero SHALL NOT prevent a true peak
above full scale from being reported, and a true peak above full scale SHALL NOT be reported as, or
converted into, a count of clipped samples.

#### Scenario: No clipped samples, true peak above full scale

- **WHEN** a file has no sample at or beyond full scale but its reconstructed waveform exceeds it
- **THEN** the clipped-sample count is reported as zero and the true peak is reported above full scale,
  with neither value contradicting or overriding the other

#### Scenario: Clipped samples present

- **WHEN** a file contains samples at or beyond full scale
- **THEN** the clipped-sample count is reported as the number of such samples and the true peak is
  reported at or above full scale, as two separate facts

#### Scenario: Neither condition present

- **WHEN** a file's samples and its reconstructed waveform both stay below full scale
- **THEN** the clipped-sample count is zero and the true peak is reported below full scale

