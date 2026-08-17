# Design — integrated loudness as a fifth consumer

Evidence in `docs/spikes/2026-08-18-loudness-measurement-validation.md`, whose **Part A** is normative
(document, revision, section for every constant) and whose **Part B** is measurement from FFmpeg 8.1.2.
This design cites Part A for rules and Part B for corroboration, and never mixes them.

## 1. The methodology, and who owns each rule

**The blocking unknown of the first draft is resolved.** The standards were obtained and read:

| ref | document | revision | date |
| --- | --- | --- | --- |
| **N1** | Recommendation ITU-R BS.1770 | **BS.1770-5** | Nov 2023 |
| **N2** | EBU R 128 | **v5.0** | Nov 2023 |
| **N3** | EBU Tech 3341 | **v4** | Nov 2023 |
| **N4** | EBU Tech 3342 (LRA — read only to keep its constants out) | **v4** | Nov 2023 |
| **N5** | Report ITU-R BS.2217 | **BS.2217-2** | Oct 2016 |

**Every algorithm constant belongs to N1, Annex 1.** N2 contributes the unit name **LUFS** (equivalent to
N1's LKFS), the definition of *Programme Loudness*, and the instruction to use N1 eq. (7) — and **no
constant of its own**. This design does not cite R128 for a number BS.1770 owns.

**The trap N4 exists to document**: LRA's relative gate is **−20 LU**; integrated loudness's is
**−10 LU**. Different quantities, different documents, different numbers.

## 2. The four metrics, and why only one ships

| | what it is | window | needs whole file | value in a static report |
| --- | --- | --- | --- | --- |
| **Integrated (LUFS-I)** | gated mean loudness of the programme | whole file, in blocks | **yes** — the relative gate depends on the mean | **one number, unambiguous** |
| Momentary (LUFS-M) | loudness of the last 400 ms, **ungated** (N3 §2.2) | sliding | no | a *meter* reading; a report would have to pick max or a series |
| Short-term (LUFS-S) | loudness of the last 3 s, **ungated** (N3 §2.2) | sliding | no | same problem, longer window |
| Loudness Range (LRA) | spread of short-term loudness, **own −20 LU gate** (N4) | derived from S | yes | meaningful, but needs S plus its own gate and percentiles |

Integrated is the only one whose single value is self-explanatory on a page. Momentary and short-term
are not omitted because they are hard — they are cheap once the weighting exists — but because
**"Momentary: −14.2 LUFS" is meaningless without saying *when***, and answering that means choosing a
reduction (max? last? a timeline?) that is a product decision, not a measurement one. Shipping them
un-reduced would be publishing a number whose meaning we had not decided.

LRA is deferred for the same reason plus two more: it depends on short-term, and its gate is a different
constant that must not travel next to this one before it is needed.

## 3. K-weighting, and the sample-rate decision

Two cascaded 2nd-order IIR sections (N1 Annex 1, Fig. 3), **published for 48 kHz only**:

| | stage 1 — shelving ("spherical head"), N1 Table 1 | stage 2 — RLB high-pass, N1 Table 2 |
| --- | --- | --- |
| b₀ | `1.53512485958697` | `1.0` |
| b₁ | `−2.69169618940638` | `−2.0` |
| b₂ | `1.19839281085285` | `1.0` |
| a₁ | `−1.69065929318241` | `−1.99004745483398` |
| a₂ | `0.73248077421585` | `0.99007225036621` |

**The decisive finding of the reading**: for any other sample rate, N1 states only that coefficients
*should be chosen to give the same frequency response as at 48 kHz*. It publishes **no** prototype, **no**
per-rate table, **no** discretisation method and **no** tolerance. Verified by reading Annex 1 end to end
and searching the document for every occurrence of "sampling rate".

So the three levels stay separate, and ADR-0022 decision 3 carries them:

| level | content |
| --- | --- |
| **Normatively fixed** | the 48 kHz coefficients above; the requirement that other rates match that response |
| **Implementation-equivalent** | any derivation that demonstrably meets it |
| **Our decision, recorded** | recover an analogue prototype from the 48 kHz coefficients and re-discretise per rate — **not** resample the audio to 48 kHz; and the tolerance at which "same response" is judged |

**Acceptance property, mandatory**: at 48 kHz the derivation must reproduce the published coefficients,
and the measured result must be rate-invariant across 44.1/48/88.2/96/192 kHz. Part B §5 shows a
rate-adapting implementation is achievable; it does **not** show ours will match FFmpeg's, which is why
the sweep is a test and not an assumption.

**`vDSP_biquad` is the implementation route**, measured at 0.117 s for two cascaded sections over two
channels of ten-minute audio. It carries its own delay state, which is exactly what a chunked stream
needs. `AVAudioUnitEQ` and `AVAudioConverter` were considered and rejected: both live in Media, both
would drag a media framework into a DSP decision, and neither exposes coefficients we could record with
the measurement.

## 4. Channel layout — the hard constraint, now with a proof

N1 Table 3 weights L/R/C at **1.0** and Ls/Rs at **1.41**, and **excludes the LFE channel entirely**;
N3 §2.10 forbids including it. N1 Annex 3 generalises the weight to a function of a channel's **azimuth
and elevation** — never of its index.

`PCMStreamDescription` carries `sampleRate`, `channelCount`, `frameCount` and **no layout**. The property
reader takes `channelCount` from the ASBD and its own comment says it is "never inferred from channel
layouts, labels, or names". Nothing reads `AVAudioChannelLayout`.

| channels | determined by the count alone? |
| --- | --- |
| **1** | **Yes** — can only be L, C or R; all three weigh 1.0 |
| **2** | **Yes** — the only 2-channel BS.2051 configuration is A (0+2+0), both 1.00, no LFE |
| **3** | **No** — L/C/R would be 1.0 each, but the file could carry an **LFE that must be excluded** |
| **≥ 4** | **No** — position-dependent weights, and 5.1/7.1 carry an LFE |

**Three channels is the counterexample that closes the question.** Getting the LFE wrong moves the result
by more than the ±0.1 LUFS the standards themselves tolerate. Corroborated by measurement (Part B §3):
a stereo pair of identical channels reads exactly **3.01 dB = 10·log₁₀2** above the same signal in mono,
which is the equal weights plus energy summation the text prescribes.

**Decision: measure mono and stereo; report nothing for anything else.** Not a failure — an absence,
because the file offered no way to size the measurement honestly. Reading `AVAudioChannelLayout` to
extend this is a **separate change**: it touches the property reader, the domain and the boundary rules,
and it should not ride along inside a loudness feature.

## 5. Where the DSP lives

`AudioInspectorAnalysis`, behind the existing `AudioDecoding` seam, as ADR-0006 says and as the
spectrogram and true peak already do. `AudioInspectorMedia` keeps AVFoundation; the domain keeps the
value type. No new port: the accumulator takes `PCMChunk` like its three siblings.

## 6. The algorithm, complete

Blocks (N1 Annex 1, eq. (3) and the text after eq. (2)):

- **duration** *T<sub>g</sub>* = **400 ms**, to the nearest sample;
- **overlap shall be 75 %**, so step = 0.25 and the **hop is 100 ms** = `round(0.1 × sampleRate)` frames;
- the **first block starts at frame 0**; no warm-up, no weighting, no skip;
- block indices *j* = 0 … ⌊(*T* − *T<sub>g</sub>*)/(*T<sub>g</sub>*·step)⌋;
- an **incomplete trailing block is discarded** (N1, and N3 §2.3 restates it);
- therefore **one valid block requires T ≥ 400 ms, inclusive** — which the oracle confirms at the
  boundary sample: 400 ms measures, 399 ms does not (Part B §7).

Gating and conversion (N1 eqs. (4), (6), (7)), as normative pseudocode:

```
for each block j:
    for each measured channel i:
        z[i][j] = mean of (K-weighted y_i)^2 over block j
    l[j] = -0.691 + 10*log10( sum_i G[i] * z[i][j] )

J_a = { j : l[j] > -70.0 }                                    # absolute gate
if J_a is empty: UNDEFINED

zbar_a[i] = mean over j in J_a of z[i][j]
Gamma_r = -0.691 + 10*log10( sum_i G[i] * zbar_a[i] ) - 10.0   # relative gate

J_g = { j : l[j] > Gamma_r and l[j] > -70.0 }
if J_g is empty: UNDEFINED

zbar[i] = mean over j in J_g of z[i][j]
L_KG = -0.691 + 10*log10( sum_i G[i] * zbar[i] )               # LUFS
```

Constants, each owned by N1 Annex 1: **Γ<sub>a</sub> = −70 LKFS** (eq. 6), **relative offset = 10 LU**
(eq. 6), **conversion offset = −0.691** (eq. 2, cancelling the K-weighting gain at 997 Hz),
**G = 1.0** for mono and both stereo channels (Table 3), unit **LKFS ≡ LUFS** (N2 footnote 1).

Three details the text settles and an implementation is likely to get wrong:

1. **Eq. (7) keeps both conditions.** Γ<sub>r</sub> is not necessarily above Γ<sub>a</sub>; for a very
   quiet programme the absolute gate binds.
2. **Means are taken over energies and then converted** — never a mean of block loudnesses in dB.
3. **The relative gate needs a first logical pass.** The threshold is unknowable until every block's
   energy has been seen; N3 §2.3 describes exactly this recalculation from stored block levels.

## 7. Streaming state and memory

**Per-sample state is bounded and small**: two biquad sections × 2 delay elements × `channelCount`; one
absolute frame counter; and — because 75 % overlap means every 400 ms block is exactly **four consecutive
100 ms sub-blocks** — a ring of 4 sub-block energy sums plus one partial sum per channel. **No samples are
buffered.**

**Per-block state cannot be bounded, and that is a property of the standard, not a shortcoming.** The
relative gate is derived from the whole programme, so whether a block survives eq. (7) cannot be decided
when the block is produced. **An exact O(1)-memory integrated loudness is impossible in principle.**

**Chosen: one energy per block, gated in two passes over that array.** 10 blocks per second → ≈36 000
blocks and ≈**288 kB per hour** as `Double`; ≈864 kB for three hours. Memory is a function of the **block
count, never of the sample count**. A **histogram was rejected**: it trades exactness inside a ±0.1 LUFS
budget for memory the measurement does not need.

## 8. Numeric strategy

**Not inherited from a sibling.** Signal levels widen to `Double` before reducing because their sums
overflow in `Float`; true peak reconstructs in `Float`. Loudness has a third shape: an **IIR filter**,
where `Float` state can accumulate error over millions of samples, followed by an energy sum that has
the same overflow exposure signal levels had.

**Starting position, to be confirmed by measurement, not assumed**: filter in `Float` via `vDSP_biquad`
(measured 0.117 s), widen to `Double` before squaring and accumulating (measured 0.028 s). Task group 4
measures `Float` against `Double` filter state on a long file against the published targets and picks
with numbers. If `Float` state drifts measurably, the filter moves to `Double` and the cost is
re-measured.

**No clamp anywhere.** N1's loudness path contains no limit or saturation step; its only attenuation is a
12.04 dB integer-headroom step in the *true-peak* Annex, which that text itself calls unnecessary in
floating point. Samples above unity are measured as they are.

## 9. Chunk independence — the risk this feature carries

An IIR filter plus fixed-length blocks is the most chunk-sensitive thing this codebase has attempted.
Filter state must cross chunk boundaries and block boundaries must be absolute, not per-chunk.

The guarantee must be the one every other analysis already keeps: **identical at every chunk size**, over
the sizes the suites already use (1, 3, 127, 512, 4 096, 65 536, whole file). A tolerance here would be
admitting the state is not carried correctly. If exact equality proves impossible in `Float`, that is
evidence for `Double` state (§8), not for a widened tolerance.

## 10. Domain model

A **sibling type**, `LoudnessMeasurement`, beside `SignalLevelMetrics` and `TruePeakMeasurement` —
`Sendable`, `Equatable`, failable, not `Codable` (ADR-0009).

Extending `SignalLevelMetrics` was rejected: it holds direct sample-domain facts, per channel, with no
weighting and no time structure. Loudness is frequency-weighted, gated, time-blocked and **whole-file**;
there is no per-channel loudness to report, because the channels are summed before the number exists.

It carries its **method**, and §3 makes that heavier than for true peak: enough to reproduce the value
**and to tell the two compliance tiers apart** — the standard revision, the weighting's identity,
**whether the coefficients were the published 48 kHz set or derived for the file's rate**, the block
length and overlap, and both gate values, tied to the analysis engine version.

## 11. Unit, silence, and the too-short file

**Decision: the domain stores LUFS.** True peak stores linear because dBTP is a *presentation* of a
linear peak; here the normative quantity **is** the logarithmic one — "−14.2 LUFS" is the measurement,
not a rendering of it. Storing linear energy and converting in the view would invent a unit the standard
does not use and would put the conversion offset in the presentation layer, where it cannot be tested
against the oracle.

**Both undefined cases are settled by N1, and neither is −70:**

- **shorter than one block** → `unavailable`. The block index set is empty, so nothing was measured.
  N3 §2.8 states that what a meter shows before there is sufficient data is deliberately unspecified.
- **digital silence** → `unavailable`. Every block's loudness is −∞ and so fails the absolute gate; the
  gated set is empty and eq. (7) divides by zero. **N5**'s compliance table corroborates: for a file with
  no measurable signal the expected reading is the lowest resolvable value **or −infinity** — the ITU
  declines to name −70.

**−70 LUFS is the absolute gate, not a result.** The oracle returns exactly −70.000 for both (Part B §7);
that is its floor. Publishing it would say a silent file measures the same as a 300 ms file.

The **outcome is one absence; the causes stay distinct in the record** — silence produced blocks and gated
them all away, a short file produced none — and the boundary between them is exact: **400 ms measures,
399 ms does not**.

## 12. Presentation and export

**Copy, not implementation.** Label "Integrated loudness", value "−14.2 LUFS" at one decimal — which is
also N3 §2.8's display precision — method shown beside it as true peak's already is. No per-channel row.
Absence reads as the existing "not computable" phrasing rather than a number.

**Forbidden, and this is the whole point of the feature being a measurement**: "too loud", "too quiet",
"bad master", "streaming ready", any platform target, any normalisation advice, any comparison to −14 or
**−23 — including R128's own −23.0 LUFS target**, which is a broadcast delivery requirement, not a
property of a file. The report states what was measured.

Export: additive under `measurements`, alongside `signalLevels` and `truePeak`, absent when not
measured. `schemaVersion` stays **1**. No path, no location, deterministic for a given file and engine
version.

## 13. Verification targets — published, not observed

**Primary, from N3 Table 1** (all ±0.1 LUFS, all synthesisable from their published description with no
protected material):

| test | signal | expected | what it discriminates |
| --- | --- | --- | --- |
| #1 | stereo 1 kHz, −23.0 dBFS peak, in phase, 20 s | **−23.0** | calibration and channel summation |
| #2 | as #1 at −33.0 dBFS | **−33.0** | linearity |
| #3 | 10 s @ −36, 60 s @ −23, 10 s @ −36 | **−23.0** | **the relative gate** |
| #4 | 10 s @ −72, 10 s @ −36, 60 s @ −23, 10 s @ −36, 10 s @ −72 | **−23.0** | **the absolute gate** |
| #5 | 20 s @ −26, 20.1 s @ −20, 20 s @ −26 | **−23.0** | a negative control — correct gating changes nothing |
| §2.9 | stereo 1 kHz, −18.0 dBFS peak | **−18.0** | the published calibration signal |

Plus **N1**'s own anchor: one channel at 0 dBFS, 997 Hz → **−3.01 LKFS**.

N3 tests **7–8** are authentic programme segments — usable locally from the EBU, **never committed**.
Tests 6 (5.0) and 9–14 (M/S) are out of scope. **N5**'s compliance WAVs were not obtained; the Report is
a description of them.

**Secondary, corroboration only** — Part B's measured K-weighting response curve, the 40 dB gating
fixture, and the rate sweep. An observed target proves agreement with the thing observed, so these rank
below the published values.

**The oracle is qualified**: FFmpeg 8.1.2 passes N3 tests 1–5 and §2.9 within the published tolerance
(Part B §2). Its summary is INFO-level and prints one decimal; `ebur128=metadata=1` with
`lavfi.r128.I` prints three, which is where any tolerance tighter than 0.1 LUFS must come from. Its
`Integrated loudness:` block reports `Threshold:` — **the relative gate**, a second checkable
intermediate — while the `Loudness range:` block reports a *different* threshold on a −20 LU gate;
confusing them is a silent 10 LU error. FFmpeg is **not in CI**, so the suite stays local evidence behind
the existing `FFmpegTool.isAvailable` pattern.

## 14. Alternatives considered

| | | |
| --- | --- | --- |
| **A** | **Integrated only** | **Chosen.** The one metric with an unambiguous single value in a static report. |
| B | Integrated + Momentary + Short-Term | Rejected *for now*: cheap to compute, but each needs a reduction decision (max? series?) that is a product question, and shipping them unreduced publishes numbers whose meaning is undecided. |
| C | Integrated + LRA | Rejected: LRA needs short-term, so B precedes it — and its −20 LU gate is a constant best kept out of this change. |
| D | Extend `SignalLevelMetrics` | Rejected: mixes weighted temporal quantities with direct sample facts. |
| E | Shell out to FFmpeg for shipped values | Rejected by ADR-0006 and unchanged: it ties correctness to bundling FFmpeg. It remains the oracle. |
| F | Read `AVAudioChannelLayout` to support surround now | Rejected as scope: it touches the property reader, the domain and the boundaries, and belongs in its own change. |
| G | Resample to 48 kHz and use the published coefficients | Rejected: it measures a converted signal rather than the file, for a tier of claim not worth a resampler. |
| H | Histogram the block loudnesses | Rejected: quantisation error inside a ±0.1 LUFS budget, buying memory that is not scarce. |
