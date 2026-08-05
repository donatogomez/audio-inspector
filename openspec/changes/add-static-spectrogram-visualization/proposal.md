## Why

A collector's question — *is this "lossless" file really lossless?* — is answered, in practice, by
looking at where a file's energy stops. A WAV that came from a 128 kbit/s MP3 has nothing above about
16.8 kHz, and that is visible at a glance in a spectrogram while being invisible in every technical
property the app reports today.

The report currently shows metadata plus an amplitude envelope. Neither can show a spectral cutoff:
the envelope collapses frequency entirely. This slice adds the one view that makes the cutoff visible,
and stops there.

It also forces an architectural change that was written down in advance. ADR-0015 recorded its own
reversal condition: *"the first level metric or the first FFT needs the same decoded stream. At that
point the chunked-decode port becomes a real seam, `AudioDecoding` is introduced, and the reduction
moves to Analysis."* This is that first FFT. `docs/architecture.md` has named `AudioDecoding` and
`SpectrogramGenerating` among the intended ports since the beginning; this slice builds the first of
them for real.

**What this slice deliberately does not do is say what a cutoff means.** Automatic detection of lossy
origin is a separate change, and it must work with observable reasons, alternative explanations and
confidence rather than a verdict. Showing the evidence and interpreting it are different jobs, and
conflating them is how an instrument becomes an oracle.

## What Changes

- A **shared chunked PCM decoding seam** (`AudioDecoding`) in the domain, implemented once in Media.
  Both the spectrogram and — conditionally, at the end — the waveform consume it, with independent
  operations and independent cancellation. No single shared pass is forced on them.
- **STFT and spectral reduction as pure code in `AudioInspectorAnalysis`**, which stops being empty
  because a real seam finally exists rather than because a module was waiting to be filled.
- A **bounded spectrogram model** in the domain: at most 1024 columns × 512 bands of absolute dBFS,
  independent of any view, carrying no framework type.
- A **static spectrogram** in the report surface: time horizontal, frequency vertical and linear to
  the file's full Nyquist, intensity by colour, with a numeric dB legend. No playback, no zoom, no
  scrubbing, no selection. Resizing redraws the model; it never decodes or transforms again.
- The spectrogram travels **beside** `InspectionReport`, exactly as the waveform does. The
  `schemaVersion` 1 export is untouched.

Every constant below was measured before this proposal was written, in
`docs/spikes/2026-08-06-static-spectrogram-validation.md` (67 checks, 0 failures): FFT 2048, hop 512,
Hann denormalised, magnitude scaled by `1 / windowSum`, reference 1.0, 20·log10, floor −120 dBFS,
reduction by **maximum** in both axes, channels transformed separately and combined by maximum **in
the frequency domain**, and the final incomplete frame **discarded rather than zero-padded**.

## Capabilities

### New Capabilities

- **spectrogram-visualization** — derive a bounded, view-independent spectral model from the file's
  samples and present it as a still drawing that interprets nothing.

### Modified Capabilities

- **waveform-visualization** — only to record that the amplitude envelope may be produced from the
  shared `AudioDecoding` seam instead of its own read, with the existing guarantees unchanged. The
  migration is **conditional**: it happens only if it preserves the contract and every existing test
  without coupling the two consumers, and is otherwise deferred to its own change.

`audio-file-inspection` is **not** modified. Its promoted spec already scopes the no-DSP rule to how
technical properties are obtained and states that reading samples for another purpose is outside that
scope.

## Impact

- `AudioInspectorDomain` — a decoding port, a spectrogram model and its own error space.
- `AudioInspectorAnalysis` — first real contents: the STFT and the reduction, pure and framework-free
  apart from Accelerate.
- `AudioInspectorMedia` — one PCM chunk adapter, the only place `AVAudioFile` appears.
- `AudioInspectorApp`, `FeatureImport` — a second parallel result beside the report, with its own
  cancellation.
- `FeatureAnalysis` — the drawing, its legend and its accessible description.
- **Unchanged**: the JSON exporter and the `schemaVersion` 1 contract, `InspectionReport`, the property
  reader, the entitlements, CI, and the package's dependencies — Accelerate is a system framework, and
  no third-party dependency is added.

## Non-Goals

Automatic detection of lossy origin or transcoding · any verdict about quality, authenticity or
provenance · playback, zoom, scrubbing, selection or a movable cursor · per-file normalisation ·
persistence or caching of the model · exporting the spectrogram · a spectrum analyser, loudness or any
level metric · batch processing.
