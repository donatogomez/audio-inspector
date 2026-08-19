# Spike — significant bandwidth methodology (group 1)

Working notes for `add-significant-bandwidth-measurement` group 1. The first session settled only that
the threshold must be **relative**; this one settles **which relative reference**, **at what value**,
**with what persistence criterion**, and — the answer that was not anticipated — that those two
parameters are **not sufficient on their own**.

Nothing here touched production. The harness was a standalone `swiftc -O` executable outside the repo,
deleted at the end.

## 1. Method, and why the previous attempt was too expensive to finish

The decisive experiment is a sweep over (reference × threshold × persistence) on fixtures whose correct
answer is known. The first attempt did not finish because it re-derived the spectrum inside the sweep.

The rewrite separates the two costs completely:

1. per fixture, synthesise once and take **one STFT** → magnitudes in dB, `[window][bin]`;
2. reduce that to a **compact per-bin persistence-quantile table**
   `Q[p][bin]` = the level that `bin` holds in at least a fraction `p` of windows, built by sorting each
   bin's column of window levels **once** and reading order statistic `k − 1`, `k = ceil(p · N)`;
3. the whole sweep is then a scalar comparison against `Q`. No transform is ever repeated.

Two further reductions fall out of the shape of the problem: the three *global* references are constants
over windows, so subtracting them does not change a sort order and **one sort serves all three**; and
every synthetic frequency used is a multiple of 50 Hz, so the tone combs are exactly periodic over
`rate / 50` samples and synthesis is one period tiled.

Measured effect, on 46 fixtures of 20 s at 48 kHz, FFT 4096, hop 1024 (934 windows, 2049 bins):

| stage | cost |
| --- | --- |
| signal synthesis, all 46 fixtures | **0.06 s** |
| STFT + representation, all 46 fixtures | 10.9 s |
| **sweep of 1 287 combinations × 46 fixtures** | **0.032 s** |
| whole run, wall clock / peak RSS | 11.3 s / 102 MB |
| representation retained per fixture | 704 KB (176 KB with a single window gate) |

The parameter search is now `O(FFT of fixtures) + O(fixtures × thresholds × persistences × bins)`, as
intended. The full investigation — five passes, including 192 kHz and three FFT sizes — is under a
minute in Release.

## 2. Fixtures

All deterministic, mono, 20 s, synthesised in memory. A "body" is a tone comb on a 500 Hz grid at
0.02 amplitude (−40 dBFS per bin); a "high band" is 19/19.5/20 kHz at a stated level **relative to the
body's per-tone amplitude**, present for a stated fraction of the file as periodic bursts with
raised-cosine edges (so gating adds no splatter of its own).

- **R1–R8** — what the references do when the body's energy moves: stable; 20 dB dynamics; body silent
  50 %; a full-scale 100 Hz event over 2 %; a loud full-band burst over 2 %; 40 % digital silence; a
  full-scale low end present throughout; 40 % digital silence *with* a real high band.
- **G0/G20/G40** — the same signal at three gains (regression gate for invariance).
- **A1/A2** — hard cut-offs at 16 and 20 kHz.
- **B1–B6** — high band always present at −20/−30/−40/−50/−60/−70 dB.
- **C1–C8** — high band at −30 dB present 1/2/5/10/25/50/75/100 % of the file.
- **D1–D8** — one click; five clicks; full-band bursts of 10/50/100 ms; periodic full-band bursts
  totalling 1/5/10 %.
- **E1–E5** — continuous noise **only** above 16 kHz at −40/−50/−60/−70/−80 dB.
- **F1–F5** — adversarial: −40 dB persistent; −20 dB at 1 %; −30 dB at 5 %; −50 dB at 75 %; a click
  together with a real −40 dB persistent band.
