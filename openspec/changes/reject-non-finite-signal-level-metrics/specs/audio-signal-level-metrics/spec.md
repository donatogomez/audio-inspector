## MODIFIED Requirements

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

**Every reported metric SHALL be a finite number.** Samples are finite by construction at the decoding
boundary, and each of these metrics is bounded by the largest magnitude among them — the mean and the
root-mean-square can never exceed the peak absolute value — so a finite input always has a finite
result. The system SHALL compute them in a way that cannot overflow on the way to that result, and the
value reported SHALL be the measured one: a metric that cannot be represented SHALL NEVER be reported as
zero, as a limit, or as any other substituted number.

A metric that genuinely cannot be described SHALL NOT be published as a measurement at all. The system
SHALL report the whole reading as failed instead, distinctly from the "not computable" state that
belongs to a channel which carried no samples.

#### Scenario: A well-formed file's level metrics are reported per channel

- **WHEN** a file with two channels is inspected
- **THEN** peak, DC offset, RMS and the clipped-sample count are each reported for both channels
  individually

#### Scenario: A file with no clipped samples reports a zero count, not an absence

- **WHEN** a file's samples never reach the clipping threshold
- **THEN** the clipped-sample count is reported as zero, distinct from a metric that could not be
  computed at all

#### Scenario: Samples of extreme magnitude still produce finite metrics

- **WHEN** a file's samples are finite but of extreme magnitude, up to the largest value the sample
  representation can hold
- **THEN** every reported metric is finite and equal to the mathematically correct value, and the result
  does not depend on how the file was divided into chunks while reading it

#### Scenario: An unrepresentable reading is failed, never substituted

- **WHEN** a level metric cannot be represented as a finite number
- **THEN** the reading is reported as failed, and no substituted or partial value is published in its
  place
