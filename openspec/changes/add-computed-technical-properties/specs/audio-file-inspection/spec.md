## MODIFIED Requirements

### Requirement: Read basic technical properties without DSP

The system SHALL read only metadata-level technical properties that do not require sample
processing: container/type, duration, sample rate, channel count, bit depth (only when reliably
determinable), codec/encoding (only when reliably determinable), and bitrate (declared, framework-estimated,
and/or calculated from file size and duration). **The extraction of these properties** MUST NOT process
samples: no technical property may be derived from decoded audio, and in particular none may be derived
from a spectral transform, a loudness measure, or a waveform.

This prohibition governs **how the technical properties are obtained**, not what the system as a whole
may do. Reading samples for a purpose other than deriving a technical property is outside its scope,
and any such reading MUST NOT alter which properties are reported, their values, their states, the
warnings, or the global inspection status.

A bitrate **calculated from the file's total size and its duration** SHALL be reported as a field
distinct from both the declared and the framework-estimated bitrate, and SHALL NEVER be reported as
`available`: it is always an approximation, because the file's total size includes container overhead
(headers, tags, embedded artwork) the calculation cannot separate from the audio payload. It SHALL be
computed only when both the file's size and a confirmed, positive duration are known, and SHALL be
absent (not fabricated, not zero) otherwise.

#### Scenario: Properties read from a well-formed file

- **WHEN** a well-formed audio file is inspected
- **THEN** the system reports the properties the format exposes (e.g. duration, sample rate, channel
  count) as measured facts, computed from metadata only

#### Scenario: Declared, estimated and calculated bitrate are three distinct facts

- **WHEN** bitrate information is available in any form
- **THEN** the system reports a declared bitrate, a framework-estimated bitrate, and a
  size/duration-calculated bitrate as **three separate** fields, never conflating any two of them

#### Scenario: A calculated bitrate is never presented as a declared or a reliable fact

- **WHEN** the system computes a bitrate from the file's size and duration
- **THEN** it is reported as an approximation, never as `available`, and the report does not claim it
  represents the audio payload's true encoded rate

#### Scenario: A calculated bitrate is absent when its inputs are absent

- **WHEN** the file's size cannot be read, or the duration is not a confirmed positive value
- **THEN** the calculated bitrate is reported as absent, never as zero and never as a fabricated number

#### Scenario: Sample processing elsewhere does not reach the properties

- **WHEN** the same file is inspected once with sample processing performed for another purpose and
  once without it
- **THEN** the technical properties, their states, the warnings and the global inspection status are
  identical in both cases
