# Spike — loudness measurement, before designing it

**Date**: 2026-08-18 (two sessions) · **Status**: complete, informing change `add-loudness-measurement` ·
**Machine**: one Apple Silicon Mac, one SDK. Timings do not carry forward; the semantic findings do.

The first session could measure a reference implementation but had not read the standards, so it
recorded no constant as a normative fact. The second session obtained and read them. **This document is
therefore split in two, and the split is load-bearing:**

- **Part A — normative facts.** Every statement carries its document, revision and section. Nothing here
  is measured, inferred or remembered.
- **Part B — empirical oracle observations.** Everything measured from FFmpeg 8.1.2. Nothing here is
  normative, however well it agrees with Part A.

A number that appears in both parts appears twice, once as a rule and once as a measurement. They are
never merged.

---

# Part A — Normative facts

## A0. The documents that were read

Obtained from the publishers and read in full for the parts that govern integrated loudness.

| # | Document | Revision / version | Date | Publisher | What it governs here |
| --- | --- | --- | --- | --- | --- |
| **N1** | Recommendation ITU-R BS.1770, *Algorithms to measure audio programme loudness and true-peak audio level* | **BS.1770-5** | Nov 2023 | ITU-R | **The entire algorithm**: K-weighting, channel weights, blocks, both gates, the LUFS/LKFS conversion |
| **N2** | EBU R 128, *Loudness normalisation and permitted maximum level of audio signals* | **v5.0 (R 128-2023)** | Nov 2023 | EBU | The **name** LUFS, the definition of *Programme Loudness*, and the requirement to use BS.1770 eq. (7). **No algorithm constants of its own.** |
| **N3** | EBU Tech 3341, *Loudness Metering: 'EBU Mode'* | **v4** | Nov 2023 | EBU | Meter obligations, the **compliance test set** and its tolerances, the calibration signal, the LFE prohibition |
| **N4** | EBU Tech 3342, *Loudness Range* | **v4** | Nov 2023 | EBU | **LRA only** — read solely to prove its constants are *different* and must not leak into integrated loudness |
| **N5** | Report ITU-R BS.2217, *Compliance material for Recommendation ITU-R BS.1770* | **BS.2217-2** | Oct 2016 | ITU-R | The ITU compliance file list, its tolerance, and the expected reading when nothing measurable is present |

EBU Tech 3343 (production guidelines) was obtained and found to contain **no** methodology binding on
this measurement. It is not cited below.

**FFmpeg is not in this table.** It is an implementation, and Part B is where it belongs.

## A1. Attribution matrix — which document owns which rule

The single most important outcome of the reading: **EBU R 128 defines almost none of the algorithm.**
It sets a target level and a unit name and delegates everything else to BS.1770. Attributing a gate
value or a coefficient to "R128" is wrong, and this project does not do it.

