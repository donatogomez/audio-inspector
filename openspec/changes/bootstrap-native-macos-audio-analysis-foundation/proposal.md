## Why

Audio Inspector needs a solid, spec-driven foundation and a deliberately small first slice before
any large analysis work begins. Music collectors and archivists have no native macOS tool that
inspects the **signal** (not just the tags) and explains, with confidence levels, what can and
cannot be known about a file's source and integrity. This change establishes the project's
architecture, decisions, and the MVP: import one file and report accurate, cautiously-explained
technical facts about it — locally, non-destructively, natively.

## What Changes

- Establish the project foundation: vision, architecture, ADRs, module plan, privacy/security
  docs, and the OpenSpec workflow itself (documentation only — no runtime behavior).
- Introduce the **MVP capabilities** for single-file forensic inspection:
  - Import a single audio file via drag-and-drop and the file picker, using security-scoped
    bookmarks; originals are never modified.
  - Probe container/codec/technical facts behind an implementation-agnostic abstraction, **always
    selecting the audio stream explicitly** so cover art / non-audio streams never contaminate
    results.
  - Decode audio (streamed, cancellable) and compute level & loudness metrics: sample peak, true
    peak, RMS, LUFS integrated, basic clipping, DC offset.
  - Produce visualization data: full waveform, average spectrum, a basic spectrogram, and the
    significant maximum frequency.
  - Present a two-level report (plain summary + technical view) with **cautious, well-explained
    warnings** and confidence, and export the result as JSON.
- Scope guardrails: single file only (batch is a later change); **no ML**; no speculative complex
  detections (transcoding engine, analog-source detection, comparison, persistence cache come in
  later changes).

No **BREAKING** changes — this is greenfield.

## Capabilities

### New Capabilities

- `file-import`: Bringing a single audio file into the app via drag-and-drop and the file picker
  using security-scoped bookmarks, read-only, with graceful handling of unsupported/invalid files.
- `audio-inspection`: Extracting container, codec, and technical facts (format, duration, bitrate
  declared/estimated + CBR/VBR, sample rate, bit depth declared + effective estimate, channels,
  metadata, cover-art presence, file hashes) via an implementation-agnostic probing abstraction
  that always targets the audio stream.
- `level-loudness-metrics`: Computing sample peak, true peak, RMS, LUFS integrated, basic clipping,
  and DC offset from decoded PCM using a documented, versioned methodology.
- `spectral-visualization`: Producing waveform, average spectrum, a basic spectrogram, and the
  significant maximum frequency for display.
- `analysis-reporting`: Assembling a two-level (plain + technical) report with cautious warnings
  and confidence levels, tagged with the analysis engine version, and exporting it as JSON.

### Modified Capabilities

None — no existing specs.

## Impact

- New repository structure: `docs/` (vision, architecture, methodology, privacy, roadmap), `docs/adr/`
  (ADR-0001…0007), root docs (README, CONTRIBUTING, SECURITY), tooling config, and OpenSpec setup.
- New code (implemented in the tasks phase, on implementation branches): one Swift package
  `AudioInspectorKit` (`swift-tools-version: 6.2`) with targets `AudioInspectorDomain`,
  `AudioInspectorAnalysis`, `AudioInspectorMedia`, `AudioInspectorTesting`, `FeatureImport`,
  `FeatureAnalysis`, and `AudioInspectorApp` (library composition root), a boundary script, a PR
  template, plus a thin Xcode macOS `.app` target (`com.donatogomez.audioinspector`) reusing the
  composition root. No host executable. See docs/architecture.md and ADR-0001/0005.
- Dev/test dependency on FFmpeg/FFprobe (behind an abstraction; not required by the shipped app —
  see ADR-0003). No network, no telemetry, no modification of user files.
- Decisions now settled: license **MIT** (ADR-0007), bundle id `com.donatogomez.audioinspector`,
  `swift-tools-version: 6.2`, **no bundled FFmpeg** in the MVP (ADR-0003), no host executable.
- Open item pending validation (not a decision to make now): native-API decoding **sufficiency**,
  to be confirmed by an early Phase-1 spike (ADR-0003).
