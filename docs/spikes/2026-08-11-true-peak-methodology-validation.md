# Spike report — true peak: reconstruction filter, oversampling factor, edges and cost

> **What this is.** Group 2 of change `add-true-peak-measurement`, run **before** any production code
> exists. It settles the six methodology decisions ADR-0006 deliberately left open, with measurements
> rather than reasoning.
>
> **What it is not.** It is not production code, not a benchmark suite, and not a verdict about any
> file. Every number below is a measurement of an algorithm against signals whose answer is known.

- **Date prepared**: 2026-08-11
- **Branch**: `design/add-true-peak-measurement`
- **Package**: `Spike/validate-true-peak/` — its own SwiftPM package, deliberately **outside** the
  production graph. The root `Package.swift` is untouched, so `swift build` at the repository root
  never sees it, and `Scripts/check-boundaries.sh` (which scans only `Sources/`) is unaffected.
- **Related**: **ADR-0006** (the methodology this spike executes; *referenced, never edited*),
  **ADR-0019** (`Proposed` — the two structural decisions ADR-0006 does not make), ADR-0003 (FFmpeg as
  a dev/test oracle, never shipped), ADR-0016 (independent operations over the shared PCM seam),
  `docs/analysis-methodology.md`, and the spectrogram spike of 2026-08-06 whose form this follows.

## Objective

Decide, with runnable evidence, what a true-peak measurement in this project actually is:

interpolation filter · oversampling factor per sample rate · edge handling · chunk independence ·
`Float` vs `Double` · the `truePeak >= samplePeak` invariant · unit · agreement tolerance against
FFmpeg · cost — **or find out the proposed shape does not survive contact with a measurement.**

## How to reproduce

```bash
cd Spike/validate-true-peak
swift build -c release -Xswiftc -warnings-as-errors
swift run -c release TruePeakSpike /tmp/true-peak-fixtures --cost
```

Debug timings come from the same binary built without optimisation:

```bash
swift run TruePeakSpike /tmp/true-peak-fixtures-debug --cost-quick
```

It writes nothing inside the repository. **Every fixture is synthesised from a formula in
`Fixtures.swift`** and written as a canonical RIFF/WAVE IEEE-float file by hand — no external audio is
used as evidence anywhere, and no framework's own file writing or resampling sits between the formula
and the oracle. Float samples are used throughout so a fixture carrying a sample beyond `±1` keeps it
(a 16-bit file would silently clamp fixture 06).

The oracle gate needs FFmpeg. When FFmpeg is absent that gate **skips loudly** and a skip is never
counted as evidence.

## Environment

