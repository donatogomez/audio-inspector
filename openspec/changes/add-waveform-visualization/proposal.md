## Why

The product's premise is that it examines the **signal**, not the tags — and nothing in the codebase
reads a single sample. Selection, drag & drop, property extraction, the report and the JSON export are
all derived from metadata. The only requirement that mentions samples says they must not be touched.

A **static waveform** — read the samples once, draw them once, no interaction — is the thinnest slice
that changes that. Its arithmetic is trivial on purpose: a minimum and a maximum per bucket. What it is
really for is the path underneath it — opening a decoded stream, reading it in bounded chunks,
honouring cancellation, and failing honestly — the seam every later visual and every later metric
depends on. Building that seam under a min/max reduction means a defect in the seam cannot hide behind
a defect in the maths.

The decoding strategy is no longer a guess. The spike merged in
[#24](https://github.com/donatogomez/audio-inspector/pull/24) —
`docs/spikes/2026-08-05-native-pcm-decoding-validation.md`, reproducible from `main` — established with
measurements that `AVAudioFile` opens and fully decodes WAV, AIFF, ALAC, FLAC and AAC to one uniform
processing format, that frames read match the declared `length`, that channel identity survives, and
that native float PCM preserves values beyond ±1 untouched. It also produced the finding that shapes
the code: **the buffer region past `frameLength` is never safe**, so a reader must consume exactly
`frameLength` frames and never `frameCapacity`.

This change turns that evidence into a working slice, and closes the one gap the spike could not:
**MP3 was never decoded at all**, because macOS cannot encode it and the spike only wrote its own
fixtures.

## What Changes

- **A domain port for producing a waveform**, implemented in `AudioInspectorMedia`, expressed purely in
  domain value types. No `AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat` or Apple error crosses it
  (ADR-0011).
- **One pass over the samples**, in bounded chunks, cancellable at chunk boundaries, reduced as it goes.
  The decoded track is never held in memory in full.
- **Exactly `frameLength` frames are consumed per read, never `frameCapacity`.** This is an explicit,
  test-enforced invariant, not a convention — the spike showed the region beyond it holds either the
  caller's previous contents or deterministic, content-derived audio the API declined to report.
- **A combined min/max envelope across all channels, never an average.** Averaging lets two channels in
  opposing phase cancel and draws a flat line for a file that is not flat. It is not a mono mix and must
  not be named as one.
- **No normalisation, per file or otherwise.** Buckets stay on the sample scale `[-1, 1]`, so a quiet
  file is drawn quiet and a file near full scale is drawn large, and two files stay comparable.
- **A resolution independent of the view's width**, capped at 2048 buckets. Resizing never decodes again.
- **The waveform sits beside the `InspectionReport`, never inside it**, and never in the
  `schemaVersion` 1 JSON.
- **A waveform failure is neutral with respect to the report.** If the samples cannot be read while the
  properties were read fine, the report is presented exactly as today and the waveform's absence is
  stated. No warning, no change of inspection status.
- **No interaction**: no playback, zoom, scrubbing, selection or cursor.

`AudioInspectorAnalysis` stays empty. A per-bucket minimum and maximum is a fold performed while
reading, not a transform over a buffer; `design.md` states the condition that would move it.

## Capabilities

### New Capabilities

- `waveform-visualization`: producing a bounded, view-independent amplitude envelope from the file's
  decoded samples and presenting it as a still drawing beside the report, without interpreting it.

### Modified Capabilities

- `audio-file-inspection`: the requirement **Read basic technical properties without DSP** states that
  *the system* MUST NOT perform any DSP and names `waveform` among the prohibited operations. Read
  literally, it forbids this change outright. The prohibition is **scoped to what it was protecting** —
  that the technical properties are derived from metadata alone, never from processed samples — so that
  reading samples for a separate purpose is no longer forbidden by a requirement about property
  extraction. **The title, both existing scenarios and every other requirement in the capability are
  unchanged**, and no property, state, warning, status or JSON field changes meaning.

## Impact

- **Affected specs:** `waveform-visualization` (new, `ADDED`) and `audio-file-inspection` (one
  `MODIFIED` requirement, narrowing scope only).
- **Affected decisions:** **ADR-0015** records the sample-reading seam — `AVAudioFile` over
  `AVAssetReader`, the `frameLength` invariant, and the reduction living in Media. It cites the spike
  report and **references ADR-0003 without editing it**. It stays **Proposed** until the format matrix
  passes against the real adapter, MP3 included, and the manual validation is done.
- **Affected code:** a new port in `AudioInspectorDomain`, its adapter in `AudioInspectorMedia`, a fake
  in `AudioInspectorTesting`, the waveform surface in `FeatureAnalysis`, and the wiring in
  `AudioInspectorApp` — including the security-scoped access window, which today closes when the
  inspection returns.
- **Affected tests:** unit tests for the bucket arithmetic and the envelope's honesty rules, adapter
  integration tests over the format matrix, and end-to-end assertions that a report still presents when
  the waveform is absent. Existing assertions are updated only where a state type gains a field; **none
  is removed or weakened.**
- **Explicitly unchanged:** the `schemaVersion` 1 contract and its exporter, `InspectionReport`,
  `TechnicalProperties`, `Property`, the warning and status model, the property reader, drag & drop, the
  entitlements and the sandbox model. No new dependency, and nothing is written to the user's file.

**Out of scope:** playback, zoom, scrubbing, selection, a time axis, a spectrogram, an FFT or any
spectral measure, loudness, peak/RMS or any level metric, per-property explanations, persistence or
caching of the waveform, exporting the waveform in any form, batch, and any judgement about what the
drawn shape means.

**Also out of scope, deliberately carried forward:** the drag sources never exercised — iCloud files,
aliases, symlinks, app bundles and Mail file promises — remain open against ADR-0014 and are **not**
mixed into this slice.