| Element | Document | Section / item | Rule or constant |
| --- | --- | --- | --- |
| K-weighting, stage 1 (shelving, "spherical head") | **N1** BS.1770-5 | Annex 1, Fig. 3 + **Table 1** | 2nd-order IIR, coefficients below, **at 48 kHz** |
| K-weighting, stage 2 (RLB high-pass) | **N1** BS.1770-5 | Annex 1, Fig. 3 + **Table 2** | 2nd-order IIR, coefficients below, **at 48 kHz** |
| Behaviour at other sample rates | **N1** BS.1770-5 | Annex 1, notes under Tables 1 and 2 | **A goal, not a transform** — see A3 |
| Channel weights *G<sub>i</sub>* (≤ 5 main channels) | **N1** BS.1770-5 | Annex 1, **Table 3** | L/R/C = 1.0; Ls/Rs = 1.41 |
| Channel weights, advanced sound systems | **N1** BS.1770-5 | Annex 3, **Tables 4 and 5** | by azimuth/elevation; stereo = config A (0+2+0), both 1.00 |
| LFE treatment | **N1** BS.1770-5 | Annex 1 (opening) | **Excluded from the measurement** |
| LFE, reinforced | **N3** Tech 3341 | §2.10 | Shall **not** be included in 'EBU Mode'; including it forfeits both EBU Mode and BS.1770 compliance |
| Block duration *T<sub>g</sub>* | **N1** BS.1770-5 | Annex 1, after eq. (2) | **400 ms**, to the nearest sample |
| Block overlap | **N1** BS.1770-5 | Annex 1, after eq. (2) | **shall be 75 %** of the block duration |
| Block index set / hop | **N1** BS.1770-5 | Annex 1, **eq. (3)** | step = 1 − overlap = 0.25 → **hop 100 ms** |
| Trailing partial block | **N1** BS.1770-5 | Annex 1, after eq. (2) | Incomplete final blocks are **not used** |
| Trailing partial block, restated | **N3** Tech 3341 | §2.3 | An incomplete gating block at the end **shall be discarded** |
| Absolute gate Γ<sub>a</sub> | **N1** BS.1770-5 | Annex 1, **eq. (6)** | **−70 LKFS** |
| Relative gate Γ<sub>r</sub> | **N1** BS.1770-5 | Annex 1, **eq. (6)** | absolute-gated loudness **− 10** (LU) |
| Relative gate offset history | **N2** R 128 · **N4** Tech 3342 | Document History (both) | changed **−8 → −10 LU** in Aug 2011 |
| Final gated set | **N1** BS.1770-5 | Annex 1, **eq. (7)** | *l<sub>j</sub>* > Γ<sub>r</sub> **and** *l<sub>j</sub>* > Γ<sub>a</sub> |
| Energy aggregation | **N1** BS.1770-5 | Annex 1, eqs. (1), (3), (5), (7) | mean of **block mean-squares**, per channel, then channel-weighted sum |
| Loudness conversion offset | **N1** BS.1770-5 | Annex 1, **eq. (2)** + NOTE 1 | **−0.691**, cancels K-weighting gain at 997 Hz |
| Unit | **N1** BS.1770-5 | Annex 1, after eq. (7) | **LKFS** |
| Unit, equivalence | **N2** R 128 | §e) + footnote 1 | **LUFS ≡ LKFS**; EBU prefers LUFS |
| Integrated loudness definition | **N2** R 128 | *Definitions* | *Programme Loudness* = integrated loudness over the programme, via BS.1770 **eq. (7)** |
| Silence / nothing measurable | **N5** BS.2217-2 | compliance table, LFE row | lowest resolvable value, **or −infinity** — explicitly **not** a −70 floor |
| Insufficient data | **N3** Tech 3341 | §2.8 | 'EBU Mode' **does not specify** what to indicate until there is enough input for a valid result |
| Compliance tolerance | **N3** Tech 3341 · **N5** BS.2217-2 | Table 1 · Summary | **±0.1 LUFS / ±0.1 LKFS** |
| **LRA — different gate, do not reuse** | **N4** Tech 3342 | §"cascaded gating" | absolute −70 LUFS, relative **−20 LU**, 3 s windows, 10th/95th percentiles |

The last row is the trap this matrix exists to prevent: LRA's relative gate is **−20 LU**, integrated
loudness's is **−10 LU**. They are different numbers in different documents for different quantities.

## A2. K-weighting — exactly what is published

**N1** BS.1770-5, Annex 1. Two cascaded 2nd-order sections, both in the direct form of its Fig. 3
(*a*<sub>0</sub> = 1 implied; the *a* coefficients are subtracted in the feedback path).

**Stage 1 — shelving filter, modelling the acoustic effect of a rigid-sphere head** (Table 1):

| | |
| --- | --- |
| b<sub>0</sub> | `1.53512485958697` |
| b<sub>1</sub> | `−2.69169618940638` |
| b<sub>2</sub> | `1.19839281085285` |
| a<sub>1</sub> | `−1.69065929318241` |
| a<sub>2</sub> | `0.73248077421585` |

**Stage 2 — RLB (revised low-frequency B-curve) high-pass** (Table 2):

| | |
| --- | --- |
| b<sub>0</sub> | `1.0` |
| b<sub>1</sub> | `−2.0` |
| b<sub>2</sub> | `1.0` |
| a<sub>1</sub> | `−1.99004745483398` |
| a<sub>2</sub> | `0.99007225036621` |

The concatenation of the two stages is what the Recommendation designates **K-weighting**.

Two notes that the Recommendation attaches to these tables and that matter to us:

1. **Both tables are for a 48 kHz sampling rate.** This is stated separately under each table.
2. The coefficients may need quantising to the available precision, and the Recommendation states that
   the algorithm's performance has been found **not sensitive to small variations** in them. That is a
   licence for numeric format choices — it is *not* a licence for different coefficients.

## A3. Sample rate — what is prescribed, and what is not

This was the question with the most consequential answer, and it is not the one that was expected.

**What the Recommendation prescribes** (N1, Annex 1, under Tables 1 and 2): implementations at other
sampling rates require different coefficient values, and those values *should be chosen to provide the
same frequency response that the specified filter provides at 48 kHz*.

**What the Recommendation does not publish** — verified by reading Annex 1 end to end and by searching
the whole document for every occurrence of "sampling rate" and "sample rate":

