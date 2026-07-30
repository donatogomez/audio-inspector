## Why

The project skeleton builds but does nothing. The first functional vertical slice must prove the
whole end-to-end path — select → open → read basic properties → show → export — **before any DSP**
(see `docs/project-principles.md` #13). This de-risks file access, the domain/infra boundary, the
result model, and JSON export while adding zero forensic analysis.

## What Changes

- Introduce a single vertical slice: the user selects a **local audio file** via the native panel;
  the app opens it, reads **basic technical metadata** (no sample processing), presents a
  **structured result**, and can **export it as `schemaVersion` 1 JSON**.
- Model each property with an **explicit state** — `available` / `unavailable` / `unsupported` /
  `uncertain` / `failed` — so nothing is invented and inferences are never shown as facts.
- Keep the **domain pure**: technical extraction sits behind a port implemented later by
  infrastructure; the domain never imports AVFoundation, URL-bookmark APIs, SwiftUI, or JSONEncoder.
- Define the **first exportable JSON contract** (`schemaVersion` 1) with a **sandbox-safe** file
  representation (no absolute private path by default).

This change is **spec only** — no Swift, no `Package.swift`, no Xcode changes. Implementation
follows in later commits/changes.

## Capabilities

### New Capabilities

- `audio-file-inspection`: Selecting a single local audio file, reading its basic technical
  properties without DSP, representing each property's availability/certainty explicitly, producing
  a structured inspection report with warnings and a global status, and exporting it as
  `schemaVersion` 1 JSON.

### Modified Capabilities

None accepted yet. (The still-active `bootstrap-native-macos-audio-analysis-foundation` change
*proposes* overlapping capabilities `file-import` / `audio-inspection` / `analysis-reporting`, but
those are not accepted specs. Reconciling/retiring that umbrella change is flagged as an open
governance decision in `design.md`.)

## Impact

- New OpenSpec change artifacts + the `audio-file-inspection` capability spec.
- New ADRs: property-state model, domain-report vs JSON-contract separation, sandboxed file access.
- Reconciled `docs/json-schema-v1.md` (concrete `schemaVersion` 1 field contract for the first
  export).
- **No production code touched.** Scope excludes: waveform, FFT, spectrogram, LUFS, true peak,
  clipping, phase, dynamic range, silence detection, transcode/codec-authenticity detection,
  fingerprinting, metadata editing, batch import, drag-and-drop, persistence, recent files, file
  comparison, FFmpeg, any quality score, and any forensic conclusion.
