## ADDED Requirements

### Requirement: Generate waveform data

The system SHALL produce waveform data for the full file suitable for display, computed from the
audio stream in a bounded-memory, streamed fashion.

#### Scenario: Waveform for a full file

- **WHEN** a supported file is analyzed
- **THEN** the system produces waveform overview data spanning the entire duration without loading
  the whole decoded track into memory at once

### Requirement: Generate an average spectrum

The system SHALL compute an average magnitude spectrum of the audio using a documented FFT
configuration (window, size), reported with the engine version.

#### Scenario: Average spectrum computed

- **WHEN** a supported file is analyzed
- **THEN** the system produces an average spectrum across the file, with the FFT window and size
  recorded in the technical view

### Requirement: Generate a basic spectrogram

The system SHALL compute a basic time–frequency spectrogram of the audio for display.

#### Scenario: Spectrogram computed

- **WHEN** a supported file is analyzed
- **THEN** the system produces spectrogram data (time × frequency × magnitude) suitable for
  rendering

### Requirement: Estimate the significant maximum frequency over time

The system SHALL estimate the highest frequency carrying meaningful energy above the local noise
floor, measured over time rather than as a single global fixed threshold. The result SHALL be
presented as evidence with a confidence level, and MUST NOT by itself be used to assert
transcoding.

#### Scenario: Persistent low-pass cutoff detected

- **WHEN** a file exhibits a spectral cutoff that persists across most of its duration
- **THEN** the system reports the estimated significant maximum frequency and the cutoff's
  persistence as evidence, explicitly noting alternative explanations (master, deliberate
  filtering, analog bandwidth) rather than declaring transcoding

#### Scenario: Full-bandwidth file

- **WHEN** a file has significant energy up to near the Nyquist frequency
- **THEN** the system reports a high significant maximum frequency and does not raise a
  bandwidth-limitation warning
