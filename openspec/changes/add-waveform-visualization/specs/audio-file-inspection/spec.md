## MODIFIED Requirements

### Requirement: Read basic technical properties without DSP

The system SHALL read only metadata-level technical properties that do not require sample
processing: container/type, duration, sample rate, channel count, bit depth (only when reliably
determinable), codec/encoding (only when reliably determinable), and bitrate (declared and/or
estimated). **The extraction of these properties** MUST NOT process samples: no technical property may
be derived from decoded audio, and in particular none may be derived from a spectral transform, a
loudness measure, or a waveform.

This prohibition governs **how the technical properties are obtained**, not what the system as a whole
may do. Reading samples for a purpose other than deriving a technical property is outside its scope,
and any such reading MUST NOT alter which properties are reported, their values, their states, the
warnings, or the global inspection status.

#### Scenario: Properties read from a well-formed file

- **WHEN** a well-formed audio file is inspected
- **THEN** the system reports the properties the format exposes (e.g. duration, sample rate, channel
  count) as measured facts, computed from metadata only

#### Scenario: Declared vs estimated bitrate are distinct

- **WHEN** bitrate information is available
- **THEN** the system reports a declared bitrate and an estimated bitrate as **separate** fields,
  never conflating the two

#### Scenario: Sample processing elsewhere does not reach the properties

- **WHEN** the same file is inspected once with sample processing performed for another purpose and
  once without it
- **THEN** the technical properties, their states, the warnings and the global inspection status are
  identical in both cases
