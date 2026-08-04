## ADDED Requirements

### Requirement: Present the report in human terms without interpreting quality

The system SHALL present the inspection report using vocabulary and formatting intended for a person, and
MUST NOT expose internal identifiers on its primary surface: enum case names, stable warning or error
codes, wire-format field keys, raw Uniform Type Identifiers, or codec tokens for which a comprehensible
name is known. Values that have a unit or a scale — byte counts, durations, sample rates, bitrates, dates
— SHALL be formatted for reading, while preserving the exact underlying value as secondary detail or in
the export, so no precision is lost. The system MUST NOT fabricate information while formatting: a label
may name only what the domain actually carries.

Presentation SHALL NOT interpret the quality of the audio. It may name a value and may state that a value
is absent, undefined for the format, unreliable or unreadable, but it MUST NOT characterise any value as
good, bad, better, worse, high or low, and MUST NOT imply that a larger number is preferable. Colour and
iconography SHALL communicate only the state of the inspection, never quality; in particular, a value
that is unreliable or not defined by the format SHALL NOT be presented as an error or a defect of the
file.

The presented report SHALL remain usable without sight of colour: no information may be conveyed by
colour alone, each property SHALL be reachable as a single coherent element by an assistive reader, and
the report SHALL remain legible at the system's accessibility text sizes.

This requirement governs presentation only. The properties read, their states, the warnings, the global
status, the safe origin descriptor and the exported JSON contract are unchanged by it.

#### Scenario: No internal identifier reaches the primary surface

- **WHEN** a report is presented for any file, whatever the outcome of the inspection
- **THEN** no enum case name, stable code, wire-format field key, raw Uniform Type Identifier, or
  known-nameable codec token appears as primary text

#### Scenario: Values are formatted for a reader

- **WHEN** a property carries a byte count, a duration, a sample rate, a bitrate or a date
- **THEN** it is presented in a readable form with its unit, and the exact underlying value remains
  available as secondary detail or in the export

#### Scenario: A technical token without a known name is shown unchanged

- **WHEN** a codec or container token has no comprehensible name available
- **THEN** the token is presented as it is, and no name is guessed for it

#### Scenario: Absence is presented without judgement

- **WHEN** a property is unavailable, not defined by the format, or unreliable
- **THEN** the report states which of those it is, in plain words, without presenting it as an error, a
  defect, or a statement about the quality of the file

#### Scenario: A failed reading is marked as a failure of the reading

- **WHEN** a property could not be read
- **THEN** the report says so and may mark it, always with words beside any colour or symbol, without
  implying a defect of the file

#### Scenario: Presentation never judges quality

- **WHEN** any value, state, warning or status is presented
- **THEN** no text, colour or symbol characterises it as good, bad, better, worse, high or low, and none
  implies that a larger value is preferable

#### Scenario: The report is reachable without colour or sight

- **WHEN** the report is read with an assistive reader, or by a user who cannot distinguish colour
- **THEN** every property is exposed as one coherent element with its name, value and state, and no
  information depends on colour alone