| | |
| --- | --- |
| macOS SDK | 26.5 |
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`), Swift 6 language mode, `-warnings-as-errors` |
| Architecture | arm64 |
| FFmpeg (oracle only) | 8.1.2 |

> **SDK-dependence caveat**, inherited from the earlier spikes: every observation comes from **one**
> OS/SDK on one machine. The *semantic* conclusions carry forward; the timings do not.

## Fixtures

Twenty-one files, covering the seventeen characteristics the change asked for. Where the continuous
waveform's maximum is known **analytically** it is stated — that is stronger evidence than any oracle,
and it is what most of this report is measured against.

| # | Fixture | Covers | Analytic true peak |
| --- | --- | --- | --- |
| 01 | `01-silence` | silence | 0 (measured, not "not computable") |
| 02 | `02-tone-crest-on-sample` | peak exactly on a sample | 0.9 |
| 03 | `03-tone-crest-between-samples` | crest between samples | 0.9 (sample peak 0.6364) |
| 04 | `04-tone-near-nyquist` | 0.45·sr | 0.9 |
| 05 | `05-sample-under-true-over` | sample peak < 1, true peak > 1 | 1.05 (sample peak 0.7425) |
| 06 | `06-sample-beyond-full-scale` | a stored sample of 1.5 | ≥ 1.5 |
| 07 | `07-impulse` | impulse | 1.0 (its reconstruction is sinc) |
| 08 | `08-square-hard-edges` | square / hard edges | — (not band-limited) |
| 09 | `09-energy-first-frame` | energy at the very first frame | 1.0 |
| 10 | `10-energy-last-frame` | energy at the very last frame | 1.0 |
| 11 | (01–10, 17, 19–22) | mono | — |
| 12 | `12-stereo-different-channels` | stereo, channels genuinely different | 0.9 (L) / 0.3 (R) |
| 13–16 | `13-rate-44100` … `16-rate-192000` | 44.1 / 48 / 96 / 192 kHz | 0.9 |
| 17 | `17-complex-programme` | music-like: 12 partials + seeded noise | — |
| 18 | `23-192k-realistic-hf` | realistic HF at a high rate (15 kHz @ 192 kHz) | 0.9 |
| 19–20 | `19-faded-sr4`, `20-faded-near-nyquist` | the same tones with a raised-cosine fade | 0.9 |
| 21–22 | `21-periodic-sr4`, `22-periodic-near-nyquist` | exactly periodic, power-of-two length | 0.9 |

Fixtures 19–22 **were added during the spike**, not planned: the first run showed both this
implementation *and* the oracle reading above a tone's own amplitude, and separating why required
signals that are smooth at their boundaries (19–20) and signals a frequency-domain method can
interpolate exactly (21–22). That separation turned out to be the single most important result here.

## Result

Every open decision from `design.md` §4 is closed with a measurement. Two of them were closed
**against** the shape the design assumed, and both corrections are recorded in "Corrections" below.

---

## A — The invariant, proven at its root rather than patched

`truePeak >= samplePeak` is not enforced afterwards with `max(samplePeak, reconstructed)`. It holds
because **phase 0 of the interpolator is the exact identity**, so the stored samples are inside the set
the maximum is taken over.

The reason is one line of the design: `sinc(u)` is **zero at every non-zero integer**, which is a
definition rather than an approximation, so it is evaluated as such instead of via `sin(πu)/(πu)`,
which returns ~1e-16 at integer arguments. At phase 0 every tap argument is an integer.

```
filter: polyphase-fir-4x-12tap-kaiser8.6-cut1.00-norm
phase 0 taps: 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0
phase 0 is the exact identity (bit-for-bit): true
worst (truePeak - samplePeak) over every fixture and channel: 0.0
```

**The negative control, run and reported:** the same filter designed with a cutoff *below* the original
Nyquist has a phase 0 that is no longer the identity, and the invariant stops being structural.

```
phase 0 taps with cutoff 0.90: 0.0019, -0.0099, 0.0292, -0.0590, 0.0878, 0.8999, 0.0878, …
worst (truePeak - samplePeak) with cutoff 0.90: -0.16023433225176686   <- invariant broken
```

**Consequence for the contract**: the cutoff is fixed at exactly 1.0 (the original Nyquist), and it is
not a free parameter. Any future change to it breaks a structural guarantee, not just a number.

## B — The overshoot was the file's edge, not the filter

The first run looked alarming: on `03-tone-crest-between-samples` (a 0.9-amplitude tone) this
implementation read **0.9116** and the FFmpeg oracle read **0.963**, both above the tone's own
amplitude. Neither is wrong.

| fixture | taps/phase | zero-padded | interior-only | fft zero-pad 4× | analytic |
| --- | --- | --- | --- | --- | --- |
| 03 truncated, sr/4 | 12 | 0.909447 | 0.900002 | n/a | 0.900000 |
| 03 truncated, sr/4 | 24 | 0.911551 | 0.900000 | n/a | 0.900000 |
| 19 **faded**, sr/4 | 12 | 0.900002 | 0.900002 | n/a | 0.900000 |
| 19 **faded**, sr/4 | 24 | 0.900000 | 0.900000 | n/a | 0.900000 |
| 21 periodic, sr/4 | 24 | 0.911551 | 0.900000 | **0.900000** | 0.900000 |
| 04 truncated, 0.45·sr | 24 | 1.000468 | 0.888920 | n/a | 0.900000 |
| 20 **faded**, 0.45·sr | 24 | 0.888920 | 0.888920 | n/a | 0.900000 |
| 22 periodic, 0.45·sr | 24 | 1.000494 | 0.900000 | **0.900000** | 0.900000 |

A tone that starts abruptly at a non-zero value is **discontinuous against the silence outside the
file**, and the band-limited reconstruction of a discontinuity genuinely overshoots. Fade the ends and
the overshoot disappears entirely (0.900000 against an analytic 0.9). The frequency-domain candidate,
which interpolates the *periodic* extension, never sees the discontinuity at all and returns the exact
analytic answer — which is what makes it a useful second ground truth and a poor production candidate.

**This is not an artefact to remove.** A decoder handed that file in isolation produces exactly that
overshoot. Reporting it is correct; the design must simply not mistake it for filter error.

## C — Chunk independence: bit-exact, at every size

| fixture | whole buffer | 1 | 3 | 127 | 512 | 2048 | 4096 | 65536 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 03 tone | 0.911550829 | exact | exact | exact | exact | exact | exact | exact |
| 09 first frame | 1.000000000 | exact | exact | exact | exact | exact | exact | exact |
| 10 last frame | 1.000000000 | exact | exact | exact | exact | exact | exact | exact |
| 17 complex | 0.983623012 | exact | exact | exact | exact | exact | exact | exact |

Worst difference across every size and fixture: **0.0** — bit for bit, not "within a tolerance".

**Why it is exact here when `SignalLevelMetrics` had to state a caveat.** RMS and DC offset accumulate
a *sum*, and different chunk boundaries hand vDSP different pairings that round differently. A maximum
accumulates nothing: each output point is computed from the same taps and the same samples whatever the
chunking, and `max` is exact. The only requirement is that the filter's history crosses the boundary,
which the streaming reconstructor does by holding the first `tapsPerPhase/2 - 1` samples before
emitting anything.

**Consequence for the contract**: chunk independence for true peak is testable as **equality**, not as
a tolerance. The production test may assert bit-for-bit.

## D — `Float` versus `Double`

Same algorithm, convolution carried out both ways, plus the vDSP path production would use:

| | worst over all 21 fixtures |
| --- | --- |
| `\|float − double\|`, linear | **1.9 × 10⁻⁷** |
| `\|float − double\|`, dB | **2 × 10⁻⁶ dB** |
| `\|vDSP − double\|`, linear | **7.1 × 10⁻⁸** |

Both are four orders of magnitude below the oracle's own printing resolution and six below any
tolerance worth stating.

**Decision: `Float`.** It matches the sample type the port already delivers, it is what vDSP's fast
path wants, and `Double` buys a difference no test could justify asserting. This is the opposite of
`SignalLevelMetricsAccumulator`'s choice **for a stated reason**: that type accumulates ~10⁸ additions
into a running sum, where `Float`'s ~7 digits genuinely erode; a maximum accumulates nothing.

> **Caveat on the timing of `scalar-float` below**: the spike's float path converts the whole extended
> buffer to `Float` first, an allocation the double path does not pay. Its timings are therefore *not*
> a fair measure of float arithmetic, and are reported only to show that neither scalar path is the one
> to ship.

## E — The oracle, and exactly what it can answer

**Command, verbatim:**

```bash
ffmpeg -hide_banner -nostats -i FIXTURE.wav \
  -af ebur128=peak=true+sample:metadata=1,ametadata=mode=print:file=- -f null -