- **S1** — digital silence.
- **roll-off series** — graded slopes of 6/12/24/48/96/192/480 dB per octave above an 8 kHz and a
  16 kHz knee (task 1.1's literal deliverable; §8).

### 2.1 The measurement that reframes persistence

A burst shorter than the analysis window still marks `fftSize / hop` windows. Time-domain duty cycle and
**window** presence are therefore different numbers, and the criterion is defined on the second:

| fixture | duty cycle | measured window presence |
| --- | --- | --- |
| C1 / C2 / C3 / C4 | 1 / 2 / 5 / 10 % | **1.7 / 2.8 / 5.8 / 10.8 %** |
| C5 / C6 / C7 / C8 | 25 / 50 / 75 / 100 % | 25.8 / 51.0 / 76.1 / 100 % |
| D1 one click | one sample | **0.4 %** |
| D2 five clicks | five samples | 2.1 % |
| D3 / D4 / D5 bursts | 10 / 50 / 100 ms | 0.1 / 0.3 / 0.5 % |
| D6 / D7 / D8 bursts | 1 / 5 / 10 % | **4.3 / 8.0 / 13.2 %** |
| F2 high band, loud, rare | 1 % | 1.9 % |

Every threshold and persistence result below is stated against the **measured** column.

## 3. The reference — four candidates, then a fifth the task named

Gain invariance was re-run only as a regression gate; it separates nothing, because all four relative
candidates are relative (recorded in the previous session and unchanged).

### 3.1 Global spectral peak — rejected, P7

A full-scale 100 Hz event occupying **2 %** of the file raises the file's peak bin from −40.0 to
−7.3 dBFS, and a real high band present *throughout* then falls below any usable threshold.

| fixture | expected | global peak | per-window peak |
| --- | --- | --- | --- |
| R4 loud LF event 2 % + high band −30 dB, always present | 20 000 | **16 008** | 20 016 |

Rejected: a reference computed once over the whole file is hostage to its single loudest instant.

### 3.2 Global spectral RMS and a robust 95th percentile — rejected, they are not levels

Both are statistics over the **bin population**, so they move when the number of empty bins moves. The
same signal, same content, three FFT sizes:

| reference | FFT 2048 | FFT 4096 | FFT 8192 | drift |
| --- | --- | --- | --- | --- |
| global spectral peak (A1) | −40.0 | −40.0 | −40.0 | **0.0 dB** |
| global spectral RMS (A1) | −53.3 | −56.3 | −59.3 | 6.0 dB (3 dB per doubling) |
| robust p95 over all bins (A1) | −42.6 | −60.6 | **−84.4** | **41.8 dB** |

The p95 figure is the clearest: 95 % of the bins of a sparse spectrum are *empty*, so the "robust
reference" tracks the leakage floor and not the signal. Across fixtures at one FFT size it ranges from
−44.0 to −75.9 dBFS for content whose loudest bin is always −40.0 dBFS. A threshold relative to either
is not a fixed sensitivity. Both rejected.

### 3.3 Gated loudness (BS.1770-5) — rejected, not commensurable

Task 1.2 names it, so it was measured rather than argued away: the published 48 kHz K-weighting tables,
400 ms blocks at 75 % overlap, absolute gate −70 LUFS, relative gate −10 LU.

It is resolution-stable, and it **does** pass all eight pre-registered constraints (48 combinations).
It is rejected on what the numbers underneath show: the offset between the reference and the quantity
being thresholded — a *per-bin* magnitude — is not a constant.

| fixture | global peak dBFS | LUFS | LUFS − peak |
| --- | --- | --- | --- |
| R1 body + high band | −40.0 | −18.9 | **+21.1** |
| A2 body to 20 kHz | −40.0 | −17.8 | +22.2 |
| R5 loud burst 2 % | −30.8 | −17.6 | +13.2 |
| R7 loud low end throughout | −11.7 | −8.8 | +2.9 |
| R4 loud LF event 2 % | −7.3 | −17.7 | **−10.4** |

**Spread 32.6 dB.** A broadband gated energy and a single bin's magnitude are different quantities, and
the distance between them is a property of the file's crest factor and spectral density, not of the
method. The same constant would mean a 31 dB different sensitivity on R1 and R4. It would also couple
significant bandwidth to the loudness gate and, at rates other than 48 kHz, to this project's own
derivation of the weighting.

### 3.4 Per-window spectral peak — chosen

It is a **level**, so it is resolution-stable (−40.0 dBFS at every FFT size), and it is the *same kind of
quantity* as the bin being compared to it, so the offset is zero by construction. It survives P1–P7 over
a wide region — and fails P8, which is the subject of §6.

## 4. The threshold — −50 dB relative to the loudest bin in the same window

Reading of the highest qualifying bin at persistence ≥ 10 %, per threshold (Hz):

| fixture | −30 | −35 | −40 | −45 | −50 | −55 | −60 | −65 | −70 | −80 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B1 high band −20 dB | 20 004 | 20 016 | 20 016 | 20 016 | 20 016 | 20 027 | 20 027 | 20 039 | 20 051 | 20 074 |
| B2 −30 dB (**must count**) | 19 500 | **20 004** | 20 004 | 20 016 | 20 016 | 20 016 | 20 016 | 20 027 | 20 027 | 20 051 |
| B3 −40 dB | 16 020 | 16 020 | 16 031 | **20 004** | 20 004 | 20 016 | 20 016 | 20 016 | 20 016 | 20 027 |
| B4 −50 dB | 16 020 | 16 020 | 16 031 | 16 043 | **19 500** | 20 004 | 20 004 | 20 016 | 20 016 | 20 016 |
| B5 −60 dB | 16 020 | 16 020 | 16 031 | 16 043 | 16 043 | 16 055 | **19 500** | 20 004 | 20 004 | 20 016 |
| B6 −70 dB (**should not**) | 16 020 | 16 020 | 16 031 | 16 043 | 16 043 | 16 055 | 16 066 | 16 090 | **19 500** | 20 004 |
| E3 noise −60 dB | 16 020 | 16 020 | 16 031 | 16 043 | 16 055 | 16 055 | **23 250** | 23 953 | 23 953 | 23 965 |
| E4 noise −70 dB | 16 020 | 16 020 | 16 031 | 16 043 | 16 043 | 16 055 | 16 066 | 16 102 | **23 250** | 23 953 |
| E5 noise −80 dB (**must not**) | 16 020 | 16 020 | 16 031 | 16 043 | 16 043 | 16 055 | 16 066 | 16 090 | 16 113 | **23 250** |

The single most important thing in this table is that the **B and E rows behave identically**. A weak
band and a low noise floor at the same level relative to the window peak are the same thing spectrally,
and no threshold separates them. **The threshold is a sensitivity, not a discriminator.** Choosing it
means choosing how far below the loudest component in the same window content still counts.

The constraints bracket it: keeping B2 needs `≤ −35`; rejecting E5 needs `≥ −75`; rejecting B6 and E4
needs `≥ −65`; keeping B3 needs `≤ −45`. **The admissible region is [−65, −45].**

**Chosen: −50 dB.** It is round, it sits mid-region, and it carries 20 dB of margin above the loudest
"must not count" fixture and 20 dB below the "must count" one. No finer sweep was run: the fixtures do
not justify a decimal, and the transition itself is about 5 dB wide (B4 at exactly −50 is *partially*
detected — 19 500 rather than 20 016).

**Quiet-but-persistent floor (task 1.4), stated as measured**, at threshold −50 dB:

- a persistent band at **−45 dB or above** relative to the loudest bin in the same window is reported in
  full;
- at **−50 dB** it is at the transition and reported partially;
- at **−55 dB or below** it is not reported.

## 5. The persistence criterion — ≥ 10 % of eligible windows

Reading at threshold −50 dB, per persistence (Hz), against the measured window presence of §2.1:

| fixture | wPres | any | 1 % | 2 % | 5 % | 7.5 % | **10 %** | 15 % | 25 % | 50 % | 75 % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D1 one click | 0.4 % | **24 000** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |
| D2 five clicks | 2.1 % | 24 000 | **24 000** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |
| D6 bursts 1 % | 4.3 % | 24 000 | 24 000 | **24 000** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |
| D7 bursts 5 % | 8.0 % | 24 000 | 24 000 | 24 000 | 24 000 | **24 000** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |
| D8 bursts 10 % | 13.2 % | 24 000 | 24 000 | 24 000 | 24 000 | 24 000 | **24 000** | 16 043 | 16 043 | 16 043 | 16 043 |
| C1 high band 1 % | 1.7 % | 20 027 | **20 027** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |
| C3 high band 5 % | 5.8 % | 20 027 | 20 016 | 20 016 | 20 016 | **16 043** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |
| C4 high band 10 % | 10.8 % | 20 027 | 20 027 | 20 016 | 20 016 | 20 016 | **20 016** | 16 043 | 16 043 | 16 043 | 16 043 |
| C7 high band 75 % | 76.1 % | 20 027 | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 |
| F2 −20 dB at 1 % | 1.9 % | 20 109 | **20 074** | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 | 16 043 |

The criterion flips exactly at `wPres ≥ p`, on every row. The constraints bracket it: rejecting D6
(4.3 %) needs `≥ 5 %`; keeping C7 (76.1 %) needs `≤ 75 %`.

**Chosen: ≥ 10 %.** 5 % clears D6 by only 0.7 points and admits D7; 7.5 % clears D7 by 0.5 points. 10 %
is the smallest value clearing both D6 and D7 with real margin (5.7 and 2.0 points) while still keeping
a band genuinely present in a tenth of the file.

D8 (13.2 %) is kept, and that is accepted rather than tuned away: full-band content present in a tenth
of the windows is not distinguishable from a high band present in a tenth of the windows, because they
are the same measurement. Persistence sets where "occasional" ends; it does not read intent.

### 5.1 Percentile equivalence, stated exactly

"Present in at least a fraction `p` of eligible windows at a level ≥ `T`" is equivalent to
`Q_p ≥ T`, where `Q_p` is the **`k`-th largest** of that bin's per-window relative levels and
`k = ceil(p · N)`, `N` the number of eligible windows.

For `p = 0.10` this is a 90th percentile under the **nearest-rank-from-the-top** convention. It is
**not** a linearly interpolated p90, and it is **not** p95. The two languages agree only under that
definition and that inequality, which is why the criterion is written as a window fraction and the
percentile named as its restatement rather than the other way round.

## 6. Threshold + persistence are **not** sufficient — classification **B**

**No combination of any of the four references with any threshold and any persistence passes all eight
pre-registered constraints.** Every one of them fails **P8**: on digital silence every bin sits at the
numerical floor and so does every relative reference, so the ratio is 0 dB everywhere and the answer is
Nyquist. A relative method cannot, by construction, recognise the absence of a signal.

The same shape appears in a milder and more realistic form. With a per-window reference, a window that
is digitally silent has *its own* peak at the floor, so every bin in it qualifies:

| fixture | expected | window peak, no extra rule | with the rule below |
| --- | --- | --- | --- |
| R6 body 60 % of the file, digital silence 40 % | 16 000 | **24 000** | 16 043 |
| S1 digital silence | absence | **24 000** | **absence** |

Two small rules fix both, and they are separable and separately justified:

1. **Window eligibility gate.** A window whose own spectral peak is more than **60 dB** below the file's
   global spectral peak contributes to neither the count nor the denominator. This is a ratio of two
   levels in the same file, so it is **gain-invariant by construction**. Measured: it removes 361 of
   R6's 934 windows and **is inert everywhere else** — all 934 windows remain eligible in every other
   fixture, including R3, where the body is silent half the time but a real high band keeps those windows
   above the gate. The fixtures do **not** discriminate between −40, −60 and −80 dB (572 / 573 / 574
   windows kept); −60 dB is chosen for margin and to match the threshold's own scale.
2. **Absolute silence floor.** If the file's global spectral peak is below **−120 dBFS**, report absence.
   This one is *not* gain-invariant and is not meant to be: it detects the absence of audio, it does not
   measure bandwidth.

Measured cost of the floor, which is the honest statement of P1's range:

| gain applied | global spectral peak | reading |
| --- | --- | --- |
| 0 / −20 / −40 / −60 / −80 dB | −40.0 → −120.0 dBFS | **20 016 Hz, identical** |
| −100 dB | −140.0 dBFS | absence |
| −120 dB | −160.0 dBFS | absence |

**Gain invariance holds over an 80 dB range, while the file's global spectral peak stays above
−120 dBFS.** Below that the method reports absence rather than a number.

With both rules, **all eight constraints pass**, over thresholds −35…−75 and persistences 5…75 %.

## 7. Resolution and rate (task 1.5 — evidence, not yet a decision)

The candidate's *decision* is stable across three FFT sizes and two rates:

| fixture | 48k/2048 | 48k/4096 | 48k/8192 | 192k/2048 | 192k/4096 | 192k/8192 |
| --- | --- | --- | --- | --- | --- | --- |
| A1 body to 16 kHz | 16 102 | 16 043 | 16 025 | 16 406 | 16 172 | 16 102 |
| A2 body to 20 kHz | 20 086 | 20 051 | 20 021 | 20 344 | 20 203 | 20 086 |
| B2 −30 dB persistent | 20 016 | 20 016 | 20 004 | 20 062 | 20 062 | 20 016 |
| D1 one click | 16 102 | 16 043 | 16 025 | 16 406 | 16 172 | 16 102 |
| E5 noise −80 dB | 16 102 | 16 043 | 16 025 | 16 406 | 16 172 | 16 102 |
| S1 digital silence | absence | absence | absence | absence | absence | absence |

Two things this shows, and one it warns about.

- **The overshoot above a known hard cut-off is ≈ 4 bins, at every rate and size.** A1 reads +102 Hz at
  23.44 Hz/bin, +43 Hz at 11.72, +25 Hz at 5.86, +406 Hz at 93.75 — that is 4.35, 3.7, 4.3, 4.3 bins.
  This is the Hann skirt reaching −50 dB, and it is the real uncertainty: **not half a bin, about four**,
  and one-sided upward. Task 1.5 stays open because it must also decide bin centre / edge / range and
  pair this with the analytic main-lobe figure, but the empirical number is now measured.
- **The persistence constant is tied to the analysis window.** D7 (bursts totalling 5 %) reads 16 043 at
  FFT 4096 and **24 000 at FFT 8192**, because a longer window smears each burst over a larger fraction
  of a smaller number of windows. `10 %` is only meaningful together with a fixed `fftSize` and `hop`,
  which the method identity must therefore carry (task 4.2). Whether the window should be fixed in
  *time* rather than in samples, so the criterion means the same thing at every rate, is an open
  question for group 3.
- E3 at 192k/2048 reads 19 781 rather than 16 219; that is a **fixture artefact**, not a method result —
  the noise comb is spaced 50 Hz and the bin is 93.75 Hz wide, so several comb tones land in one bin and
  lift it. Recorded so it is not mistaken for a finding.

## 8. Graded roll-off (task 1.1) — the threshold means what it is claimed to mean

Predicted edge for a slope `S` above a knee: `f = knee · 2^(−T / S)` with `T = −50 dB`.

| knee | slope dB/oct | predicted | measured | agreement |
| --- | --- | --- | --- | --- |
| 8 kHz | 6 / 12 / 24 | > Nyquist | 23 531 / 23 520 / 23 508 | no edge exists below Nyquist |
| 8 kHz | 48 | 16 469 | 15 996 | last 500 Hz comb tone ≤ 16 469 is 16 000 ✔ |
| 8 kHz | 96 | 11 478 | 11 004 | ≤ 11 478 → 11 000 ✔ |
| 8 kHz | 192 | 9 583 | 9 504 | ≤ 9 583 → 9 500 ✔ |
| 8 kHz | 480 | 8 599 | 8 508 | ≤ 8 599 → 8 500 ✔ |
| 16 kHz | 6 / 12 / 24 / 48 | > Nyquist | 23 520–23 543 | no edge exists below Nyquist |
| 16 kHz | 96 | 22 957 | 22 500 | ✔ |
| 16 kHz | 192 | 19 165 | 18 996 | ✔ |
| 16 kHz | 480 | 17 198 | 17 004 | ✔ |
| — | brick wall at 16 kHz | 16 000 | 16 043 | +3.7 bins, §7 |

Every measurement lands on the highest comb tone at or below the analytic prediction — exact agreement
once the 500 Hz comb spacing is accounted for. That is the strongest available check that the threshold
constant has the meaning claimed for it.

**The consequence matters more than the agreement.** At 48 kHz with a 16 kHz knee, a roll-off gentler
than roughly 85 dB/octave has **no edge below Nyquist at all**, and the measurement correctly reports the
top of the band. Significant bandwidth is therefore **not a filter-knee detector**: it reports where
content stops crossing the threshold, which for gently filtered material is not the filter's corner.

## 9. Negative controls

| control | fixtures it breaks | first failure |
| --- | --- | --- |
| temporal max (persistence "any") | 13 | one click → 24 000 |
| absolute dBFS threshold (−90 dBFS) | 2 | the same file at −20 dB → 19 500, at −40 dB → 16 008 |
| threshold far too low (−80 dB) | 3 | −70 dB band → 20 004; −80 dB noise → 23 250 |
| threshold far too high (−20 dB) | 12 | real −30 dB band lost; R7 collapses to **117 Hz** |
| persistence 1 % | 8 | five clicks → 24 000; bursts totalling 1 % → 24 000 |
| persistence 50 % | 1 | R7 only (§10) |
| **no window gate, no floor** | 3 | R6 → 24 000; silence → 24 000 |
| **global peak reference** | 3 | R4 → 16 008; silence → 24 000 |
| **the chosen combination** | **0** | — |

## 10. Where the chosen method fails, stated rather than tuned away

- **R7 — a loud low end present throughout.** A full-scale 100 Hz tone puts the window peak at
  −11.7 dBFS; a real, always-present high band 30 dB below the body sits 59.5 dB under it and is lost at
  −50 dB. Recovering it needs −60 dB, which is exactly the level at which E3's −60 dB noise starts
  defining the bandwidth. **The two are indistinguishable by level**, so this is a limit of any
  peak-relative threshold, not a tuning failure. A bass-dominated file under-reports.
- **D8 — full-band content in 10 % of windows** is kept, by the same argument as §5.
- **Gentle roll-offs** report the top of the band, not the knee (§8).
- **Nothing was measured on real music**, on any codec, or through the production decode path. All of
  §2's material is synthetic.

## 11. Constants, with their source

| constant | value | source |
| --- | --- | --- |
| threshold reference | per-window spectral peak | §3 — the only candidate that is a level, is resolution-stable, and survives P7 |
| threshold | **−50 dB** relative to that peak | §4 — admissible region [−65, −45] bracketed by B2/B3/B6/E4/E5; midpoint, 20 dB margin each way |
| persistence | **≥ 10 %** of eligible windows | §5 — smallest value clearing D6 (4.3 %) and D7 (8.0 %) with margin while keeping C4 (10.8 %) |
| percentile restatement | k-th largest, `k = ceil(0.10 · N)` | §5.1 — nearest-rank from the top; not interpolated p90, not p95 |
| window eligibility gate | **−60 dB** below the file's global spectral peak | §6 — fixtures do not discriminate −40/−60/−80; chosen for margin. Gain-invariant |
| absolute silence floor | **−120 dBFS** global spectral peak | §6 — gain invariance measured to hold over 80 dB above it |
| measured overshoot | **≈ 4 bins**, one-sided upward | §7 — 3.7–4.35 bins at four different bin widths |
| analysis window | FFT 4096 / hop 1024 at 48 kHz | §7 — the persistence constant is not portable across window lengths |

## 12. Part B — resolution, the analysis window, and four refutation attempts

Part A settled four parameters. Part B derives the uncertainty analytically instead of empirically,
decides the analysis window, and then tries to **break** each parameter on fixtures that did not choose
it. Two of the four did not survive.

### 12.1 The Hann window, derived and then verified

A Hann window is a rectangular window minus two half-amplitude copies shifted by one bin, so its
transform is a weighted sum of three Dirichlet kernels. Because `sin(π(d ± 1)) = −sin(πd)`, the three
collapse into one expression:

> **|W(d)| / W(0) = |sin(πd)| / (π · |d| · |d² − 1|)**, with `d` in bins.

Checked against the true sampled DTFT of the window at N = 2048: **agreement to 0.000 dB at every point
tested**, from d = 0 to d = 10.5. Every figure below is measured from the window in the run, not quoted:

| quantity | measured | canonical |
| --- | --- | --- |
| coherent gain | 0.5000 | 0.5 |
| equivalent noise bandwidth | 1.5000 bins | 1.5 |
| first zero | 2.0000 bins → main lobe **4 bins** null-to-null | 2 |
| −3 dB bandwidth | 1.438 bins | 1.44 |
| scalloping loss at d = 0.5 | **−1.424 dB** | 1.42 |
| first sidelobe | **−31.47 dB** at d = 2.362 | −31.5 |
| asymptotic roll-off | **−18.6 dB/octave** | −18 |

(the canonical column is Harris 1978, *On the Use of Windows for Harmonic Analysis with the DFT*,
Proc. IEEE 66(1), table 1; it is there to confirm the harness, not to supply the numbers.)

Accelerate's own window was checked too: `vDSP_HANN_DENORM` **is** the periodic
`0.5(1 − cos(2πn/N))`, and `vDSP_HANN_NORM` is that scaled by `2/Σw`. Neither is the symmetric
`/(N−1)` variant.

### 12.2 What actually explains the ≈4-bin overshoot — and it is none of the obvious three

Four different quantities were being called "resolution". They are not the same thing:

| | quantity | value at 48 kHz / 2048 | depends on the threshold? |
| --- | --- | --- | --- |
| **A** | nominal FFT resolution `rate / fftSize` | 23.4 Hz | no |
| **B** | Hann main-lobe width | 4 bins = 94 Hz | no |
| **C** | bin quantisation of the reported index | ±0.5 bin = ±12 Hz | no |
| **D** | **threshold cutting the leakage skirt** | **4.72 bins = 111 Hz** | **yes** |

Only **D** behaves like the observation. Far from the main lobe the envelope goes as `1/(πd³)`, so
solving `|W(d)| = 10^(T/20)` gives a closed form:

> **d(T) ≈ ( 1 / (π · 10^(T/20)) )^(1/3) bins**

| threshold | −40 | −45 | **−50** | −55 | −60 | −70 | −80 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| d(T), bins | 3.27 | 3.93 | **4.72** | 5.69 | 6.88 | 10.06 | 14.73 |

The measured overshoot follows it exactly, and depends **only on where the content edge sits inside a
bin** — not on the rate and not on the FFT size:

| sub-bin offset of the edge | 0.00 | 0.25 | 0.50 | 0.75 |
| --- | --- | --- | --- | --- |
| overshoot, bins | **1.00** | 3.75 | **4.50** | 4.25 |

identical at 44.1 / 48 / 88.2 / 96 / 192 kHz and at FFT 2048 / 4096 / 8192. An edge exactly on a bin
leaks into ±1 bin and no further, because the sampled Hann transform is then exactly `{¼, ½, ¼}`; an
edge between bins leaks out to d(T). **So the uncertainty is one-sided, upward, and content-dependent.**

### 12.3 The interval contract, derived and then falsified

The natural contract was: `trueEdge ∈ [(b − d(T))·Δf, (b + 0.5)·Δf]`. It held on 105 of 105 isolated and
sparse cases — and then failed. Tones spaced **one bin apart and in phase** put the reading **8.50 bins**
above the true edge, because the skirts of many partials add in amplitude:

| content | worst overshoot |
| --- | --- |
| isolated tone / sparse comb (42.7 bins apart) | 4.50 bins — inside d(T) |
| comb 4 bins apart | 4.50 bins |
| comb 2 bins apart, in phase | 5.50 bins — **outside** |
| comb 1 bin apart, in phase | **8.50 bins — outside** |
| band-limited noise, random phases (the realistic dense case) | 2.76–3.50 bins |
| white noise through a real FIR brick wall | 2.33–4.33 bins |

**The interval contract (option C) is rejected on this evidence.** A derived bound that a legal signal
violates is not a bound. Coherent dense content is contrived, but it is a signal, and the contract
claimed to hold for all of them.

### 12.4 The reporting contract — frequency and resolution, with the bias stated

| contract | verdict |
| --- | --- |
| **A — bin centre + the resolution it was measured at** | **chosen.** The number is exactly what was measured; the resolution says how finely it is quantised. It claims nothing about the content's cut-off, which §8 already established it must not. |
| B — bin upper edge | rejected: adds half a bin of overstatement to a number that already overstates, and buys nothing. |
| C — lower/upper bound | rejected: the bound is falsifiable and was falsified (§12.3). |
| D — band index plus a mapping | rejected: moves DSP into the surface, which ADR-0016 already refused for the spectrogram. |

The bias is not hidden by choosing A; it is **stated**: the reported frequency is an upper bound on the
edge of the content, overstating it by one bin when the edge falls on a bin and by up to d(T) bins when
it does not. In Hz that is `bins / windowDuration`, so it is one number per window length and — once the
window is time-locked — the same at every sample rate:

| window | bin width @48 kHz | bias, 1 … d(T) | worst observed | honest display step |
| --- | --- | --- | --- | --- |
| 21.33 ms | 46.9 Hz | 47 … 221 Hz | 398 Hz | 0.5 kHz |
| **42.67 ms** | **23.4 Hz** | **23 … 111 Hz** | 199 Hz | 0.1–0.5 kHz |
| 85.33 ms | 11.7 Hz | 12 … 55 Hz | 100 Hz | 0.1 kHz |

### 12.5 The analysis window — time-locked, on evidence

**vDSP accepts far more than powers of two.** Probed, not assumed: `f · 2^m` for f in {1, 3, 5, 15} is
available through `vDSP_DFT_zrop`, giving 1920, 3840, 7680 and so on alongside the usual sizes. That is
what makes a time-locked window possible at 44.1 and 88.2 kHz without a large duration error.

| rate | sample-locked 2048 | time-locked ≈42.67 ms | time-locked, powers of two only |
| --- | --- | --- | --- |
| 44.1 kHz | 46.44 ms | **1920 → 43.54 ms (+2.0 %)** | 2048 → 46.44 ms (+8.8 %) |
| 48 kHz | 42.67 ms | 2048 → 42.67 ms (0 %) | 2048 (0 %) |
| 88.2 kHz | **23.22 ms (−45.6 %)** | **3840 → 43.54 ms (+2.0 %)** | 4096 → 46.44 ms (+8.8 %) |
| 96 kHz | **21.33 ms (−50 %)** | 4096 → 42.67 ms (0 %) | 4096 (0 %) |
| 192 kHz | **10.67 ms (−75 %)** | 8192 → 42.67 ms (0 %) | 8192 (0 %) |

**A single contiguous event does not discriminate the two families.** The shortest event still classified
significant, found by bisection on a 5 s file, is 500.0–502.6 ms sample-locked and 500.9–502.6 ms
time-locked — a spread of 0.5 % and 0.3 %. When the event is much longer than the window, the window
does not matter.

**Fragmented content discriminates them decisively.** Ten short bursts totalling a stated fraction of the
file, measured window presence:

| content | 44.1 k | 48 k | 88.2 k | 96 k | 192 k | same verdict? |
| --- | --- | --- | --- | --- | --- | --- |
| 1 % duty, sample-locked | 8.67 % | 7.53 % | 4.66 % | 4.18 % | **2.72 %** | 3.2× spread |
| 1 % duty, **time-locked** | 7.89 % | 7.53 % | 7.68 % | 7.53 % | 7.74 % | yes |
| **5 % duty, sample-locked** | **12.65 %** | **11.61 %** | **8.74 %** | **8.24 %** | **6.73 %** | **NO — significant at 44.1 and 48 kHz, not significant above** |
| 5 % duty, **time-locked** | 11.84 % | 11.61 % | 11.62 % | 11.61 % | 11.61 % | yes |
| 10 % duty, sample-locked | 17.80 % | 16.56 % | 13.75 % | 13.17 % | 11.65 % | yes, but 1.5× margin spread |
| 10 % duty, **time-locked** | 17.11 % | 16.56 % | 16.89 % | 16.77 % | 16.56 % | yes |

The 5 % row is the answer to the question the turn was set: **the same temporal evidence receives a
different classification at different sample rates under a sample-locked window, and the same
classification under a time-locked one.** Time-locked, on evidence.

### 12.6 What "≥ 10 % of windows" means in time

`windowPresence ≈ (totalEventTime + n · α · windowDuration) / fileDuration`, with `n` the number of
separate fragments and α between 0.5 and 1 depending on how far above threshold the event sits.

- **one contiguous event**: the criterion is "present for ≥ 10 % of the file", accurate to one window
  length — measured critical duration 502 ms against a nominal 500 ms on a 5 s file.
- **n fragments**: each fragment costs about one extra window length. Ten bursts totalling 1 % of a 5 s
  file measure 7.5 %, not 1 %.

So "10 % of the time" and "10 % of windows" are different quantities, and the difference is the window
duration times the number of fragments. This is a property of the definition and is stated, not fixed.

### 12.7 Hop

| overlap | hop @48 kHz | windows / 5 s | critical duration | a transient marks | STFT cost |
| --- | --- | --- | --- | --- | --- |
| 25 % | 42.67 ms | 117 | **480.8 ms** | 1 window (0.85 %) | 0.7 ms |
| 50 % | 21.33 ms | 233 | 502.6 ms | 1 window (0.43 %) | 1.3 ms |
| **75 %** | **10.67 ms** | 465 | **502.6 ms** | 1 window (**0.22 %**) | 3.0 ms |
| 87.5 % | 5.33 ms | 930 | 502.6 ms | 1 window (0.11 %) | 4.6 ms |

Two things worth correcting from part A. A short transient marks **one** window, not `fftSize / hop` of
them — the Hann taper attenuates a transient sitting near a window's edge below the threshold. And
because the transient's window *count* stays at one while the window total grows, **more overlap makes a
transient less significant, not more**. 25 % overlap disagrees with the rest on the critical duration;
50, 75 and 87.5 % agree. **75 % chosen**: it agrees with the consensus, rejects transients better than
50 %, and costs a third of what 87.5 % costs.

**Adversarial alignment** — the same signal shifted by 0, ¼, ½ and ¾ of a hop, time-locked, all five
rates: a 520 ms event reads 10.31–10.54 % and is classified significant in **20 of 20** cases; a 10 ms
burst reads 0.00–0.44 % and is classified insignificant in **20 of 20**. Alignment is not a risk.

### 12.8 Refutation 1 — the −50 dB threshold survives

Nine fixtures that had no part in choosing it, swept −45 / −47.5 / −50 / −52.5 / −55:

| fixture | reading at −50 dB | comment |
| --- | --- | --- |
| tilted spectrum −6 dB/oct to 20 kHz | 20 016 | kept |
| **tilted spectrum −12 dB/oct to 20 kHz** | **9 000** | the −50 dB crossing of the tilt: 500 · 2^(50/12) = 9 000 Hz **exactly** |
| bass dominant +30 dB + band −30 dB | 16 031 | §12.11 |
| narrow band, one tone at 19.5 kHz | 19 523 | a single tone is enough |
| wide band 16.5–23.5 kHz | 23 531 | kept |
| two regions, 0–8 kHz and 18–20 kHz | 20 016 | a spectral gap does not break it |
| gentle roll-off, knee 8 kHz, 24 dB/oct | 23 531 | no edge below Nyquist |
| pink-ish noise −3 dB/oct | 23 930 | full band, correctly |
| body + band + one isolated full-scale click | 20 016 | the click does not become the reference |

No fixture where −50 dB is worse than its neighbours. The −12 dB/oct row is the most instructive: the
reading tracks `500 · 2^(|T|/12)` across the whole sweep (6 492 / 7 500 / 9 000 / 10 500 / 12 000 Hz),
which is the threshold's definition working exactly, and a sharp reminder that **on a tilted spectrum the
reported frequency is the −50 dB point of the tilt, not the top of the content.**

### 12.9 Refutation 2 — the −60 dB eligibility gate does **not** survive

The gate was introduced in part A to stop digitally silent windows from qualifying. It turns out to be
doing two jobs at once, and they pull in opposite directions.

**Job A — reject a passage that is only noise floor.** Loud passage over 40 % of the file, then white
noise at the stated level and nothing else. A correct reading is ~16 000; 24 000 means the noise won:

| noise floor | gate −40 | −50 | **−60** | −70 | −80 | −90 | −100 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| −60 dBFS | 16 102 | 16 102 | **16 102** | 24 000 | 24 000 | 24 000 | 24 000 |
| −80 dBFS | 16 102 | 16 102 | **16 102** | 16 102 | 16 102 | 24 000 | 24 000 |
| −100 dBFS | 16 102 | 16 102 | **16 102** | 16 102 | 16 102 | 16 102 | 16 102 |

**Job B — keep a real quiet passage.** The same structure, but the second passage is real music with a
real 19–20 kHz band 30 dB under its own body. A correct reading is ~20 000:

| quiet passage | gate −40 | −50 | **−60** | −70 | −80 | −90 | −100 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| −50 dB | 16 102 | 20 016 | **20 016** | 20 016 | 20 016 | 20 016 | 20 016 |
| −70 dB | 16 102 | 16 102 | **16 102** | 20 016 | 20 016 | 20 016 | 20 016 |
| −90 dB | 16 102 | 16 102 | **16 102** | 16 102 | 16 102 | 20 016 | 20 016 |

**The two tables are exact mirror images.** They have to be: "a noise floor 70 dB down" and "real music
70 dB down" are the same measurement to a gate that only knows how far below the file's peak a window
sits. No value separates them.

So, against the criterion set for this turn — *does −60 dB make musically real sections disappear?* —
the answer is **yes, at 70 dB below the file's peak and below**. The gate is therefore **rejected as
specified**. What it actually is, and what any replacement will also be, is a **dynamic-range budget**:
*content in passages more than G dB below the file's loudest moment is not measured.* That is a
defensible thing to state and a wrong thing to leave implicit at G = 60.

### 12.10 Refutation 3 — the −120 dBFS floor is arbitrary, and a numeric condition is better

| the same real signal at | global peak | with the −120 floor | with no floor |
| --- | --- | --- | --- |
| −0 dB | −40 dBFS | 20 016 | 20 016 |
| −80 dB | −120 dBFS | 20 016 | 20 016 |
| **−100 dB** | **−140 dBFS** | **absent** | **20 016** |
| −140 dB | −180 dBFS | absent | 20 016 |
| −180 dB | −220 dBFS | absent | 24 000 (the harness's own 1e-12 magnitude clamp, not the signal) |

The floor **discards about 60 dB of range in which the measurement still works**. And it is not needed
for what it was introduced for: digital silence has total energy of **exactly 0.0**, while a real signal
180 dB down has energy 1.5 × 10⁻¹⁵ — the two are separated by a numeric condition with **no chosen dB
value at all**.

> **Absence when the file carries no energy**, not when it falls below a picked level.

One thing a relative gate cannot do, confirmed: for an all-silent file every window peak equals the
global peak, so their *ratio* is 0 dB and no relative rule excludes them. The absence test has to be
absolute — but it can be numeric rather than acoustic.

### 12.11 The bass-dominance boundary is exactly the definition

A real 19–20 kHz band L dB below the body, with a 100 Hz tone D dB above the body. Prediction: the band
is kept while `|L| + D ≤ 50 dB`.

| band level | LF +0 | +10 | +20 | +30 | +40 |
| --- | --- | --- | --- | --- | --- |
| −40 dB | 20 016 | 19 500 (boundary) | 16 031 | 16 031 | 16 008 |
| −45 dB | 20 016 | 16 055 | 16 031 | 16 031 | 16 008 |
| −50 dB | 19 500 (boundary) | 16 055 | 16 031 | 16 031 | 16 008 |
| −55 dB | 16 102 | 16 055 | 16 031 | 16 031 | 16 008 |

The boundary falls on `|L| + D = 50` in every cell. **R7 is not a defect and not a surprise**: a
peak-relative threshold measures *prominence*, not presence, and 50 dB of prominence is what was chosen.
The finding to carry forward is the wording, not a fix — the quantity is "content within 50 dB of the
loudest thing happening at the same moment", and calling that "the highest frequency present" would be
false.

### 12.12 Roll-off, confirmed window-independent

The reading is `knee · 2^(|T| / slope)`, and it does **not** move with the analysis window — measured at
both 2048/512 and 4096/1024, agreeing to within one 500 Hz fixture step:

| knee | slope | predicted | 2048/512 | 4096/1024 |
| --- | --- | --- | --- | --- |
| 8 kHz | 6 / 12 / 24 dB/oct | > Nyquist | 23 555 / 23 531 / 23 531 | 23 531 / 23 520 / 23 508 |
| 8 kHz | 48 | 16 469 | 16 008 | 15 996 |
| 8 kHz | 96 | 11 478 | 11 016 | 11 004 |
| 8 kHz | 480 | 8 599 | 8 508 | 8 508 |
| 16 kHz | 6 … 48 | > Nyquist | 23 531 – 23 578 | 23 520 – 23 543 |
| 16 kHz | 96 | 22 957 | 22 500 | 22 500 |
| 16 kHz | 480 | 17 198 | 17 016 | 17 004 |

**Significant maximum frequency ≠ cut-off frequency**, quantitatively: at 48 kHz with a 16 kHz knee,
anything gentler than about 85 dB/octave has no edge below Nyquist at all.

### 12.13 Where part B leaves the five parameters

| parameter | status after part B |
| --- | --- |
| reference: per-window spectral peak | unchanged, and re-validated at the new window |
| threshold −50 dB | **survives** refutation on nine new fixtures (§12.8) |
| persistence ≥ 10 % of eligible windows | **survives**, and is now portable across rates *provided* the window is time-locked (§12.5) |
| eligibility gate −60 dB | **rejected as specified** (§12.9). It is a dynamic-range budget, not a silence test, and 60 dB is too little |
| absolute floor −120 dBFS | **replaced** by "the file carries no energy" (§12.10) |
| analysis window | **decided**: time-locked ≈ 42.67 ms, nearest vDSP-supported length per rate, hop = fftSize/4 |

All eight of part A's pre-registered constraints were re-checked at the new window (2048/512 at 48 kHz)
and all eight still pass.

## 13. What group 1 still requires

- **1.5 the resolution claim** — the ≈ 4-bin overshoot is measured (§7); still to decide is whether the
  reported value is a bin centre, a bin edge or a range, paired with the analytic Hann main-lobe figure
  rather than the empirical one alone.
- **1.6 constants with sources** — §11 is the table, but it cannot be called complete while 1.5's
  constant does not exist.
- Everything in groups 2–5, unchanged. In particular: real files rather than in-memory buffers, the rate
  matrix, container and codec equivalence, chunk independence, and cost as a sixth consumer.

ADR-0023 stays **Proposed**. Two of its three promotion conditions — an impulse control passing against
*production* code, and human validation of the surface — are untouched by this session.

## 13b. Part C — the eligibility semantics, and what they cost

Part B rejected the −60 dB gate. Part C tests the hypothesis that replaces it: **there is no level gate
at all.** A window participates if it carries energy; the threshold decides prominence *inside* a
window; persistence decides repetition *between* windows. Three layers, three different questions, none
substituting for another.

### 13b.1 The numeric boundary is real, and there is no epsilon in it

| question | measured |
| --- | --- |
| does `FFT(zeros)` give exactly zero? | **yes** — windowed samples all exactly 0, max magnitude `0.0` |
| where does squaring lose a sample? | in `Float`, below ≈1e-19 the square underflows to 0; accumulated in `Double` it survives to ≈1e-154 |
| `Float.leastNormalMagnitude` | 1.175e-38 → −758.6 dBFS |
| `Float.leastNonzeroMagnitude` | 1e-45 → −897.1 dBFS (denormal) |
| smallest sine that survives window + transform | **−280 dBFS**, peak bin 5.0e-15, still non-zero |

So "the window carries energy" is decidable **with no chosen constant**, provided the energy is
accumulated in `Double`; the boundary then belongs to the sample type, not to the accumulator, because
any non-zero `Float` has a non-zero `Double` square.

### 13b.2 Level invariance is total once the floor is gone

The same spectral structure, scaled bodily, with **no floor of any kind** and no magnitude clamp:

| level | −0 | −40 | −80 | −120 | −160 | −200 | −240 dB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| reading | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 | 20 016 | **20 016** |

Part B's observation that a signal below −180 dBFS "degraded" was an artefact of that harness's 1e-12
magnitude clamp, not of the arithmetic. **The −120 dBFS floor was invention twice over**: unnecessary,
and masking 120 dB of range in which the measurement is exact.

Three edge cases, recorded because two of them are surprising:

| case | eligible windows | reading |
| --- | --- | --- |
| samples exactly zero | 0 / 465 | **absent** ✔ |
| one denormal sample (1e-45) in an otherwise zero file | 0 / 465 | **absent** — the Hann multiply underflows it to zero, so the analysis genuinely cannot see it |
| every sample denormal (a constant) | 465 / 465 | **0 Hz** — a constant is DC, and DC is the highest qualifying bin |
| real signal at −200 dBFS | 465 / 465 | 20 016 ✔ |

The DC row matters for the domain model: ADR-0023 says zero is not a result, and here the measurement
legitimately produces one. Task 4.4 has to say what happens to it.

### 13b.3 Without a gate, real quiet content is measured — which is the point

First half loud, second half the same body X dB lower plus a real 19–20 kHz band 30 dB under *that*:

| second half | −40 dB | −60 dB | −80 dB | −100 dB | −120 dB |
| --- | --- | --- | --- | --- | --- |
| **no gate** | 20 016 | 20 016 | **20 016** | **20 016** | **20 016** |
| gate −60 dB | 20 016 | 20 016 | 16 102 | 16 102 | 16 102 |

The hypothesis does exactly what it was proposed to do, and does it at any depth.

### 13b.4 Where it breaks, and the break is not about level

**Noise judged against a programme is handled correctly.** Body to 16 kHz present in every window, plus
random noise from 16 kHz to Nyquist: counted at −40 and −50 dB (correctly — it is within the stated
prominence), rejected at −60 dB and below. This case never threatened the hypothesis.

**Noise alone in its own windows is the failure.** A window containing nothing but a noise floor makes
that noise floor its own reference, so the noise is 0 dB from its own peak and every bin qualifies:

| share of the file that is noise-only | 2 % | 5 % | 8 % | 10 % | **12 %** | 20 % | 40 % |
| --- | --- | --- | --- | --- | --- | --- | --- |
| reading | 16 102 | 16 102 | 16 102 | 16 195 | **24 000** | 24 000 | 24 000 |

The threshold is exactly the persistence constant, which is the criterion working as designed. What is
**not** defensible is the next table — the same 40 % noise-only tail at every conceivable level:

| noise level | −40 | −60 | −90 | −120 | −150 | **−200 dBFS** |
| --- | --- | --- | --- | --- | --- | --- |
| reading | 24 000 | 24 000 | 24 000 | 24 000 | 24 000 | **24 000** |

**A signal 200 dB below the programme decides the reported bandwidth, because it happens to be alone in
its window.** No amount of restating the definition makes that a useful fact.

### 13b.5 What a noise floor's bandwidth actually is

| whole-file content | reading |
| --- | --- |
| digital silence | **absent** ✔ |
| white noise at −80 / −100 / −120 dBFS | 24 000 in all three |
| pink-ish noise, −3 dB/octave | 23 977 |
| 50 Hz hum + white noise 30 dB under it | **398 Hz** — the hum is the programme and the noise is 60 dB under it, so it is correctly excluded |
| **band-limited noise floor, to 16 kHz** | **16 102** ✔ |

The last row is the one that saves the feature's purpose: a *band-limited* noise floor — which is what a
lossy codec leaves behind — is read correctly even when it is all there is. The metric does not need a
programme to detect a band limit; it needs one to ignore a broadband floor.

### 13b.6 The collector's four files (phase 11)

96 kHz masters, music to 22 kHz, 42.67 ms window:

| scenario | reading | is it the fact wanted? |
| --- | --- | --- |
| 1. music to 22 kHz, digital silence above | 22 102 | yes |
| 1b. the same with a 15 % digitally silent tail | 22 102 | yes |
| **2. the same + analog hiss to 48 kHz, no quiet passage** | **22 102** | **yes** — a hiss well under the programme per bin is excluded by the threshold |
| 2b. the same, with a 15 % hiss-only tail | **48 000** | **no** |
| 2c. the same, with a 5 % hiss-only tail | 22 102 | yes |
| 2d. band-limited hiss (to 22 kHz), 15 % tail | 22 102 | yes |
| 3. music to 22 kHz + weak codec spurs above | 26 016 | yes |
| 4. real weak musical content 22.5–30 kHz | 30 023 | yes |

**Seven of eight are right.** The failure is narrow and specific: a *broadband* floor that is *alone* in
more than 10 % of the file. It is not "any noisy file" — an analog transfer that plays continuously
reads correctly.

### 13b.7 Can anything separate a noise floor from noise-like content? (phase 12)

Spectral flatness, over a band all three signals occupy, all three calibrated to the **same per-bin
level** so only shape differs:

| signal in 25–35 kHz | per-bin peak | flatness |
| --- | --- | --- |
| broadband analog hiss (true white noise) | −58.1 dB | **0.564** |
| band-limited noise 22.5–40 kHz — "air", cymbals | −58.1 dB | **0.564** |
| tonal spurs every 1 kHz (codec, resampler) | −58.1 dB | 0.000 |

**Identical to three decimals.** Flatness separates *tonal* artefacts from noise, which is a different
and possibly useful question, and it does not separate the two things that needed separating: a tape
hiss and a cymbal are the same kind of signal. Two earlier attempts at this probe were discarded as
confounded — one measured a tone comb's spacing, the other a band the signal only partly occupied — and
neither is reported as evidence.

A persistence *curve* was tried as a richer representation: read the same measurement at ≥10 %, ≥50 %
and ≥90 %. It genuinely adds information — it separates persistent content from intermittent — but it
does not separate noise from content either, because noise-like content fluctuates bin by bin and so
thins out at high persistence exactly as a noise floor does.

### 13b.8 Why no rule of this shape can work

Three independent attempts converge on one structural fact:

> A window that contains only a noise floor is indistinguishable, **from inside itself**, from a window
> that contains only quiet music. The difference exists only in comparison with the rest of the file,
> and any comparison with the rest of the file is a **dynamic-range budget**.

- a *level gate* is that comparison, made explicit — rejected in part B for having no defensible value;
- *flatness* is not that comparison, and measures something else;
- a *persistence curve* is not that comparison, and measures something else.

So the choice in phase 9 is **B**, not A: the metric as hypothesised measures any real signal, noise
floor included, and to mean "programme content" it needs a cross-window comparison. That comparison is a
**declared parameter of the measurement**, not a constant to be discovered — and that is a materially
better position than part B ended in, where it was an undeclared constant.

Rejected while here: making the budget adaptive (derived from the file's own dynamic range or its
loudness range). It would break the rule that the same method identity must imply the same number, since
identical content in two files would then be measured against two different budgets.

### 13b.9 The name

If option A were taken, **"significant bandwidth" would be a misleading name**: a −200 dBFS floor
determining the answer is not "significant" in any sense a reader would grant. Under option B the name
is only honest once the budget is part of it. Candidates, none adopted, no API exists yet:

- *persistent spectral extent* — accurate, and silent about significance;
- *highest persistent spectral frequency* — accurate and long;
- *programme bandwidth (within N dB of programme peak)* — carries the budget in the name, which is the
  only version that stays true under option B.

## 13c. Part D — the decision, and a simplification that came with it

The budget is a product declaration, and it was made: **60 dB**. The metric is named **programme
bandwidth**. What follows is the validation of the whole rule set as one thing — every earlier run
exercised one rule at a time — and a correction to part C that the validation produced.

### 13c.1 The correction: there are two rules, not three, and one of them needs no constant

Part C proposed a file-level numeric test ("absence when the file carries no energy") alongside the
per-window eligibility test. Switching the two independently shows the file-level test is **redundant**:

| file | wanted | both rules | budget only | numeric only | neither |
| --- | --- | --- | --- | --- | --- |
| digital silence | absent | absent | **absent** | absent | **absent** |
| 60 % body + 40 % digital silence | 16 000 | 16 102 | 16 102 | 16 102 | **16 102** |
| 40 % broadband noise-floor tail | 16 000 | 16 102 | 16 102 | 24 000 | 24 000 |
| real music 70 dB down in the second half | (the cost) | 16 102 | 16 102 | 20 016 | 20 016 |

Row 1 is absent in **every** column, including the one with no rules at all. A window of zeros
transforms to magnitude exactly zero, which is `-infinity` in dB, so the per-window eligibility test
already excludes it and absence falls out with nothing added.

**The P8 failure that started all of this was caused by a magnitude clamp**, not by the method. Part A's
harness floored magnitudes at 1e-12, which turned a silent window into −240 dB and therefore into a
window with a reference. Remove the clamp and silence solves itself. That makes the clamp a
**methodological requirement rather than an implementation detail**: a production accumulator must not
floor its magnitudes, or it reintroduces the failure.

Rows 3 and 4 show what the budget is actually for, and it is one thing only: the broadband
noise-floor-alone case. Row 2 needs no budget either.

So the final rule set is:

1. **Eligibility — no constant.** A window is an observation if it carries energy. This handles digital
   silence, partial silence and absence, all of it, automatically.
2. **Budget — one declared constant, 60 dB.** A window must sit within 60 dB of the file's spectral peak
   to contribute. This handles the broadband noise floor, and nothing else needs it.
3. **Significance — −50 dB** relative to that window's own peak.
4. **Persistence — ≥ 10 %** of eligible windows.

### 13c.2 The whole method, validated once, with every rule active

48 kHz, FFT 2048 / hop 512 (42.67 ms, 75 % overlap), periodic Hann, no magnitude clamp:

| | constraint | reading |
| --- | --- | --- |
| PASS | P1 gain invariance (0 / −20 / −40 dB) | 20 016 / 20 016 / 20 016 |
| PASS | P2 a click does not reach Nyquist | 16 102 |
| PASS | P3a loud but rare band (−20 dB, 1 %) | 16 102 |
| PASS | P3b full-band bursts totalling 1 % | 16 102 |
| PASS | P4 persistent −30 dB band is kept | 20 016 |
| PASS | P5 continuous −80 dB noise ignored | 16 102 |
| PASS | P6a / P6b hard cut-offs at 16 and 20 kHz | 16 102 / 20 086 |
| PASS | P7 a loud LF event keeps the band | 20 016 |
| PASS | P8 digital silence reports absence | absent |
| PASS | X1 partial digital silence | 16 102 |
| PASS | X2 partial silence keeps a real band | 20 086 |

**Twelve of twelve, with the full rule set active for the first time.**

### 13c.3 The declared cost, as a table the record owns

Loud first half; second half X dB lower, carrying a real 19–20 kHz band:

| quiet passage | −30 | −40 | −50 | **−60** | **−70** | −80 | −90 dB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| reading | 20 016 | 20 016 | 20 016 | **20 016** | **16 102** | 16 102 | 16 102 |
| measured? | yes | yes | yes | **yes** | **no** | no | no |

> **Content in passages more than 60 dB below a file's loudest spectral moment is not measured, and a
> noise floor further down than that does not count as content.** The two halves of that sentence are
> the same rule; there is no setting that keeps one and drops the other.

And what the budget buys, on the case that motivated it — 40 % of the file a broadband floor and nothing
else:

| noise floor | −40 | −60 | −70 | −90 | −120 | −200 dBFS |
| --- | --- | --- | --- | --- | --- | --- |
| with the budget | 24 000 | **16 102** | 16 102 | 16 102 | 16 102 | **16 102** |
| without | 24 000 | 24 000 | 24 000 | 24 000 | 24 000 | 24 000 |

The −40 dBFS row still reads 24 000, and correctly: a floor that loud is within the budget and within
the prominence threshold, so it *is* programme. A band-limited floor alone still reads its own limit
(16 102), which is the case the feature exists for.

### 13c.4 The name

**Programme bandwidth**, stated in full as *"programme bandwidth, within 60 dB of programme peak"*. It
carries the budget in the name, so it stays true if the budget is ever changed, and it does not claim
the significance that "significant bandwidth" would. *Persistent spectral extent* was the accurate
alternative but is silent about the budget, which is the one thing a reader must not have to guess.

## 14. Stopping rule — **GO for the accumulator**

Nine conditions were set for authorising group 2. Seven are met:

1. Hann explained analytically — **met** (§12.1, verified to 0.000 dB against the DTFT).
2. A defensible uncertainty — **met** (§12.2–12.4), including the falsification of the contract that
   looked derivable.
3. Window and hop defensible — **met** (§12.5, §12.7).
4. Persistence portable across rates — **met, conditionally**: it is portable *because* the window is
   time-locked, and demonstrably is not otherwise (§12.5).
5. −50 dB survived refutation — **met** (§12.8).
8. R7 understood and documented — **met** (§12.11).
9. Roll-off understood as expected behaviour — **met** (§12.12).

Two were not, and both are now resolved by part D:

6. **The −60 dB eligibility rule is a declaration, not a discovery** (§12.9, §13c). It erases real
   content in passages more than 60 dB below the file's peak, and no value can separate a quiet passage
   from a noise floor at the same level. It is therefore stated as a budget, with its cost tabulated
   (§13c.3), and carried in the metric's own name.
7. **The −120 dBFS floor is deleted, not replaced** (§12.10, §13c.1). An unclamped transform makes a
   silent window ineligible by itself, so no absolute rule of any kind is required.

Item 6 is structural, so the accumulator is not authorised. It is not a defect in the threshold or the
persistence criterion — both survived — but in the rule that decides *which windows are looked at*, and
that rule sits upstream of everything else.

**Part C did not lift the NO-GO, and narrowed it to one sentence.** The gateless hypothesis is
numerically clean, needs no invented constant, and gets seven of the collector's eight files right. It
fails on one: a broadband noise floor alone in more than 10 % of a file sets the answer, **at any level,
down to 200 dB below the programme**. Nothing inside a window can tell that floor from quiet music, and
every rule that can is a dynamic-range budget. So the remaining decision was not a measurement — it was
**what the product declares it is looking at**.

**Part D closed it.** The declaration was made — 60 dB, with the cost written down in §13c.3 rather than
discovered later — and the rule that carries it turned out to be the only constant the method needs
beyond the three already settled. Item 6 is decided rather than refuted, and item 7 dissolved: the
absolute floor is not replaced by a numeric condition, it is **not needed at all**, because an unclamped
transform makes a silent window ineligible on its own.

All nine conditions are now met, and the full rule set passes twelve of twelve constraints in a single
validation. **The accumulator is authorised**, subject to the change's own ordering: group 2's fixtures
and oracle come before group 3's accumulator, and nothing here has touched a real file, a container, a
codec, or the production decode path.
