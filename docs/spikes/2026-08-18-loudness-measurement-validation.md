# Spike — loudness measurement, before designing it

**Date**: 2026-08-18 · **Status**: complete, informing change `add-loudness-measurement` ·
**Machine**: one Apple Silicon Mac, one SDK. Timings do not carry forward; the semantic findings do.

Everything below was measured. Where something could not be established in this session it is marked
**UNRESOLVED**, not guessed — which matters more here than anywhere else so far, because the normative
constants of BS.1770 are exactly the kind of thing that is easy to half-remember and wrong to invent.

## 0. The one thing this spike could not do

**The normative text of ITU-R BS.1770 and EBU R128 was not read.** Neither document is in this repo and
neither was consulted in this session. Therefore this spike records **no filter coefficients, no gate
thresholds and no window lengths as normative facts.** Everything numeric below is either measured from
a reference implementation or derived from those measurements.

That is a real gap and it is the first implementation task, not a detail: an implementation whose
coefficients came from memory would be unverifiable and probably wrong. What this spike provides
instead is a **verification target** — the measured behaviour any correct implementation must
reproduce — and the oracle to check against.

## 1. The oracle

`ffmpeg` **8.1.2** (Homebrew, `/opt/homebrew/bin/ffmpeg`), filter `ebur128`, which ADR-0006 already
names as the reference. Exact command:

```
ffmpeg -hide_banner -nostats -i FILE -filter_complex ebur128 -f null -
```

**Its summary is emitted at INFO level**, so `-loglevel error` silently discards it — an hour lost to
that, recorded so nobody repeats it. It reports Integrated, its gating threshold, LRA with its own
threshold, and LRA low/high; adding `=peak=true` also reports true peak.

Not a runtime dependency: it is a test-time oracle, exactly as ADR-0006 and ADR-0003 intend.

## 2. Fixtures

Written directly as float32 WAV by a throwaway Python generator, so amplitude is exact rather than
whatever a filter graph happens to produce. (First attempt used `lavfi` sources and produced a file
21 dB below the intended level — measure your fixtures before trusting them.)

## 3. Calibration and channel weighting — measured

1 kHz sine, amplitude 0.1 (peak −20.00 dBFS), 10 s, 48 kHz:

| layout | Integrated |
| --- | --- |
| mono (1 ch) | **−23.0 LUFS** |
| stereo (2 identical ch) | **−20.0 LUFS** |

The difference is **3.01 dB = 10·log₁₀2**. So each of the two channels contributes with the **same
weight**, and their energies sum — a stereo file is 3 dB "louder" than the same signal in mono. Two
consequences:

- for **mono and stereo**, the channel weighting is fully determined by the channel *count*; no layout
  knowledge is needed;
- at 1 kHz the sine's −3 dB RMS-vs-peak and the stereo +3 dB cancel, so **I equals the peak dBFS**.
  That makes this fixture the natural calibration anchor for any implementation.

## 4. K-weighting response — measured

Stereo, identical channels, amplitude 0.1, 48 kHz, relative to the 1 kHz reading:

| frequency | Integrated | relative to 1 kHz |
| --- | --- | --- |
| 40 Hz | −26.3 LUFS | **−6.3 dB** |
| 100 Hz | −21.8 LUFS | −1.8 dB |
| 200 Hz | −21.0 LUFS | −1.0 dB |
| 400 Hz | −20.7 LUFS | −0.7 dB |
| 1 kHz | −20.0 LUFS | 0.0 dB |
| 2 kHz | −17.6 LUFS | +2.4 dB |
| 4 kHz | −16.7 LUFS | +3.3 dB |
| 8 kHz | −16.7 LUFS | +3.3 dB |
| 12 kHz | −16.6 LUFS | +3.4 dB |
| 16 kHz | −16.6 LUFS | +3.4 dB |

The shape is a **high-frequency shelf of about +3.4 dB** that has settled by ~4 kHz, and a **high-pass
roll-off below a few hundred Hz** reaching −6.3 dB at 40 Hz. This table is the acceptance target: an
implementation that reproduces it to a stated tolerance has the weighting right, whatever route it took
to the coefficients.

## 5. Sample rate — measured

Same 1 kHz sine, amplitude 0.1, stereo:

