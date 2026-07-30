# Roadmap

Phased plan. Each phase is delivered as one or more **small, reviewable OpenSpec changes** — not a
single monolithic implementation. Order and scope will adjust as specs are approved. Nothing below
is committed until its OpenSpec change is approved.

## Phase 0 — Foundation *(this session)*

Vision, architecture, ADRs, module plan, privacy/security docs, and the first OpenSpec change
`bootstrap-native-macos-audio-analysis-foundation`. **No app code yet.**

## Phase 1 — MVP: single-file inspection *(deliberately small, vertical-slice-first)*

The first working native app, built as **vertical slices**: a complete runnable flow first, complex
math only afterwards (see [project-principles.md](project-principles.md) #13). Every increment leaves
the app runnable and demoable.

### Phase 1a — Runnable end-to-end slice *(no complex math)*

- **Native-decoding spike first** (ADR-0003): validate AVFoundation/AudioToolbox sufficiency for the
  seven formats against real + synthetic fixtures before committing MVP decoding to native APIs.
- Native macOS app shell (window, empty states, toolbar, menus).
- Import **one** file via drag-and-drop and the file picker (security-scoped bookmarks).
- Inspect behind a probing abstraction — **native-first**, with FFprobe as a dev/reference
  cross-check — **always selecting the audio stream explicitly** so cover art/other streams never
  contaminate results.
- Decode audio (streamed) and show **properties only**: format, codec, duration, bitrate (declared +
  estimated, CBR/VBR), sample rate, declared bit depth, channels; plus a file hash.
- Export the result as versioned JSON (`schemaVersion` 1 — see [json-schema-v1.md](json-schema-v1.md)),
  with empty `measurements`/`findings` at this stage.
- Tests for the slice (import/decode/properties/export; originals unmodified). **No DSP yet.**

### Phase 1b — Add analysis incrementally *(each step still runnable)*

Only once 1a runs end-to-end, add — one small increment at a time:

- Simple level metrics (arithmetic): sample peak, RMS, DC offset, basic clipping.
- **Loudness (complex):** integrated LUFS and true peak (oversampling), cross-checked vs FFmpeg
  `ebur128`.
- **Spectral visuals (complex):** full waveform, average spectrum (FFT), basic spectrogram, and the
  significant max frequency.
- Effective-bit-depth estimate; cautious, well-explained findings with confidence + a plain summary.
- **No ML, no speculative complex detections yet.**

## Phase 2 — Batch, integrity & persistence

- Multiple files, folders, batch analysis, per-file + global progress, cancellation, retry.
- Container/codec integrity checks (truncation, decode errors, header/duration/bitrate mismatches,
  declared vs decoded sample rate/channels, extra streams, suspicious metadata).
- SwiftData result store with versioned fingerprint cache and invalidation.
- Cryptographic file hashes + decoded-PCM hash where appropriate.

## Phase 3 — Loudness, dynamics & master analysis

- Full loudness suite (LUFS M/S/I, LRA, momentary/short-term timeline, crest factor, DR).
- Master/dynamics indicators: brickwall limiting, clipping (digital/analog-likely), reduced
  dynamics, elevated gain, de-clipping/declip artifacts, apparent normalization.

## Phase 4 — Spectral & bit-depth/sample-rate forensics

- Spectrogram, per-window spectra, band energy, centroid, rolloff, time-varying spectral limit,
  aliasing/ultrasonic content, "empty" high-sample-rate content.
- Effective bit depth, LSB/dither analysis, 16→24 padding, inflated sample rate, resampling
  images.

## Phase 5 — Source evidence engine (transcoding & analog)

- The weighted multi-indicator evidence engine for transcoding (MP3/AAC/Opus/…): outputs *none /
  weak / possible / strong / inconclusive* with confidence and explanation.
- Analog-source indicators — vinyl (clicks, crackle, rumble, hum, wow/flutter, channel balance,
  inner-groove distortion, RIAA/EQ issues, over-de-noising) and tape (hiss, wow/flutter, hum,
  dropouts, HF loss, saturation, print-through, azimuth, speed drift).

## Phase 6 — Channels, phase, noise & electrical issues

- Stereo correlation, phase, mid/side, mono compatibility, duplicated/inverted channels, false
  stereo, polarity, inter-channel delay/imbalance, mono-sum cancellation.
- 50/60 Hz hum + harmonics, ground noise, interference, stationary noise, periodic clicks,
  glitches, dropouts, anomalous digital silence.

## Phase 7 — Version comparison & "which copy to keep"

- Select 2+ versions; time-align, compensate silence, estimate offset, normalize only for
  comparison, detect polarity/channel inversion; compare duration/waveform/dynamics/spectrum/
  loudness/noise/frequency response; correlation + residual; "B appears derived from A."
- A comprehensible "which copy to keep" comparison (integrity, degradation, dynamics, clipping,
  spectral response, noise, capture, fidelity) — never auto-picking highest SR/bitrate/bit depth.

## Phase 8 — Polish, packaging & distribution

- Accessibility/VoiceOver pass, Quick Look, contextual menus, export/import panels.
- CI matrix (build/test/lint/spec-validation) on a verified macOS + Xcode runner combination.
- Sandbox hardening and distribution (signing, hardened runtime, notarization). Licensing is
  settled (MIT, ADR-0007); the app ships without bundled FFmpeg (ADR-0003).

## Explicitly deferred / possible future

- **CLI executable** (`audio-inspector`) for batch/headless analysis — added only when an analysis
  engine has a real headless consumer (the reason a host executable was dropped from the initial
  package; see ADR-0001).
- AccurateRip verification for CD rips.
- Core ML-assisted detection (only if a phase justifies it).
- Tag writing (opt-in, confirmed, never during analysis).
