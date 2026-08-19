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

## 12. What group 1 still requires

- **1.5 the resolution claim** — the ≈ 4-bin overshoot is measured (§7); still to decide is whether the
  reported value is a bin centre, a bin edge or a range, paired with the analytic Hann main-lobe figure
  rather than the empirical one alone.
- **1.6 constants with sources** — §11 is the table, but it cannot be called complete while 1.5's
  constant does not exist.
- Everything in groups 2–5, unchanged. In particular: real files rather than in-memory buffers, the rate
  matrix, container and codec equivalence, chunk independence, and cost as a sixth consumer.

ADR-0023 stays **Proposed**. Two of its three promotion conditions — an impulse control passing against
*production* code, and human validation of the surface — are untouched by this session.