```

Three limitations were measured, not assumed, and all three bound what the cross-check can prove:

1. **Resolution.** The summary block prints true peak to **one decimal place in dB**. The metadata
   stream prints `lavfi.r128.true_peak` and `lavfi.r128.true_peaks_ch<N>` as **linear** values to
   **three decimals**. The metadata form is the one used here — it is per channel and far finer — but
   it still puts a hard floor of **±0.0005 linear** (≈ ±0.004 dB near full scale) under any agreement
   claim. That floor is budgeted separately from algorithmic error below.
2. **192 kHz is not oversampled at all.** On `16-rate-192000` the oracle's true peak is **0.636**,
   exactly equal to its own reported sample peak, while the fixture's analytic true peak is 0.9. The
   oracle therefore **cannot validate 192 kHz**, and that fixture is excluded from the tolerance
   derivation rather than allowed to inflate it.
3. **Truncated fixtures measure edge behaviour, not agreement.** Both meters overshoot at a
   discontinuity, by amounts that depend on their own filters (§B). The tolerance is therefore derived
   from the fixtures that are smooth at their boundaries.

FFmpeg stays a **dev/test dependency, never shipped** (ADR-0003 §4). The subprocess is invoked with a
separated argument vector, never `sh -c` — the project's own rule, obeyed in the spike too.

## F — Edge handling: four policies, one survivor

Measured on every fixture with the 4× / 24-tap filter. Where an analytic answer exists, closeness to it
is the criterion; the disqualifying failures are **fabricating** a peak the file cannot produce and
**missing** one it literally contains.

| fixture | analytic | zero | mirror | constant | interior-only |
| --- | --- | --- | --- | --- | --- |
| 02 crest on sample | 0.900000 | **0.900000** | 0.943203 | 0.900000 | 0.900000 |
| 03 crest between samples | 0.900000 | **0.911551** | 0.953586 | 0.934042 | 0.900000 |
| 04 near Nyquist | 0.900000 | 1.000468 | 0.888920 | **1.236883** | 0.888920 |
| 05 sample under / true over | 1.050000 | **1.063476** | 1.112517 | 1.089715 | 1.050000 |
| 09 energy at first frame | 1.000000 | **1.000000** | 1.000000 | 1.000000 | **0.000014** |
| 10 energy at last frame | 1.000000 | **1.000000** | 1.000000 | **1.130299** | **0.000014** |
| 19 faded sr/4 | 0.900000 | **0.900000** | 0.900000 | 0.900000 | 0.900000 |
| 23 realistic HF @192k | 0.900000 | **0.906187** | 0.924933 | 0.912901 | 0.900000 |

- **`constant` fabricates.** Holding the last sample turns the end of the file into a step and reads
  **1.1303** where the file's own maximum is 1.0, and **1.2369** on fixture 04. Disqualified outright.
- **`mirror` fabricates too**, and on ordinary tones rather than on adversarial ones: **0.9432** on a
  fixture whose crest sits exactly on a sample and whose true peak is provably 0.9. Mirroring asserts
  the signal continues in a way the file never states.
- **`interior-only` misses.** It reads **0.000014** on files whose energy is a full-scale sample at the
  very first or last frame — it never evaluates those positions, so it reports below the sample peak
  and **breaks the invariant of §A**. Disqualified outright.
- **`zero` neither fabricates nor misses.** It is closest to the analytic answer on every fixture where
  one exists, returns exactly 1.0 on both edge fixtures, and its only excursions above the analytic
  value are the honest discontinuity overshoot of §B.

**Decision: zero-extension**, and the justification is physical rather than aesthetic: a file is
surrounded by silence, and silence is what a decoder handing that file to anything else also produces.
The other three policies each assert something about the world outside the file that the file does not
say.

## G — The filter, chosen from a design sweep

Two properties matter and they pull against each other: **passband flatness** (droop under-reads the
peak) and **image rejection** (leakage over-reads it). Both were measured for 24 designs at 4×; the
worst image leakage across *every* design was **+0.02 dB**, so image rejection turned out not to be the
binding constraint and the choice is dominated by flatness.

| taps/phase | β | flat ±0.1 dB up to | gain @0.8·N | gain @0.9·N | gain @0.95·N | worst image |
| --- | --- | --- | --- | --- | --- | --- |
| 12 | 6.0 | 0.71·N | −1.02 dB | −5.13 dB | −10.63 dB | +0.02 dB |
| 24 | 6.0 | 0.85·N | +0.01 dB | −1.02 dB | −5.13 dB | +0.02 dB |
| 32 | 6.0 | 0.89·N | +0.00 dB | −0.20 dB | −3.16 dB | +0.01 dB |
| **48** | **6.0** | **0.93·N** | **−0.00 dB** | **+0.00 dB** | **−1.02 dB** | **+0.01 dB** |
| 64 | 6.0 | 0.94·N | −0.00 dB | +0.00 dB | −0.20 dB | +0.01 dB |
| 96 | 6.0 | 0.96·N | +0.00 dB | −0.00 dB | +0.00 dB | +0.01 dB |
| 48 | 12.0 | 0.89·N | +0.00 dB | −0.20 dB | −2.80 dB | +0.00 dB |
| 48 | 16.0 | 0.87·N | −0.00 dB | −0.48 dB | −3.69 dB | +0.00 dB |

Confirmed end to end rather than only in the frequency response — the same faded tones, measured
through the whole reconstruction:

| f/Nyquist | 12t/4× | 24t/4× | 32t/4× | **48t/4×** | 64t/4× | 96t/4× |
| --- | --- | --- | --- | --- | --- | --- |
| 0.50 | −0.0021 | +0.0002 | −0.0003 | **−0.0005** | −0.0004 | −0.0003 |
| 0.70 | −0.0505 | +0.0096 | +0.0007 | **+0.0052** | +0.0020 | −0.0004 |
| 0.90 | −0.1076 | −0.1076 | −0.1076 | **+0.0042** | +0.0023 | −0.0010 |

**Decision: 48 taps per phase, Kaiser β = 6.0, cutoff = 1.0, each phase normalised to unit sum.**

The criterion is the product's own subject, not a convention: this app exists to show *where a file's
high-frequency energy stops*, and a lossy cutoff at 16–20 kHz sits at **0.73–0.91 of Nyquist** at
44.1 kHz. Under-reading precisely in that band would be the worst possible place for this instrument to
be inaccurate. 48 taps is the shortest design measured flat within ±0.1 dB across all of it; 32 taps
misses it (0.89·N) and 64/96 buy nothing this product can use.

> **Limitation, stated rather than glossed over.** ITU-R BS.1770 Annex 2 tabulates its own polyphase
> FIR. **Its coefficients are not reproduced here: this spike had no access to the standard's text**,
> and writing down remembered numbers would be fabricated evidence. What is used instead is a filter of
> the same family, **designed** from the parameters above — every one of which is recorded with the
> result, so the value is interpretable — and validated against two independent references: signals
> whose true peak is known analytically, and FFmpeg's own R128 meter. If the annex table later becomes
> available, comparing against it is a bounded, well-defined follow-up, not a redesign.

## H — The oversampling factor

ADR-0006 fixes a floor of ≥4× and no more. What decides the rest is the **grid**: a factor `L` evaluates
the reconstruction every `1/L` of a sample, so a crest can fall between two evaluated points. A single
tone phase measures luck; this sweeps 64 phases per frequency and reports the **worst** case.

| f/Nyquist | 2× | 4× | 8× | 16× |
| --- | --- | --- | --- | --- |
| 0.10 | −0.0256 | −0.0058 | −0.0012 | +0.0000 |
| 0.25 | −0.1685 | −0.0420 | −0.0001 | −0.0001 |
| **0.50** | **−0.6877** | **−0.1689** | **−0.0424** | −0.0005 |
| 0.70 | −0.0216 | −0.0034 | −0.0001 | +0.0000 |
| 0.90 | −0.0226 | −0.0044 | −0.0008 | +0.0000 |

The worst case matches `1 − cos(π·f/(L·sr))` exactly, which is what makes it a property of the geometry
rather than of this implementation.

**Decision: 8×, flat at every supported sample rate.**

- **Why not 4×** — it is ADR-0006's floor and it is legal, but its worst-case under-read is **−0.17 dB**.
  R128 delivery limits are quoted to 0.1 dB (`−1.0 dBTP`), so a systematic 0.17 dB under-read can flip
  the judgement a reader is making. 8× brings that to **−0.04 dB**, below the oracle's own resolution.
  Measured cost of the difference: **+0.29 s in Release and +0.33 s in Debug** on a ten-minute stereo
  file. That is a cheap way to stop the metric being wrong in the direction that matters.
- **Why not rate-dependent** (8×/8×/4×/2× for a constant reconstructed rate) — it equalises accuracy for
  a given *absolute* frequency and is cheaper at 96/192 kHz, but 2× at 192 kHz **violates ADR-0006's
  own "≥4×" literally**. One flat constant satisfies the ADR at every rate, needs no second constant to
  justify and record, and gives a uniform worst case. Cost at 192 kHz scales with the sample count
  (≈4.35× the 44.1 kHz figure), which is reported rather than hidden.
- **Why not 16×** — its worst case is −0.0005 dB, an improvement no reader and no threshold can use, at
  double the cost of 8×.

## I — Agreement with the oracle, and the tolerance derived from it

Measured with the chosen configuration (`polyphase-fir-8x-48tap-kaiser6.0-cut1.00-norm`, zero edges):

| fixture | analytic | ours | oracle | Δ vs oracle | Δ vs analytic |
| --- | --- | --- | --- | --- | --- |
| 01 silence | 0.000000 | 0.000000 | 0.000 | 0.0000 | — |
| 06 stored 1.5 | — | 1.500000 | 1.500 | 0.0000 | — |
| **19 faded sr/4** | 0.900000 | 0.899949 | 0.900 | **0.0005 dB** | −0.0005 dB |
| **20 faded 0.45·sr** | 0.900000 | 0.900439 | 0.898 | **0.0236 dB** | +0.0042 dB |
| **17 complex programme** | — | 0.983270 | 0.983 | **0.0024 dB** | — |
| 02 truncated, crest on sample | 0.900000 | 0.917829 | 0.900 | 0.1704 dB | +0.1704 dB |
| 03 truncated, crest between | 0.900000 | 0.909681 | 0.963 | 0.4947 dB | +0.0929 dB |
| 04 truncated, near Nyquist | 0.900000 | 1.014433 | 0.899 | 1.0493 dB | +1.0396 dB |
| 16 rate 192 kHz | 0.900000 | 0.909681 | 0.636 | 3.1086 dB | +0.0929 dB |

The fixtures fall into three classes, and **collapsing them into one number would produce a tolerance
that describes nothing**:

- **Class A — smooth boundaries, ≤ 96 kHz** (01, 06, 17, 19, 20): worst **0.0236 dB**. This is the class
  where both meters are measuring the same thing.
- **Class B — truncated boundaries** (02–05, 08, 12–15, 23): up to **1.05 dB**. Not algorithm error:
  §B established that a discontinuity produces a real overshoot, and the two meters ring differently
  because their filters differ. A longer filter rings longer, which is why the 48-tap design overshoots
  *more* than the 24-tap one here while being *more* accurate everywhere else. These fixtures are
  checked against the **analytic** truth instead, where the overshoot is expected and bounded.
- **Class C — 192 kHz** (16): **not comparable.** The oracle does not oversample there at all.

**Tolerance: 0.05 dB, for class A at sample rates up to 96 kHz.**

Derived, not rounded up for comfort: worst measured **0.0236 dB**, plus the oracle's own printing
quantisation of ±0.0005 linear (**±0.0048 dB** at these levels) gives a credible worst of **0.029 dB**.
0.05 dB is the nearest round figure above it — a margin of ≈1.7× for fixture-to-fixture variation not
yet sampled, and no more. Against the **analytic** truth, which carries no quantisation at all, the same
class agrees to **0.0042 dB**, and that is the tighter check the production tests should lead with.

## J — Cost

DSP only, per the matrix the change asked for. Decode is **not** included: this package imports no
AVFoundation, and the project already has a decode figure measured against a real ten-minute stereo file
(**0.035 s**, recorded in `SignalLevelMetricsAccumulator`'s own documentation).

**Release (`-O`), seconds:**

| duration | channels | 32t/4× | 48t/4× | **48t/8×** |
| --- | --- | --- | --- | --- |
| 1 min | 1 | 0.012 | 0.015 | **0.028** |
| 1 min | 2 | 0.022 | 0.030 | **0.056** |
| 10 min | 1 | 0.122 | 0.153 | **0.272** |
| 10 min | 2 | 0.220 | 0.403 | **0.693** |

**Debug (`-Onone`), seconds:**

| duration | channels | implementation | 32t/4× | 48t/4× | 48t/8× |
| --- | --- | --- | --- | --- | --- |
| 1 min | 1 | scalar | 51.9 | 76.5 | 151.8 |
| 1 min | 1 | **vDSP** | **0.230** | **0.232** | **0.243** |
| 1 min | 2 | scalar | 103.9 | 152.5 | 323.6 |
| 1 min | 2 | **vDSP** | **0.453** | **0.455** | **0.516** |
| 10 min | 2 | **vDSP** | **4.96** | **4.91** | **5.24** |

**vDSP is not an optimisation here, it is the only viable implementation.** A scalar pass over *one
minute* of mono audio costs **76 seconds** in the build a developer actually runs — three orders of
magnitude worse. The scalar `Float` and `Double` timings are within 1 % of each other, so the choice of
§D costs nothing either way.

Note that in Debug the three designs cost almost the same through vDSP (4.91–5.24 s): the convolution is
precompiled, so what remains is the spike's own buffer handling — an allocation and a `Double`→`Float`
conversion production would not pay, since the port already delivers `Float`.

**The fourth read is accepted.** Its own cost is one more decode (**0.035 s**), and the DSP it enables
costs **0.69 s in Release and ≈5 s in Debug** on a ten-minute stereo file — beside the spectrogram's own
≈36 s in an unoptimised build (its spike, §F), this is not the operation that decides how long an
inspection feels. `design.md` §8's stop rule is therefore **not** triggered, and no deduplication change
is opened. The numbers are recorded so that decision can be revisited on evidence rather than reopened
on taste.

## Decisions, closed

| # | Decision | Value | Where it came from |
| --- | --- | --- | --- |
| 1 | Oversampling factor | **8×, flat at every rate** | §H — worst-case −0.042 dB vs −0.169 dB at 4× |
| 2 | Filter | **Polyphase FIR, 48 taps/phase** (384 coefficients at 8×) | §G |
| 3 | Filter parameters | **Kaiser β = 6.0, cutoff = 1.0 (exact input Nyquist), each phase normalised to unit sum**; coefficients generated by formula, not quoted | §G |
| 4 | Edge handling | **Zero-extension** | §F |
| 5 | Chunk continuity | Carry `tapsPerPhase/2 − 1` samples of history; result **bit-exact** at any chunk size | §C |
| 6 | Arithmetic | **`Float`** | §D |
| 7 | Unit | **Linear** in the domain and on the wire; **dBTP** only at presentation | §K |
| 8 | Tolerance vs FFmpeg | **0.05 dB**, class A (smooth boundaries, ≤96 kHz); analytic check at **0.0042 dB** | §I |
| 9 | Zero frames | **Not computable**, distinct from a measured zero | §A, fixture 01 vs an empty channel |
| 10 | Samples beyond ±1 | **Kept, never clamped** — fixture 06 reads exactly 1.500000 | §B |
| 11 | Per channel / overall | Per channel canonical; overall = **maximum** of the per-channel values | §A (a maximum of maxima is exact) |
| 12 | Performance strategy | **`vDSP_conv` per phase + `vDSP_maxmgv`**; scalar is unusable in Debug | §J |
| 13 | Oracle in CI | **Gated on FFmpeg's presence**; the analytic fixtures are the CI-enforced check | §K |

## K — Two decisions that needed a reason, not just a value

**The unit is dBTP.** ADR-0006 writes "true peak > 0 **dBFS**"; `docs/analysis-methodology.md` writes
"true peak (dBFS)"; FFmpeg's own option is documented as "true peak (dBFS)". EBU R128 / Tech 3341 write
**dBTP**. The measurements above are the argument for the divergence rather than convention: fixture 03
has a sample peak of 0.6364 and a true peak of 0.9, which on screen is `−3.92 dBFS` beside `−0.92 dBTP`.
Two numbers that differ by 3 dB while sharing a unit invite the reader to conclude one of them is
wrong. The stored and exported value stays **linear**; dBTP exists only at the presentation edge.
Recorded in **ADR-0019**, which narrows ADR-0006's wording without editing it.

**The oracle is gated in CI, and the analytic fixtures carry the standard-agreement claim.** FFmpeg is
present on the development machine and **absent from the CI runner** (`.github/workflows/ci.yml`,
`macos-26`, no install step). Two options existed: gate the oracle tests on the tool's presence — the
pattern `MP3WaveformEvidenceTests` already uses — or install a GPL FFmpeg build into the pipeline.

**Gated, and here is why that is not a weakening.** §E showed the oracle cannot validate 192 kHz at all
and prints to a resolution that puts a ±0.0048 dB floor under any claim, while the analytic fixtures
(02, 03, 05, 07, 09, 10, 19–22) have **exact known answers, need no external tool, and agree to
0.0042 dB**. So the CI-enforced check is the stronger of the two, and the oracle cross-check is a
locally-run confirmation against an independent implementation. "Cross-checked in tests" therefore means
something precise, and never quietly means "on one machine only". FFmpeg stays a dev/test dependency and
is never shipped (ADR-0003 §4).

## What this evidence supports, and what it does not

**It supports** measuring a true peak with a stated, reproducible methodology, reporting it per channel
and overall, and stating how far it can be trusted: ±0.05 dB against an independent R128 meter for
signals that are smooth at their boundaries, and bit-exact regardless of how the file is chunked.

**It does not support** any statement about the *file*. A true peak above 0 dBTP means the
reconstruction exceeds full scale; whether any converter, encoder or player in a given chain actually
distorts because of it is not measured here and is not knowable from the file alone. Nothing in this
spike authorises the word "clipping" (ADR-0019 §4).

**It also does not support** a claim of conformance to BS.1770's own filter. The filter here is of the
same family, designed to recorded parameters, and validated against analytic truth and an independent
implementation — which is a different and weaker claim than "the standard's coefficients", and is
written that way everywhere.

## Corrections to the design this spike was written to test

1. **`design.md` §4.4 asked whether the convolution needs `Double`. It does not** — the worst difference
   over 21 fixtures is 1.9 × 10⁻⁷ linear. The design's own precedent (`SignalLevelMetricsAccumulator`
   accumulates in `Double`) does **not** transfer, and the reason is now recorded: that type accumulates
   ~10⁸ additions, a maximum accumulates nothing.
2. **`design.md` §4.1 framed the factor as "flat 4× or rate-dependent". Measurement chose neither**: a
   flat **8×**, because 4×'s worst-case −0.17 dB is large next to the 0.1 dB precision R128 limits are
   quoted at, and because rate-dependence would break ADR-0006's own "≥4×" at 192 kHz.
3. **`design.md` §4.3's edge candidates were incomplete.** It offered zero / reflection / interior-only.
   Reflection turned out to **fabricate** on ordinary tones (0.9432 where the truth is 0.9), and
   interior-only to **break the §A invariant** outright (0.000014 on a file whose peak is 1.0). Neither
   was a close call.
4. **`design.md` §4.2 offered the BS.1770 annex filter "if its coefficients can be reproduced from the
   standard's text". They could not be** — the text was not available — so the conditional resolved to
   the designed windowed-sinc branch, and the limitation is recorded rather than papered over.
5. **The frequency-domain candidate is withdrawn as a production option** and kept as a *reference*: it
   interpolates the periodic extension exactly, which makes it an excellent second ground truth (§B) and
   a poor fit for a streaming, chunked pipeline.

Everything else in the design survived: the sibling domain type, the fourth independent operation, the
linear-internal/dBTP-at-the-edge split, and the export shape.

## Falsification criteria, written before the measurements

If any of these had been met, the design would **not** have been adopted:

1. `truePeak >= samplePeak` requiring a clamp rather than holding structurally — **not met** (§A, worst
   shortfall exactly 0.0).
2. The result depending on chunk size — **not met** (bit-exact at every size from one frame up).
3. No design reaching ±0.1 dB flatness across the 16–20 kHz band this product exists to examine —
   **not met** (48 taps/phase reaches 0.93·Nyquist).
4. Every edge policy either fabricating or missing a peak — **not met** (zero-extension does neither).
5. A ten-minute stereo file costing more than a few seconds in an unoptimised build — **not met**
   (≈5 s through vDSP; the scalar path, at 76 s per minute of audio, was rejected on exactly this).
6. Disagreement with the oracle that could not be attributed to a measured cause — **not met**: every
   disagreement above 0.03 dB is accounted for by edge ringing, by the oracle's own 3-decimal printing,
   or by its not oversampling at 192 kHz.

## Deletion criterion

`Spike/validate-true-peak/` is deleted once **ADR-0019 is Accepted** and the slice's own tests cover
these observations — the same criterion the PCM decoding and spectrogram spikes carry. Until then it
stays reproducible, and this report is the durable record of what it measured.
