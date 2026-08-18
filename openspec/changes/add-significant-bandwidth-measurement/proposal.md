# Measure where a file's signal energy actually stops

## Why

A collector's question is rarely *"what does the header say?"* — it is *"does this 96 kHz file contain
anything a 44.1 kHz file would not?"* Today Audio Inspector can draw a spectrogram that makes a band
limit visible, and can say nothing about it in words, in the export, or in a comparison between two
files. The picture is evidence a person has to read; this makes the same evidence a **measured fact**.

`docs/roadmap.md` names it in Phase 1b — *"full waveform, average spectrum (FFT), basic spectrogram,
**and the significant max frequency**"* — and it is the last item of that phase still unbuilt.

## What this is, and what it is emphatically not

It reports **one fact**: the highest frequency region that carries signal energy persistently enough to
be called content rather than an artefact. Nothing more.

It does **not** detect upsampling, transcoding, lossy provenance, "fake lossless", or a source codec,
and it emits **no finding**. `CLAUDE.md` already forbids the shortcut in as many words — *"never assert
transcoding from a single frequency cutoff"* — and `docs/analysis-methodology.md` requires any such
inference to combine independent indicators, each with its own measurement. This change builds the
**first** such indicator and stops there. The inference layer is a later change with its own record.

## Why it cannot be derived from the spectrogram

This was measured rather than assumed, and the answer decided the architecture. A spike drove real
files through the production pipeline and read the resulting `Spectrogram`:

- **The spectrogram reduces over time by maximum** (`vDSP_vmax`). A file that is digital silence except
  for **one impulse** reports its highest energy at **23 977 Hz** — while the same reading taken as a
  percentile across columns reports **0 Hz**. A max-reduced picture cannot tell an isolated click from
  persistent content, and persistence is exactly what the methodology requires.
- **Its band grid is a UI cap, and the answer moves with the sample rate.** 512 bands span 0–Nyquist, so
  band width scales with the rate. The same 16 kHz-limited signal reads 16 042 Hz at 44.1 kHz and
  **16 594 Hz at 192 kHz** — a 594 Hz error on a physical fact that does not depend on the rate.
- **The caps are declared free to change**: *"Caps, not promised resolutions: neither is exported,
  persisted or shown, so both can change without breaking anything."* A domain measurement must not
  depend on a constant whose own documentation says it may be changed at will.

## What is proposed

A **sixth consumer** of the existing shared PCM read, computing its own STFT at full resolution, with a
methodology decided and recorded before any accumulator exists — the order `add-loudness-measurement`
followed and the reason it succeeded.

Still **one** read of the file. No new dependency. No new decoder. `schemaVersion` stays 1.

## Out of scope

Momentary / short-term loudness, loudness range, spectral centroid, roll-off percentiles beyond what
this measurement needs, effective bit depth, findings of any kind, platform targets, and any statement
about a file's origin.