- **no** coefficient table for any rate other than 48 kHz;
- **no** analogue prototype, and no pole/zero or *Q*/*f*<sub>0</sub>/gain parameterisation of either stage;
- **no** prescribed discretisation method — the bilinear transform is never mentioned in Annex 1;
- **no** tolerance on "the same frequency response".

So, against the five candidate shapes this spike set out to choose between:

| | candidate | verdict |
| --- | --- | --- |
| **A** | fixed digital coefficients for 48 kHz only | **This is what is published** — and *only* this |
| B | analogue prototype + bilinear transform | **Not published.** No prototype exists in the text |
| C | parameterised digital coefficients | Not published |
| D | a table per sample rate | Not published |
| E | a combination | Not published |

**The correct answer is A plus an unmet obligation.** BS.1770-5 fixes the filter at 48 kHz and states a
*goal* for every other rate without giving a construction that reaches it. Any rate other than 48 kHz is
therefore served by an implementation's own derivation.

This has a direct consequence for how far compliance may be claimed, recorded in ADR-0022:

- **at 48 kHz** — the coefficients are normatively fixed and can be used literally. Conformance to the
  published filter definition is exact and demonstrable;
- **at every other rate** — the coefficients are *ours*. What is normative is only the property they must
  have (the 48 kHz response). Conformance is a claim about a **derivation we chose**, demonstrated by
  measurement, not a claim about published numbers.

Classifying the three levels the project must keep apart:

| level | what belongs to it |
| --- | --- |
| **Normatively fixed** | the 48 kHz coefficients (A2); the requirement that other rates match the 48 kHz response |
| **Implementation-equivalent** | any derivation that demonstrably meets that requirement |
| **Our own decision, to be recorded** | *which* derivation, and the tolerance at which "same response" is judged |

## A4. Channel weighting and LFE

**N1** BS.1770-5, Annex 1, Table 3 — for programmes of up to five main channels:

| channel | *G<sub>i</sub>* |
| --- | --- |
| Left, Right, Centre | **1.0** (0 dB) |
| Left surround, Right surround | **1.41** (≈ +1.5 dB) |

The **LFE channel is excluded** from the measurement (Annex 1, opening). **N3** Tech 3341 §2.10
reinforces this: until its inclusion is standardised in BS.1770 it shall not be included in an 'EBU Mode'
meter, and a meter that includes it is no longer BS.1770-compliant. Tech 3341 records a *hypothetical*
+10 dB weight should the ITU ever include it — **that is not a rule and must never be implemented as one.**

Beyond five channels, **N1** Annex 3 replaces the fixed table with a **position-dependent** weight
(Table 4): a channel is weighted 1.41 only when its azimuth is between 60° and 120° and its elevation is
within ±30°; everything else is 1.00. Table 5 then applies this to each BS.2051 loudspeaker
configuration. Stereo is configuration **A (0+2+0)**, whose two channels (M+030, M−030) both weigh
**1.00**.

**The weight of a channel is a function of its position, never of its index.** That single sentence is
what decides A11 below.

## A5. Gating blocks

**N1** BS.1770-5, Annex 1, after eq. (2) and in eq. (3):

- **Block duration** *T<sub>g</sub>* = **400 ms**, *to the nearest sample*.
- **Overlap** **shall be 75 %** of the block duration.
- Therefore **step = 1 − overlap = 0.25** and the **hop is 100 ms** — `round(0.1 × sampleRate)` frames.
- The **first block starts at the beginning** of the measurement interval (eq. (3) indexes from *j* = 0).
- The block index set is *j* = 0, 1, 2, …, ⌊(*T* − *T<sub>g</sub>*) / (*T<sub>g</sub>* · step)⌋.
- The measurement interval **shall end at the end of a gating block**, and **incomplete gating blocks at
  the end are not used**. **N3** Tech 3341 §2.3 states the same obligation in meter terms.

**The minimum condition for one valid block follows arithmetically from the index set**: with
*T* = *T<sub>g</sub>* the set is {0} — exactly one block. With *T* < *T<sub>g</sub>* it is empty. So the
threshold is **T ≥ 400 ms**, inclusive, and a programme shorter than that yields **no blocks at all**.

Nothing special is prescribed for the first block: it is not warmed up, not weighted, not skipped. The
filter simply starts from rest.

## A6. Gating — the exact algorithm

Per **N1** BS.1770-5, Annex 1, eqs. (3), (4), (6), (7).

Per block *j* and channel *i*, *z<sub>ij</sub>* is the **mean square** of the K-weighted channel over the
block. Block loudness (eq. (4)):

> *l<sub>j</sub>* = −0.691 + 10 · log₁₀ ( Σ<sub>i</sub> *G<sub>i</sub>* · *z<sub>ij</sub>* )

**Absolute gate** (eq. (6)): Γ<sub>a</sub> = **−70 LKFS**, applied to *l<sub>j</sub>* — that is, **per
block, after the channel-weighted sum**, with a **strict** inequality. It is not per channel and not per
programme.

**Relative gate** (eq. (6)): Γ<sub>r</sub> is the loudness computed over the absolutely-gated blocks,
**minus 10**. It therefore **requires a first logical pass**: the threshold cannot be known until every
block's energy has been seen.

**Final result** (eq. (7)): the gated loudness over the blocks satisfying **both** conditions.

Normative pseudocode — deliberately not Swift:

```
# pass 0 — per block
for each gating block j:
    for each measured channel i:
        z[i][j] = mean of (K-weighted y_i)^2 over block j     # eq. (3)
    l[j] = -0.691 + 10*log10( sum_i G[i] * z[i][j] )          # eq. (4)

# pass 1 — absolute gate
J_a = { j : l[j] > -70.0 }                                    # eq. (6), Gamma_a
if J_a is empty:
    integrated loudness is UNDEFINED                          # see A7

for each measured channel i:
    zbar_a[i] = (1/|J_a|) * sum over j in J_a of z[i][j]
Gamma_r = -0.691 + 10*log10( sum_i G[i] * zbar_a[i] ) - 10.0  # eq. (6)

# pass 2 — relative gate
J_g = { j : l[j] > Gamma_r and l[j] > -70.0 }                 # eq. (7)
if J_g is empty:
    integrated loudness is UNDEFINED

for each measured channel i:
    zbar[i] = (1/|J_g|) * sum over j in J_g of z[i][j]
L_KG = -0.691 + 10*log10( sum_i G[i] * zbar[i] )              # eq. (7)
```

Three details that are easy to get wrong and are settled by the text:

1. **Both conditions survive into eq. (7).** Γ<sub>r</sub> is not necessarily above Γ<sub>a</sub> — for a
   very quiet programme the absolute gate is the binding one — which is why eq. (7) carries both and why
   the pseudocode must too.
2. **The mean is taken over energies, then converted** — never a mean of block loudnesses in dB.
3. **The recomputation is over the same per-block energies**, not over the samples: pass 2 revisits the
   block set, so per-block energies must survive pass 1. **N3** Tech 3341 §2.3 says exactly this for live
   meters — the result is recalculated from the *stored* block loudness levels each time the reading
   updates.

## A7. Energy → LUFS, and the undefined cases

**Conversion** (**N1** eq. (2), and identically inside (4), (6), (7)):

> *L* = −0.691 + 10 · log₁₀ ( Σ<sub>i</sub> *G<sub>i</sub>* · *z<sub>i</sub>* )   [LKFS]

Base-10 logarithm; factor **10**, because *z* is a power quantity; offset exactly **−0.691**, which
**N1** NOTE 1 states cancels the K-weighting gain at 997 Hz. The unit is **LKFS**, which **N2** R 128
footnote 1 declares equivalent to **LUFS**.

**N1** also supplies its own calibration statement: a 0 dBFS, 997 Hz sine applied to the **left, centre or
right** channel reads **−3.01 LKFS**. (997 Hz is the exact reference frequency per IEC 61606; 1 kHz is
the nominal name for it.)

**Undefined cases.** Both arise from the pseudocode above and neither is a floor value:

- **Digital silence.** Every block has *z* = 0, so *l<sub>j</sub>* is −∞ and **no block satisfies
  *l<sub>j</sub>* > −70**. *J<sub>a</sub>* is empty, |*J<sub>a</sub>*| = 0, and eq. (7) divides by it.
  **The quantity is not defined.** **N5** BS.2217-2 corroborates the direction: for its LFE-only
  compliance file — a file with signal but no *measurable* signal — the expected reading is the meter's
  lowest resolvable value **or −infinity**, and the Report says so explicitly rather than naming −70.
- **Programme shorter than one block.** The block index set of A5 is empty, so there is no *l<sub>j</sub>*
  at all. **N3** Tech 3341 §2.8 confirms this is deliberately unspecified: 'EBU Mode' does not say what a
  meter should indicate until there is sufficient input data for a valid result.

**These are two different causes with the same outcome**, and the project keeps the causes distinct even
though the reported outcome is identical: silence produced blocks and gated them all away; a 300 ms file
produced none. **Neither is −70 LUFS.** −70 is the absolute *gate*, and the standard never uses it as a
result.

## A8. Sample magnitudes greater than 1

Searched Annex 1 in full. **No clamp, no limit, no saturation and no headroom step appears anywhere in
the loudness path.** Eq. (1) is a plain mean square of the filtered signal, and the filter definition is
a plain IIR.

The only attenuation in the whole Recommendation is in **Annex 2**, where a 12.04 dB attenuation gives
integer arithmetic headroom for **true-peak** measurement — and even there the text states it is
**unnecessary in floating point**. That is a different Annex measuring a different quantity.

**Conclusion: samples above unity are processed normally.** The project's expectation of "no clamp" is
not merely compatible with the methodology, it is what the methodology says.

## A9. Official test vectors

Two official sets exist, both with a published tolerance of **±0.1 LUFS / ±0.1 LKFS**.

**N3** EBU Tech 3341, Table 1 — 'minimum requirements' compliance signals. Reproducibility for us:

| test | signal | expected | reproducible locally? |
| --- | --- | --- | --- |
| **1** | stereo 1 kHz, −23.0 dBFS peak, in phase, 20 s | **I = −23.0** | **yes** — fully specified by level and duration |
| **2** | as #1 at −33.0 dBFS | **I = −33.0** | **yes** |
| **3** | 10 s @ −36, 60 s @ −23, 10 s @ −36 | **I = −23.0** | **yes** — this is the **relative-gate** discriminator |
| **4** | 10 s @ −72, 10 s @ −36, 60 s @ −23, 10 s @ −36, 10 s @ −72 | **I = −23.0** | **yes** — this is the **absolute-gate** discriminator |
| **5** | 20 s @ −26, 20.1 s @ −20, 20 s @ −26 | **I = −23.0** | **yes** — a *negative* control: correct gating changes nothing here |
| 6 | 5.0 channel, per-channel levels | I = −23.0 | out of scope (needs layout) |
| 7, 8 | authentic programme segments, NLR and WLR | I = −23.0 | **downloadable from the EBU, but copyrighted — must not be committed** |
| 9–14 | momentary / short-term maxima | M/S targets | out of MVP scope |
| 15–23 | true-peak signals | dBTP targets | belong to ADR-0019's measurement, not this one |

**Tests 1–5 are pure tones defined entirely by level and duration.** They can be synthesised from their
published description, contain no protected material, and are strictly better acceptance targets than
the invented fixtures of the first session, because their expected values are published rather than
observed.

**N3** §2.9 also gives a **calibration signal**: stereo 1 kHz sine, in phase, peak **−18 dBFS**, which a
meter should read as **−18.0 LUFS**. Tech 3341 attaches a warning worth carrying: 1 kHz sits on a filter
slope, so this calibration is more sensitive to filter accuracy and to the exactness of the tone's
frequency than one might expect — which is also why **N1** specifies 997 Hz.

**N5** Report ITU-R BS.2217-2 lists the ITU's own compliance files (48 kHz, 16-bit WAV) with expected
readings: a relative-gate test, an absolute-gate test, sine waves at 25/100/500/1000/2000/10000 Hz all
normalised to a single reading, a frequency sweep, channel-check and summing files. **The audio files
themselves were not obtained** — the Report is a table describing them. Their *descriptions* are still
useful: the frequency series is an independent statement of the K-weighting shape, and the LFE row is
the source cited in A7.

## A10. What BS.1770-5 says about pure tones

Annex 1 closes with a caveat this project should repeat rather than hide: the algorithm has been shown
effective for typical broadcast programme material and **is not, in general, suitable for estimating the
subjective loudness of pure tones**.

This does not weaken the sine fixtures — Tech 3341 and BS.2217 both use tones precisely because they are
exactly predictable — but it fixes what they prove. **A sine fixture verifies the algorithm, never the
perceptual claim.** Our acceptance targets are algorithmic.

## A11. What the standards require that the pipeline cannot supply

`PCMStreamDescription` carries `sampleRate`, `channelCount` and `frameCount`, and **no channel layout**.
`AVFoundationAudioFilePropertyReader` reads `channelCount` from the ASBD and its own comment states that
it is never inferred from channel layouts, labels or names. Nothing in the codebase reads
`AVAudioChannelLayout`.

Against A4, a channel count alone is sufficient **only** where every configuration with that count agrees
on the weights:

| channels | is the weighting determined by the count alone? |
| --- | --- |
| **1** | **Yes.** A single channel can only be one of L, C or R, and **N1** Table 3 weights all three **1.0**. Which one it is cannot change the answer. |
| **2** | **Yes.** The only two-channel BS.2051 configuration is **A (0+2+0)**, whose channels both weigh **1.00**, and it contains no LFE. |
| **3** | **No.** L/C/R would be 1.0 each — but a three-channel file could equally carry an LFE, which **must be excluded entirely**. Excluding the wrong channel, or none, changes the result materially. |
| **≥ 4** | **No.** Table 5 assigns 1.00 or 1.41 by **position**, and 5.1 and 7.1 contain an LFE that must be removed. Index order is a convention of a container, not a fact the standard accepts. |

**Three channels is the case that settles it.** It is the most tempting "surely this one is safe", and it
is not safe, because the LFE question alone can change the answer by more than the entire compliance
tolerance. There is no partial extension that is defensible without real layout metadata.

---

# Part B — Empirical oracle observations

**Everything in this part is FFmpeg 8.1.2** (Homebrew, `/opt/homebrew/bin/ffmpeg`), filter `ebur128`,
which ADR-0006 already names as the reference. **None of it is normative.** Where it agrees with Part A
that is evidence about FFmpeg, not about the standard.

## B1. The oracle, exactly

```
ffmpeg -hide_banner -nostats -i FILE -filter_complex ebur128 -f null -
```

- **The summary is emitted at INFO level**, so `-loglevel error` silently discards it — an hour lost to
  that in the first session, recorded so nobody repeats it.
- Fields in the `Integrated loudness:` block: **`I:`** — the integrated value, and **`Threshold:`** — the
  **relative gate** Γ<sub>r</sub>. The second field is worth as much as the first: it is an independently
  checkable intermediate of A6, so an implementation can be compared at two points rather than one.
- The `Loudness range:` block that follows has **its own, different `Threshold:`**, which is LRA's −20 LU
  gate (A1, last row). **The two `Threshold:` lines are not the same quantity.** Parsing the wrong one is
  a silent 10 LU error.
- `ebur128=peak=true` adds a true-peak block.

**Higher precision is available and the summary is not the only channel**:

```
ffmpeg -hide_banner -nostats -i FILE \
  -filter_complex "ebur128=metadata=1,ametadata=mode=print:key=lavfi.r128.I" -f null -
```

The summary prints **one** decimal; `lavfi.r128.I` prints **three**. The last emitted value is the
integrated result. Any tolerance tighter than 0.1 LUFS must come from the metadata route.

**Not a runtime dependency**, and **not present in CI**: `.github/workflows/ci.yml` runs on `macos-26`
and installs nothing. The existing `TruePeakOracleTests` pattern — `FFmpegTool.isAvailable` with an
`.enabled(if:)` trait and an explicit message that a skip is not evidence of agreement — is the pattern
this measurement must reuse.

## B2. The oracle qualified against the normative test set

**This is the new result of the second session, and it changes the standing of every other line in Part B.**
The Tech 3341 tests 1–5 and the §2.9 calibration signal (A9) were synthesised from their published
descriptions as float32 WAV at 48 kHz and measured:

| test | published expectation (N3) | FFmpeg 8.1.2 | `Threshold:` | verdict |
| --- | --- | --- | --- | --- |
| 3341 #1 | −23.0 ±0.1 LUFS | **−23.0** | −33.0 | **pass** |
| 3341 #2 | −33.0 ±0.1 LUFS | **−33.0** | −43.0 | **pass** |
| 3341 #3 (relative gate) | −23.0 ±0.1 LUFS | **−23.0** | −34.2 | **pass** |
| 3341 #4 (absolute gate) | −23.0 ±0.1 LUFS | **−23.0** | −34.2 | **pass** |
| 3341 #5 (gating no-op) | −23.0 ±0.1 LUFS | **−23.0** | −33.0 | **pass** |
| 3341 §2.9 calibration | −18.0 LUFS | **−18.0** | −28.0 | **pass** |

Two corroborations beyond the pass/fail:

- **#3 and #4 report the same threshold, −34.2.** They differ only by the two −72 dBFS segments, so the
  absolute gate removed exactly those blocks before the relative threshold was computed — the behaviour
  A6 describes, visible in an intermediate value.
- **#5's threshold is exactly −33.0 = −23.0 − 10**, i.e. the relative gate excluded nothing. A negative
  control that passes for the right reason.

**FFmpeg 8.1.2's `ebur128` therefore passes the EBU minimum-requirements integrated-loudness tests within
the published tolerance.** That upgrades it from *a convenient second implementation* to *a second
implementation demonstrated against the publisher's own acceptance set*, which is what a cross-check needs
to be worth running.

## B3. Calibration and channel weighting

1 kHz sine, in phase, 48 kHz, measured at full metadata precision:

| fixture | FFmpeg | Part A prediction | source of the prediction |
| --- | --- | --- | --- |
| **mono**, −23.0 dBFS peak | **−26.010** | **−26.01** | **N1** A7: 0 dBFS into one of L/C/R reads −3.01 LKFS |
| **stereo**, −23.0 dBFS peak | **−23.000** | −23.0 | **N3** Tech 3341 test #1 |
| stereo, −18.0 dBFS peak | −18.000 | −18.0 | **N3** Tech 3341 §2.9 |
| stereo, −20.0 dBFS peak (first session) | −20.0 | −20.0 | derived from the same rule |
| mono, −20.0 dBFS peak (first session) | −23.0 | −23.01 | derived from the same rule |

**The mono row is the strongest single result in this document.** BS.1770-5 states its own anchor as a
rule — one channel at 0 dBFS reads −3.01 LKFS — and the oracle reproduces it to three decimals at a
different level. Norm and oracle agree exactly; there is nothing to diagnose.

The mono/stereo difference is **3.01 dB = 10·log₁₀2**, which is what A4's *G* = 1.0 for both channels
plus A6's energy summation predicts. **Measurement and text agree, by two independent routes.**

## B4. K-weighting response — measured

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

A high-frequency shelf of about +3.4 dB settled by ~4 kHz, over a high-pass roll-off reaching −6.3 dB at
40 Hz — the two stages of A2, in that order.

**N5** BS.2217-2 describes an independent version of this same curve: its compliance sines at
25/100/500/1000/2000/10000 Hz are pre-levelled to approximately −13/−22/−23/−24/−26/−27 dBFS so that all
read the same loudness, which implies roughly −11/−2/−1/0/+2/+3 dB of weighting. The shapes agree. The
BS.2217 levels are given as approximate in the Report and are **not** a substitute for its actual files.

**This table remains useful but is demoted.** It is now a *corroborating* target measured from an
implementation; the *primary* acceptance targets are A9's published values.

## B5. Sample rate — measured

Same 1 kHz sine, amplitude 0.1, stereo:

| rate | Integrated |
| --- | --- |
| 44 100 | −20.0 LUFS |
| 48 000 | −20.0 LUFS |
| 88 200 | −20.0 LUFS |
| 96 000 | −20.0 LUFS |
| 192 000 | −20.0 LUFS |

**Rate-invariant**, so the oracle does adapt its filter per rate rather than assuming 48 kHz. Read
together with **A3**, this is now a much sharper finding than it was: the standard does not say *how* to
adapt, so this measurement shows that a rate-adapting derivation **exists and works**, not that ours will
match FFmpeg's. Rate-invariance is a property our own derivation must be tested for, and the sweep is a
required test.

## B6. Gating — measured

10 s at amplitude 0.5 followed by 10 s at amplitude 0.005 (≈ 40 dB quieter), stereo:

```
I: -6.1 LUFS    Threshold: -19.0 LUFS    LRA: 4.8 LU
```

The quiet half is excluded, so the fixture discriminates a gated implementation from an ungated one.
**Superseded as an acceptance target by A9 tests #3 and #4**, whose expected values are published rather
than observed; retained because its 40 dB step is a blunter, easier-to-debug first signal.

## B7. Floor behaviour — measured, and it is a clamp

| fixture | summary | `lavfi.r128.I` | `Threshold:` |
| --- | --- | --- | --- |
| 5 s digital silence, stereo | −70.0 LUFS | **−70.000** | **0.0 LUFS** |
| 300 ms of 1 kHz sine | −70.0 LUFS | **−70.000** | **0.0 LUFS** |
| **399 ms** of 1 kHz sine | −70.0 LUFS | −70.000 | **0.0 LUFS** |
| **400 ms** of 1 kHz sine | **−20.0 LUFS** | **−20.000** | −30.0 LUFS |
| 500 ms of 1 kHz sine | −20.0 LUFS | — | −30.0 LUFS |

Three findings:

1. **−70.000 at full precision is a clamp, not a computation.** It is FFmpeg's initial/floor value. A7
   shows the normative quantity is *undefined* in both of these cases. **The project must not publish
   −70.0 as a measurement**, and this table is the evidence that doing so would be copying a display
   convention.
2. **`Threshold: 0.0 LUFS` is the tell.** The oracle reports a nonsensical relative gate exactly when no
   gating happened — i.e. when no block existed or none survived. It is a reliable discriminator for test
   code parsing the oracle's output, and it is *not* documented behaviour, so it should be asserted rather
   than assumed.
3. **The 400 ms boundary is exact and inclusive.** 399 ms yields nothing; 400 ms yields a full
   measurement. **This is precisely what A5's index set predicts** — ⌊(*T*−*T<sub>g</sub>*)/(*T<sub>g</sub>*·step)⌋
   is 0 at *T* = *T<sub>g</sub>* and negative below it. Norm and oracle agree at the boundary sample.

## B8. Cost — measured

Over **10 minutes of stereo, Release**, on the same 4 096-frame chunking the pipeline already uses.
Coefficient *values* were placeholders in this measurement; cost does not depend on them.

| stage | cost |
| --- | --- |
| two cascaded biquads per channel (`vDSP_biquad`, Float) | **0.117 s** |
| square-and-accumulate per channel (widened to `Double`) | **0.028 s** |
| **total fold** | **≈ 0.14 s** |

For comparison, measured on this machine during `share-waveform-pcm-read`: the waveform's fold costs
**0.30 s** and the whole shared pass **1.20 s (WAV) / 1.79 s (FLAC) / 1.96 s (AAC)**.

**Loudness as a fifth consumer costs roughly half of what the waveform costs, about 7–12 % of the pass it
would join**, and opens no second read. Block bookkeeping and the gating passes are still unmeasured; A6
and B9 now bound what they can cost, and it is per-block rather than per-sample.

## B9. Streaming state — what A6 actually requires

Derived from Part A, not measured, and stated here because it is the bridge from methodology to design.

**Per-sample state** is small and bounded:

- **filter state**: two biquad sections × 2 delay elements × `channelCount`;
- **sub-block accumulation**: A5's 75 % overlap means every 400 ms block is exactly **four consecutive
  100 ms sub-blocks**. Accumulating energy per 100 ms sub-block and summing the last four gives each
  block's energy **without buffering a single sample** — a ring of 4 sub-block sums plus one partial sum,
  per channel;
- **hop position**: one frame counter, absolute across chunks.

**Per-block state is not bounded, and cannot be.** A6's relative gate is computed from the whole
programme, so whether a given block survives eq. (7) **cannot be decided when that block is produced**.
An exact single-pass, O(1)-memory integrated loudness is therefore **impossible in principle**, not merely
awkward.

Against the four candidate strategies:

| | strategy | verdict |
| --- | --- | --- |
| **A** | keep one energy per block, gate in two passes over that array | **Chosen.** Exact, reproducible, trivially auditable |
| B | histogram / binning of block loudnesses | Rejected: buys memory we do not need at the cost of a quantisation error inside a ±0.1 LUFS budget |
| C | two logical passes over stored block metadata | Identical to A; that is what A is |
| D | an equivalent streaming algorithm | Does not exist for the exact result — see above |

**Memory for A**: one hop is 100 ms, so **10 blocks per second** — ≈ 36 000 blocks per hour, ≈ **288 kB
per hour** as `Double`, ≈ 864 kB for a three-hour file. This satisfies the standing requirement that
memory be a function of the **block count, never of the sample count**, and it makes premature
optimisation unnecessary.

One consequence worth stating: because *J<sub>g</sub>* ⊆ *J<sub>a</sub>* is not guaranteed by
construction, and because the loudest block always exceeds a mean-derived threshold minus 10 LU, the
second emptiness guard in A6 is unreachable in practice. **It should still be written**, because its
unreachability is an argument, not a proof carried by the code.

---

# Part C — What this evidence forces

1. **The blocking unknown is resolved.** Every constant integrated loudness needs is published, sourced
   and recorded in Part A. Nothing remains to be remembered.
2. **The compliance claim is now precisely bounded, and it is narrower than "BS.1770-compliant".** It is
   exact at 48 kHz and a demonstrated-equivalent derivation everywhere else (A3). That distinction is the
   ADR's job to carry.
3. **Mono and stereo only, and three channels is the proof** (A11). Not a caution — a counterexample.
4. **Silence and too-short are both undefined, and neither is −70** (A7, B7). The outcome is the same for
   two different reasons, and the reasons are worth keeping even though the report shows one absence.
5. **The acceptance targets are now published values, not observed ones** (A9). The first session's
   fixtures are demoted to corroboration.
6. **The oracle is qualified** (B2), which is what makes a cross-check meaningful — and it is absent from
   CI, which is what makes the skip message matter.
7. **Exact O(1) is impossible; O(blocks) is cheap** (B9). The design does not need to be clever here.
