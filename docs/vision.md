# Audio Inspector — Product Vision

## One sentence

A native macOS forensic instrument that examines the **signal** of an audio file — not its
metadata — and explains, in language a non-expert can follow, what can and cannot be known about
its source, master, rip, and integrity.

## Who it is for

Music collectors, DJs, audiophiles, and people digitizing vinyl, tape, CD, or other sources who
need to answer questions like:

- Is this "24/96 FLAC" actually a padded, upsampled 16/44.1 file?
- Was this lossless file re-encoded from an MP3?
- Which of my three copies of this album is the best one to keep?
- Is my vinyl rip clean, or does it have hum, clicks, and excessive noise reduction?
- Is the master brickwalled and clipped, or does it still have dynamics?

## Product principles

1. **Evidence over verdicts.** Every conclusion is backed by measurable facts and carries a
   confidence level. We separate *evidence* (measured), *inference* (reasoned), and *conclusion*
   (judgment). See [analysis-methodology.md](analysis-methodology.md).
2. **No arbitrary scores.** No "quality: 83/100." We describe what we found and why it matters.
3. **Alternative explanations are first-class.** A spectral cutoff can be transcoding *or* the
   master *or* deliberate filtering. We say so.
4. **Format ≠ quality.** We never equate a container/codec (FLAC, WAV) with quality, and never
   recommend a file purely because it has a higher sample rate, bitrate, or bit depth.
5. **Two audiences, one analysis.** Every result has a **plain-language summary** and a
   **technical view** (metrics, methodology, thresholds, raw data, engine version).
6. **Local and non-destructive.** All processing is on-device; originals are never altered.
7. **Native macOS.** A real macOS utility (NavigationSplitView, Table, inspector, toolbar,
   menus, Quick Look, keyboard, VoiceOver) — not a scaled-up iPhone UI.
8. **Honest about uncertainty.** When the signal cannot support a claim, the app says
   "inconclusive" rather than guessing.

## What "good output" looks like

> This file is stored as 24-bit / 96 kHz FLAC, but the signal appears to originate from a 16-bit
> / 44.1 kHz source. There is no useful content above ~21 kHz, and the lower eight bits show a
> pattern consistent with padding. This file gains no real quality over a 16/44.1 lossless copy.

versus the failure mode we reject:

> Fake 24-bit. ❌

## Non-goals (product level)

- Not a tag editor, transcoder, or audio restoration tool.
- Not a scoring/ranking engine that reduces a file to a single number.
- Not a cloud service. No accounts, no sync, no telemetry.
- Not a replacement for critical listening — it informs it.
- Not a DRM/authenticity certifier. It reports evidence, not provenance guarantees.

## Success criteria (early)

- A user can drag in a file and, within seconds, see accurate container/codec/technical facts and
  a small set of **cautious, well-explained** observations.
- The app never overclaims: no observation is presented as certain unless the evidence is
  overwhelming and reproducible.
- The methodology and thresholds behind every observation are documented and versioned, so results
  are reproducible and auditable.
