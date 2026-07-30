## ADDED Requirements

### Requirement: Report container and codec technical facts

The system SHALL extract and display the following facts for an imported file: file name, path,
extension, container, codec, size, duration, declared bitrate, estimated average bitrate, CBR vs
VBR, sample rate, declared bit depth, channel count, channel layout, and modification date.
Extraction SHALL occur behind an implementation-agnostic probing abstraction so the domain does not
depend on any particular tool (native API or FFprobe).

#### Scenario: Facts extracted for a supported file

- **WHEN** a supported file is imported and inspected
- **THEN** the system presents the container, codec, duration, sample rate, declared bit depth,
  channel count and layout, and file size, each labelled as a measured fact

#### Scenario: Declared vs estimated bitrate and CBR/VBR

- **WHEN** a compressed file (e.g. MP3 or AAC) is inspected
- **THEN** the system shows the declared bitrate, an estimated average bitrate derived from the
  audio stream, and whether the stream is constant or variable bitrate

### Requirement: Select the audio stream explicitly

The system SHALL always operate on the file's audio stream. Cover art, video, or other non-audio
streams MUST NOT contribute to any computed metric.

#### Scenario: File with embedded cover art

- **WHEN** a file containing embedded cover art (an attached picture stream) is inspected
- **THEN** the reported technical facts and all downstream metrics are derived solely from the
  audio stream, and the presence of cover art is reported separately as metadata, not as audio

### Requirement: Estimate effective bit depth distinctly from declared bit depth

The system SHALL report the container's declared bit depth and, where it can be estimated, an
effective bit depth for the signal, clearly distinguishing the two.

#### Scenario: 24-bit container carrying 16-bit signal

- **WHEN** a file declared as 24-bit is inspected but its lower bits carry no real signal
- **THEN** the system reports declared bit depth as 24 and presents an effective-bit-depth estimate
  indicating the signal occupies ~16 bits, labelled as an estimate with a confidence level

### Requirement: Compute file and audio hashes

The system SHALL compute a cryptographic hash of the file bytes, and, where appropriate, a hash of
the decoded PCM audio, so identical bytes and identical audio can be distinguished later.

#### Scenario: Hashes computed for an imported file

- **WHEN** a file is inspected
- **THEN** the system records a cryptographic file hash and, when audio is decoded, a decoded-PCM
  hash, both available in the technical view