| rate | Integrated |
| --- | --- |
| 44 100 | −20.0 LUFS |
| 48 000 | −20.0 LUFS |
| 88 200 | −20.0 LUFS |
| 96 000 | −20.0 LUFS |
| 192 000 | −20.0 LUFS |

**Rate-invariant.** The reference adapts its filter to the sample rate rather than assuming 48 kHz, so
ours must generate coefficients per rate too. A sample-rate sweep is therefore a required test, not a
nicety. **UNRESOLVED**: whether the standard publishes a coefficient table per rate, a single 48 kHz
table plus a prescribed transform, or an analog prototype to discretise. This decides whether we ship a
table or a derivation.

## 6. Gating — measured

10 s at amplitude 0.5 followed by 10 s at amplitude 0.005 (≈ 40 dB quieter), stereo:

```
I: -6.1 LUFS    Threshold: -19.0 LUFS    LRA: 4.8 LU
```

The loud half alone would read ≈ −6 LUFS; an ungated mean of the two halves would land far lower. The
quiet half is **excluded**, so this fixture discriminates a gated implementation from an ungated one and
belongs in the suite. **UNRESOLVED**: the exact absolute and relative gate values, and the block length
and overlap, all of which come from the standard.

## 7. Silence and very short files — measured

| fixture | Integrated |
| --- | --- |
| 5 s of digital silence, stereo | **−70.0 LUFS** |
| 300 ms of 1 kHz sine (shorter than one 400 ms block) | **−70.0 LUFS** |

Both return the **same floor value**, and that is a reporting decision this project cannot inherit
blindly. −70 LUFS is not a measurement of silence; it is where the reference clamps. And a file too
short to contain one complete block has produced **no** gated block at all — nothing was measured, which
is a different statement again.

This maps cleanly onto distinctions the codebase already keeps apart:

- silence → a real measurement, and the honest value is arguably "below the floor" rather than a number;
- shorter than one block → **not computable**, i.e. `unavailable`, exactly as a channel with no frames
  reports for signal levels.

Collapsing them into −70.0 would tell a user their silent file measures the same as their 300 ms file,
which is two different untruths at once.

## 8. Cost — measured

The shape of the work, over **10 minutes of stereo, Release**, on the same chunking (4 096 frames) the
pipeline already uses. Coefficient *values* are placeholders here; cost does not depend on them.

| stage | cost |
| --- | --- |
| two cascaded biquads per channel (`vDSP_biquad`, Float) | **0.117 s** |
| square-and-accumulate per channel (widened to `Double`) | **0.028 s** |
| **total fold** | **≈ 0.14 s** |

For comparison, measured on this machine during `share-waveform-pcm-read`: the waveform's fold costs
**0.30 s** and the whole shared pass **1.20 s (WAV) / 1.79 s (FLAC) / 1.96 s (AAC)**.

**So loudness as a fifth consumer costs roughly half of what the waveform costs, and about 7–12 % of the
pass it would join** — and it opens no second read. That is affordable. What is *not* yet measured is the
block-boundary bookkeeping and the gating pass, both of which are per-block rather than per-sample and
should be small, but "should be" is not a measurement.

## 9. What the pipeline cannot currently know

`PCMStreamDescription` carries `sampleRate`, `channelCount` and `frameCount` — **and no channel layout**.
`AVFoundationAudioFilePropertyReader` reads `channelCount` from the ASBD's `mChannelsPerFrame` and its
own comment says it is "never inferred from channel layouts, labels, or names". Nothing anywhere reads
`AVAudioChannelLayout`.

For mono and stereo this does not matter (§3). For anything else it decides whether a number may be
published at all, because the standard weights channels by their position. **UNRESOLVED**: the exact
weights and the treatment of LFE.

## 10. Findings that shaped the design

1. Integrated loudness is the only one of the four metrics whose value is unambiguous in a **static
   report**; momentary and short-term are meter quantities that would have to be reduced to a maximum or
   a series before they mean anything on a page.
2. The cost is small and the read is already shared — the expensive part of this feature is *correctness*,
   not performance.
3. The blocking unknown is the normative constants, not the architecture.
4. Silence and too-short-to-measure must stay distinct, and neither is "−70".
5. Beyond stereo we cannot currently claim compliance, because we do not know which channel is which.
