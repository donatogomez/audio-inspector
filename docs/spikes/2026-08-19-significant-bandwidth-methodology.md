# Spike — significant bandwidth methodology (group 1, **incomplete**)

Working notes for `add-significant-bandwidth-measurement` group 1. **It settles nothing.** One result
is recorded because it is real and reusable; everything else group 1 asks for is still open, and this
document exists so the next session does not repeat the part that was done or assume the part that was
not.

## Method

A temporary spike with **its own STFT** (Hann, `1/windowSum` scaling, vDSP) and signals synthesised in
memory rather than written as files. The production fixture writer cannot express a graded roll-off, a
high band at a stated level relative to the body, or content present for a stated fraction of the file
— `AudioFixtureSignal`'s cases are whole-file shapes — so synthesis was done in the spike. Nothing here
touched production.

Signal vocabulary built: tone combs on a 500 Hz grid, a high band above a knee at a stated dB relative
to the body and a stated presence fraction spread over periodic bursts, graded roll-offs in dB/octave,
deterministic LCG white noise, and impulse clicks.

Candidate algorithm space: a **per-bin presence fraction** — the fraction of analysis windows in which
a bin exceeds a threshold — with the reported value being the highest bin whose presence fraction meets
a criterion. Threshold candidates: relative to the global spectral peak, relative to each window's own
peak, relative to the global spectral RMS, relative to a robust 95th-percentile reference, and an
absolute dBFS threshold kept only as a negative control.

## A1. Gain invariance — measured

Body of tones to 16 kHz, a high band to 20 kHz at −40 dB relative to the body, present throughout.
48 kHz, FFT 4096, hop 1024, threshold −60 dB relative to each candidate's reference, presence ≥ 50 %.
The same signal was measured at four gains.

| threshold reference | −1 dBFS | −10 dB | −20 dB | −40 dB | gain-invariant |
| --- | --- | --- | --- | --- | --- |
| global spectral peak | 20 016 | 20 016 | 20 016 | 20 016 | **yes** |
| per-window peak | 20 016 | 20 016 | 20 016 | 20 016 | **yes** |
| global spectral RMS | 20 027 | 20 027 | 20 027 | 20 027 | **yes** |
| robust 95th percentile | 20 027 | 20 027 | 20 027 | 20 027 | **yes** |
| **absolute dBFS** (control) | 20 004 | 20 004 | **15 621** | **15 609** | **no** |

Two things follow, and only two:

- **The absolute-threshold negative control works.** A fixed dBFS threshold measures level rather than
  spectral structure: attenuating the same file by 20 dB moved its answer by 4.4 kHz.
- **Gain invariance does not choose between the four relative candidates.** All four pass, which is
  expected — they are all relative — so the choice must be made by the discrimination matrix below,
  not by this.

## A2. The discrimination matrix — **not obtained**

The decisive experiment — six fixtures whose correct answer is known (body-only; weak-but-persistent
high content; weak-and-rare; loud-and-rare; clicks; very low noise), swept over four threshold
references × five threshold values × five presence fractions, accepting only combinations that get
**all six** right — did not produce a result within the session.

The obstacle was measurement cost, not methodology: the sweep is 100 combinations × 6 spectrograms ×
(frames × bins) inner tests, which is roughly 3 × 10⁸ iterations, and a Debug build made it
impractical. A first attempt was additionally quadratic in frame count because the global reference
levels were recomputed per frame; that was fixed. A Release run was started and did not finish in time.

**No threshold value and no persistence fraction may be inferred from A1.** They remain undecided.

## What group 1 still requires

Unchanged and unstarted, except where noted:

- **1.1 graded fixtures** — the synthesis exists in the spike but has produced no accepted result.
- **1.2 the threshold** — narrowed only to "relative, not absolute". Which relative reference, and at
  what value, is open.
- **1.3 persistence** — open. The per-bin presence-fraction formulation is a candidate, not a decision.
- **1.4 the quiet-but-persistent floor** — open.
- **1.5 the resolution claim** — open. Bin width is `rate / fftSize`; the Hann main lobe spreads a tone
  across several bins, so ±half-bin would be dishonest, but the honest figure has not been measured.
- **1.6 constants with sources** — nothing to record yet.

Also unmeasured, and each of them a condition of the change's own stopping rule: FFT size against
analytic cut-offs, multi-rate agreement, lossy rewrap survival, and cost as a sixth consumer.

## Practical note for whoever continues

Run the sweep in **Release**. The spike's own STFT and signal synthesis are cheap; the sweep is not, and
a Debug build turns a minute into an hour. Hoist any global reference level out of the per-frame loop.
